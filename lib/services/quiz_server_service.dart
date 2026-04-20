import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'quiz_user_service.dart';
import 'supabase_clients.dart';

class QuizServerService {
  static final QuizServerService _instance = QuizServerService._internal();
  factory QuizServerService() => _instance;
  QuizServerService._internal();

  HttpServer? _server;
  final List<WebSocketChannel> _clients = [];
  final Map<WebSocketChannel, String> _clientIds = {};
  final Map<WebSocketChannel, String> _clientNames = {};
  final Map<WebSocketChannel, String> _clientAvatars =
      {}; // Store base64 avatars

  // Quiz State
  List<Map<String, dynamic>>? _questions;
  int _currentQuestionIndex = -1; // -1: Not started/Waiting
  bool _isShowingAnswer = false;
  // Updated answers map to store more info: qIndex -> optionIndex -> List of {name, avatar}
  final Map<int, Map<int, List<Map<String, String>>>> _detailedAnswers = {};

  String? _hostIp;
  int _port = 8080;

  Future<String?> get localIp async {
    if (kIsWeb) return 'localhost';
    try {
      final info = NetworkInfo();
      return await info.getWifiIP();
    } catch (e) {
      return '127.0.0.1';
    }
  }

  Future<void> startServer(List<Map<String, dynamic>> questions) async {
    if (kIsWeb) {
      throw '抱歉，本地答题服务器功能仅支持在 Android/iOS/Windows/macOS 客户端上运行，无法在 Web 模式下启动服务器。';
    }
    await stopServer();
    await WakelockPlus.enable();
    _questions = questions;
    _currentQuestionIndex = -1;
    _isShowingAnswer = false;
    _detailedAnswers.clear();
    _clients.clear();
    _clientIds.clear();
    _clientNames.clear();
    _clientAvatars.clear();

    _hostIp = await localIp ?? '127.0.0.1';

    var handler = const Pipeline()
        .addMiddleware(logRequests())
        .addHandler(_combinedHandler);

    _server = await io.serve(handler, InternetAddress.anyIPv4, _port);
    print('Quiz Server running on http://$_hostIp:$_port');
  }

  Future<void> stopServer() async {
    for (var client in _clients) {
      client.sink.close();
    }
    await _server?.close(force: true);
    _server = null;
    await WakelockPlus.disable();
  }

  FutureOr<Response> _combinedHandler(Request request) {
    if (request.url.path == 'ws') {
      return webSocketHandler((WebSocketChannel webSocket, String? protocol) {
        _handleWebSocket(webSocket);
      })(request);
    }

    if (request.url.path == 'api/leaderboard') {
      return _handleLeaderboardApi(request);
    }

    return Response.ok(
      _generateHtmlContent(),
      headers: {'content-type': 'text/html; charset=utf-8'},
    );
  }

  Future<Response> _handleLeaderboardApi(Request request) async {
    final limitRaw = request.url.queryParameters['limit'];
    final offsetRaw = request.url.queryParameters['offset'];

    final limit = (int.tryParse(limitRaw ?? '') ?? 6).clamp(1, 6);
    final offset = (int.tryParse(offsetRaw ?? '') ?? 0).clamp(0, 1000000);

    try {
      final rows = await serviceSupabase
          .from('quiz_users')
          .select('id, name, image, score')
          .order('score', ascending: false)
          .order('id', ascending: true)
          .range(offset, offset + limit);

      final hasMore = rows.length > limit;
      final items = rows.take(limit).toList().asMap().entries.map((entry) {
        final idx = entry.key;
        final r = entry.value;
        return {
          'user_id': r['id'],
          'name': r['name'],
          'avatar_url': r['image'],
          'score': r['score'],
          'rank': offset + idx + 1,
        };
      }).toList();

      return Response.ok(
        jsonEncode({'items': items, 'hasMore': hasMore}),
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
  }

  void _handleWebSocket(WebSocketChannel webSocket) {
    _clients.add(webSocket);

    webSocket.stream.listen(
      (message) async {
        final Map<String, dynamic> data;
        try {
          data = jsonDecode(message) as Map<String, dynamic>;
        } catch (_) {
          return;
        }
        final type = data['type'];

        switch (type) {
          case 'join':
            final rawName = data['name'];
            final name = (rawName as String?)?.trim();
            final avatar = data['avatar'];
            if (name == null || name.isEmpty) {
              webSocket.sink.add(
                jsonEncode({'type': 'error', 'message': '昵称不能为空'}),
              );
              return;
            }
            if (_clientNames.values.contains(name)) {
              webSocket.sink.add(
                jsonEncode({'type': 'error', 'message': '姓名已存在'}),
              );
              return;
            }
            final avatarDataUrl = (avatar as String?) ?? '';
            QuizUserCreateResult joinResp;
            try {
              joinResp = await QuizUserService.createUser(
                name: name,
                avatarDataUrl: avatarDataUrl,
              );
            } catch (e) {
              if (e.toString().contains('NAME_CONFLICT')) {
                webSocket.sink.add(
                  jsonEncode({'type': 'error', 'message': '该昵称存在冲突，请更换昵称'}),
                );
                return;
              }
              webSocket.sink.add(
                jsonEncode({'type': 'error', 'message': '加入失败，请重试'}),
              );
              return;
            }

            _clientNames[webSocket] = name;
            _clientIds[webSocket] = joinResp.id;
            _clientAvatars[webSocket] = joinResp.imageUrl ?? avatarDataUrl;
            webSocket.sink.add(
              jsonEncode({
                'type': 'join_ack',
                'inherited': joinResp.inherited,
                'score': joinResp.score,
                'rank': joinResp.rank,
              }),
            );
            _broadcastState();
            break;
          case 'submit_answer':
            if (_currentQuestionIndex >= 0 && !_isShowingAnswer) {
              final rawOptionIndex = data['optionIndex'];
              final optionIndex = switch (rawOptionIndex) {
                int v => v,
                num v => v.toInt(),
                String v => int.tryParse(v),
                _ => null,
              };
              if (optionIndex == null) {
                return;
              }
              final name = _clientNames[webSocket];
              final avatar = _clientAvatars[webSocket];

              if (name != null) {
                _detailedAnswers[_currentQuestionIndex] ??= {};

                // Prevent duplicates: Check if user already answered this question
                bool alreadyAnswered = false;
                _detailedAnswers[_currentQuestionIndex]!.values.forEach((list) {
                  if (list.any((item) => item['name'] == name))
                    alreadyAnswered = true;
                });

                if (!alreadyAnswered) {
                  _detailedAnswers[_currentQuestionIndex]![optionIndex] ??= [];
                  _detailedAnswers[_currentQuestionIndex]![optionIndex]!.add({
                    'name': name,
                    'avatar': avatar ?? '',
                  });
                  _broadcastState();

                  final q = _questions?[_currentQuestionIndex];
                  final correctIndex = q?['answerIndex'];
                  if (correctIndex is int && optionIndex == correctIndex) {
                    final id = _clientIds[webSocket];
                    if (id != null) {
                      await QuizUserService.incrementScore(id);
                    }
                  }
                }
              }
            }
            break;
          case 'host_start_quiz':
            _currentQuestionIndex = 0;
            _isShowingAnswer = false;
            _broadcastState();
            break;
          case 'host_show_answer':
            _isShowingAnswer = true;
            _broadcastState();
            break;
          case 'host_next_question':
            if (_currentQuestionIndex < (_questions?.length ?? 0) - 1) {
              _currentQuestionIndex++;
              _isShowingAnswer = false;
              _broadcastState();
            } else {
              _currentQuestionIndex = -2; // Finished
              _broadcastState();
            }
            break;
        }
      },
      onDone: () {
        _clients.remove(webSocket);
        _clientIds.remove(webSocket);
        _clientNames.remove(webSocket);
        _clientAvatars.remove(webSocket);
        _broadcastState();
      },
    );

    _sendStateTo(webSocket);
  }

  void _broadcastState() {
    final state = _getStateJson();
    final jsonString = jsonEncode(state);
    for (var client in _clients) {
      client.sink.add(jsonString);
    }
  }

  void _sendStateTo(WebSocketChannel webSocket) {
    webSocket.sink.add(jsonEncode(_getStateJson()));
  }

  Map<String, dynamic> _getStateJson() {
    final Map<String, List<Map<String, String>>> answersJson = {};
    _detailedAnswers[_currentQuestionIndex]?.forEach((key, value) {
      answersJson[key.toString()] = value;
    });

    // Collect all joined users with avatars
    final List<Map<String, String>> joinedUsers = [];
    _clientNames.forEach((socket, name) {
      joinedUsers.add({'name': name, 'avatar': _clientAvatars[socket] ?? ''});
    });

    return {
      'type': 'state_update',
      'hostIp': _hostIp,
      'port': _port,
      'clientCount': _clients.length,
      'joinedUsers': joinedUsers,
      'currentQuestionIndex': _currentQuestionIndex,
      'isShowingAnswer': _isShowingAnswer,
      'currentQuestion':
          _currentQuestionIndex >= 0 &&
              _currentQuestionIndex < (_questions?.length ?? 0)
          ? _questions![_currentQuestionIndex]
          : null,
      'answers': answersJson,
      'totalQuestions': _questions?.length ?? 0,
    };
  }

  String _generateHtmlContent() {
    return _htmlTemplate;
  }

  String get _htmlTemplate => '''
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>青春答题派对</title>
    <script src="https://cdn.jsdelivr.net/npm/qrcodejs@1.0.0/qrcode.min.js"></script>
    <style>
        :root {
            --primary: #FF6B6B;
            --secondary: #4ECDC4;
            --accent: #FFE66D;
            --bg-gradient: linear-gradient(135deg, #FF9A9E 0%, #FAD0C4 99%, #FAD0C4 100%);
        }
        
        body { 
            font-family: 'PingFang SC', sans-serif; 
            margin: 0; 
            overflow-x: hidden;
            background: var(--bg-gradient);
            min-height: 100vh;
            color: #2D3436;
        }

        /* 粒子背景 */
        #particles {
            position: fixed;
            top: 0; left: 0; width: 100%; height: 100%;
            z-index: -1;
            pointer-events: none;
        }

        .container { 
            width: 90%; 
            max-width: 500px; 
            margin: 20px auto;
            background: rgba(255, 255, 255, 0.9);
            backdrop-filter: blur(10px);
            padding: 25px;
            border-radius: 30px; 
            box-shadow: 0 15px 35px rgba(0,0,0,0.1);
            position: relative;
        }
        .container.lb-padding { padding-bottom: 240px; }

        /* 波浪文字动画 */
        .wave-text {
            display: flex;
            justify-content: center;
            font-size: 28px;
            font-weight: bold;
            color: var(--primary);
            margin: 20px 0;
        }
        .wave-text span {
            display: inline-block;
            animation: wave 1.2s infinite ease-in-out;
        }
        @keyframes wave {
            0%, 100% { transform: translateY(0); }
            50% { transform: translateY(-8px); }
        }
        .wave-text span:nth-child(1) { animation-delay: 0.1s; }
        .wave-text span:nth-child(2) { animation-delay: 0.2s; }
        .wave-text span:nth-child(3) { animation-delay: 0.3s; }
        .wave-text span:nth-child(4) { animation-delay: 0.4s; }
        .wave-text span:nth-child(5) { animation-delay: 0.5s; }
        .wave-text span:nth-child(6) { animation-delay: 0.6s; }

        .btn {
            background: var(--primary);
            color: white;
            border: none;
            padding: 15px 30px;
            border-radius: 50px;
            font-size: 18px;
            font-weight: bold;
            width: 100%;
            cursor: pointer;
            transition: all 0.3s;
            box-shadow: 0 5px 15px rgba(255, 107, 107, 0.3);
        }
        .btn:active { transform: scale(0.95); }

        /* 头像组件 */
        .avatar-upload {
            width: 120px;
            height: 120px;
            margin: 0 auto 20px;
            position: relative;
            border-radius: 50%;
            border: 4px solid white;
            overflow: hidden;
            background: #eee;
            cursor: pointer;
        }
        .avatar-upload img { width: 100%; height: 100%; object-fit: cover; }
        .avatar-hint {
            position: absolute;
            bottom: 0; width: 100%;
            background: rgba(0,0,0,0.5);
            color: white;
            font-size: 12px;
            text-align: center;
            padding: 4px 0;
        }

        /* 柱状图样式 */
        .chart-container {
            display: flex;
            justify-content: space-around;
            align-items: flex-end;
            height: 250px;
            margin: 40px 0;
            padding: 20px;
            background: rgba(255,255,255,0.5);
            border-radius: 20px;
            border-bottom: 3px solid #ddd;
        }
        .bar-group {
            display: flex;
            flex-direction: column;
            align-items: center;
            flex: 1;
            height: 100%;
            justify-content: flex-end;
            cursor: pointer;
        }
        .bar-stack {
            width: 50px;
            display: flex;
            flex-direction: column-reverse;
            border-radius: 8px 8px 0 0;
            overflow: hidden;
            transition: height 0.5s cubic-bezier(0.175, 0.885, 0.32, 1.275);
            background: #eee;
        }
        .bar-segment {
            width: 100%;
            transition: height 0.5s ease;
        }
        .segment-dark { background: #12B0C4; }
        .segment-medium { background: #00D2D3; }
        .segment-light { background: #84E3E3; }
        
        .bar-label {
            margin-top: 10px;
            font-weight: bold;
            color: #2D3436;
        }
        .bar-count {
            font-size: 12px;
            color: #666;
            margin-bottom: 5px;
        }
        .correct-indicator {
            color: #52c41a;
            font-size: 12px;
            margin-top: 2px;
            font-weight: bold;
        }

        /* 主持人入口样式 */
        #host-entry-screen {
            text-align: center;
        }
        .qr-wrapper {
            background: white;
            padding: 20px;
            border-radius: 20px;
            display: inline-block;
            margin: 20px 0;
            box-shadow: 0 10px 25px rgba(0,0,0,0.1);
        }

        /* 模态框 */
        .modal {
            position: fixed;
            top: 0; left: 0; width: 100%; height: 100%;
            background: rgba(0,0,0,0.6);
            display: none;
            justify-content: center;
            align-items: center;
            z-index: 1000;
        }
        .modal-content {
            background: white;
            width: 85%;
            max-width: 400px;
            border-radius: 25px;
            padding: 20px;
            max-height: 80vh;
            overflow-y: auto;
        }
        .user-grid {
            display: grid;
            grid-template-columns: repeat(3, 1fr);
            gap: 15px;
            margin-top: 15px;
        }
        .user-item { text-align: center; }
        .user-avatar {
            width: 50px; height: 50px;
            border-radius: 50%;
            object-fit: cover;
            margin-bottom: 5px;
        }
        .user-name { font-size: 12px; color: #666; }

        .hidden { display: none !important; }
        
        /* 吉祥物 */
        .mascot {
            width: 100px;
            display: block;
            margin: 0 auto;
            animation: bounce 2s infinite;
        }
        @keyframes bounce {
            0%, 100% { transform: translateY(0); }
            50% { transform: translateY(-10px); }
        }

        .leaderboard-panel {
            position: fixed;
            left: 50%;
            transform: translateX(-50%) translateY(16px);
            bottom: 12px;
            width: min(520px, calc(100% - 24px));
            background: rgba(255, 255, 255, 0.96);
            backdrop-filter: blur(10px);
            border-radius: 24px;
            box-shadow: 0 15px 35px rgba(0,0,0,0.12);
            padding: 14px;
            z-index: 2000;
            opacity: 0;
            pointer-events: none;
            transition: transform 240ms ease, opacity 240ms ease;
        }
        .leaderboard-panel.visible {
            opacity: 1;
            pointer-events: auto;
            transform: translateX(-50%) translateY(0);
        }

        .leaderboard-header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 10px;
            margin-bottom: 10px;
        }

        .leaderboard-title {
            font-size: 16px;
            font-weight: 800;
            color: var(--primary);
            margin: 0;
        }

        .leaderboard-error {
            font-size: 12px;
            color: #d63031;
            text-align: center;
            margin: 14px 0;
        }

        .leaderboard-skeleton {
            display: grid;
            gap: 10px;
        }

        .skeleton-line {
            height: 14px;
            border-radius: 8px;
            background: linear-gradient(90deg, #eee 0%, #f6f6f6 40%, #eee 80%);
            background-size: 200% 100%;
            animation: sk 1.1s infinite linear;
        }

        @keyframes sk {
            from { background-position: 200% 0; }
            to { background-position: -200% 0; }
        }

        .podium-grid {
            display: grid;
            grid-template-columns: repeat(3, 1fr);
            gap: 10px;
            align-items: end;
            margin-top: 6px;
        }

        .podium-card {
            text-align: center;
        }

        .podium-svg {
            width: 100%;
            height: 120px;
            display: block;
        }

        .podium-bar {
            transform-origin: bottom;
            transform-box: fill-box;
            animation: rise 800ms cubic-bezier(0.175, 0.885, 0.32, 1.275) both;
        }

        @keyframes rise {
            from { transform: scaleY(0); }
            to { transform: scaleY(1); }
        }

        .medal {
            font-size: 18px;
            font-weight: 900;
        }

        .podium-avatar {
            width: 80px;
            height: 80px;
            border-radius: 50%;
            object-fit: cover;
            display: block;
            margin: 6px auto 6px;
            border: 3px solid rgba(0,0,0,0.06);
            background: #eee;
        }

        .podium-name {
            font-size: 16px;
            font-weight: 800;
            margin: 0;
            color: #2D3436;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }

        .podium-score {
            font-size: 20px;
            font-weight: 900;
            margin: 2px 0 0;
        }

        .score-gold { color: #FFD700; }
        .score-silver { color: #C0C0C0; }
        .score-bronze { color: #CD7F32; }

        .top10-list {
            margin-top: 12px;
            display: grid;
            gap: 10px;
        }

        .top10-row {
            display: grid;
            grid-template-columns: 28px 40px 1fr auto;
            align-items: center;
            gap: 10px;
            padding: 8px 10px;
            border-radius: 12px;
            transition: background 0.2s ease;
            background: rgba(255, 255, 255, 0.7);
            border: 1px solid rgba(0,0,0,0.04);
        }

        .top10-row:hover { background: rgba(255, 107, 107, 0.10); }

        .rank-num {
            font-size: 14px;
            color: #7A7A7A;
            font-weight: 700;
        }

        .row-avatar {
            width: 40px;
            height: 40px;
            border-radius: 50%;
            object-fit: cover;
            background: #eee;
        }

        .row-name {
            font-size: 14px;
            color: #2D3436;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }

        .row-score {
            font-size: 16px;
            font-weight: 800;
            color: #2D3436;
        }

        .leaderboard-more {
            margin-top: 12px;
        }

        .leaderboard-more button {
            width: 100%;
            border: none;
            background: #2D3436;
            color: #fff;
            border-radius: 14px;
            padding: 10px 12px;
            font-weight: 800;
            cursor: pointer;
        }

        .leaderboard-more button:active { transform: scale(0.98); }

        .inherit-status {
            font-size: 12px;
            color: #2D3436;
            background: rgba(18,176,196,0.12);
            border-radius: 12px;
            padding: 10px 12px;
            margin: 12px 0;
        }
    </style>
</head>
<body>
    <canvas id="particles"></canvas>
    
    <div id="app" class="container">
        <div id="leaderboard-panel" class="leaderboard-panel hidden" aria-label="排行榜">
            <div class="leaderboard-header">
                <h3 class="leaderboard-title">排行榜</h3>
            </div>
            <div id="leaderboard-body"></div>
        </div>
        <div id="ws-status" style="text-align:center; font-size:12px; color:#999; margin-bottom:10px"></div>

        <!-- 头像设置页面 -->
        <div id="avatar-screen">
            <h1 style="text-align:center">设置你的角色</h1>
            <div class="avatar-upload" onclick="triggerFile()">
                <img id="preview-img" src="https://api.dicebear.com/7.x/adventurer/svg?seed=Lucky">
                <div class="avatar-hint">点击上传</div>
            </div>
            <input type="file" id="file-input" class="hidden" accept="image/*" onchange="handleFile(this)">
            <input type="text" id="name-input" style="width:100%; padding:12px; border:2px solid #eee; border-radius:15px; margin-bottom:20px; box-sizing:border-box" placeholder="输入超酷的昵称">
            <button class="btn" onclick="joinWithAvatar()">准备好了！</button>
        </div>

        <!-- 主持人入口页面 -->
        <div id="host-entry-screen" class="hidden">
            <h1>准备开始派对！</h1>
            <div class="qr-wrapper">
                <div id="qrcode"></div>
            </div>
            <p>扫码加入答题队列</p>
            <p>当前小伙伴: <span id="host-wait-count">0</span> 人</p>
            <button class="btn" onclick="hostStartQuiz()">立即开始答题</button>
        </div>

        <div id="wait-screen" class="hidden">
            <h1 style="text-align:center">已加入派对</h1>
            <div id="inherit-status" class="inherit-status"></div>
            <p style="text-align:center; color:#666; margin:0">当前小伙伴: <span id="wait-count">0</span> 人</p>
            <div id="joined-users" class="user-grid" style="margin-top:18px"></div>
            <p style="text-align:center; color:#888; margin-top:18px">等待主持人开始答题...</p>
        </div>

        <!-- 答题页面 -->
        <div id="quiz-screen" class="hidden">
            <h2 id="q-text"></h2>
            <div id="options-container" style="display:grid; gap:15px"></div>
            <!-- 主持人查看进度 -->
            <div id="host-quiz-info" class="hidden" style="margin-top:20px; color:#666">
                已提交: <span id="submitted-count">0</span> / <span id="total-participants">0</span>
                <button class="btn" style="margin-top:20px" onclick="hostShowAnswer()">公布答案</button>
            </div>
        </div>

        <!-- 等待结果页面 (过渡页) -->
        <div id="transition-screen" class="hidden">
            <img class="mascot" src="https://api.dicebear.com/7.x/thumbs/svg?seed=Happy">
            <div class="wave-text">
                <span>等</span><span>待</span><span>答</span><span>案</span><span>公</span><span>布</span>
            </div>
            <p style="text-align:center; color:#888">你的答案已送达太空！</p>
        </div>

        <!-- 结果展示页 (主持人与用户共有) -->
        <div id="results-display" class="hidden">
            <h1 id="results-title">答题结果统计</h1>
            <div id="chart" class="chart-container"></div>
            
            <div id="host-next-btn" class="hidden">
                <button class="btn" onclick="hostNext()">下一题</button>
            </div>
            <p id="participant-wait-msg" class="hidden" style="text-align:center; color:#666">等待主持人进入下一题...</p>
        </div>

        <!-- 答题结束 -->
        <div id="finish-screen" class="hidden">
            <img class="mascot" src="https://api.dicebear.com/7.x/big-smile/svg?seed=Done">
            <h1 style="text-align:center">派对圆满结束！</h1>
            <button class="btn" onclick="location.reload()">重新开始</button>
        </div>
    </div>

    <!-- 详情弹窗 -->
    <div id="detail-modal" class="modal" onclick="closeModal()">
        <div class="modal-content" onclick="event.stopPropagation()">
            <h3 id="modal-title">选择该项的小伙伴</h3>
            <div id="modal-users" class="user-grid"></div>
            <button class="btn" style="margin-top:20px; padding:10px" onclick="closeModal()">返回</button>
        </div>
    </div>

    <div id="leaderboard-modal" class="modal" onclick="closeLeaderboardModal()">
        <div class="modal-content" onclick="event.stopPropagation()">
            <h3 style="margin-top:0">完整榜单</h3>
            <div id="leaderboard-full-list" style="max-height:60vh; overflow:auto; display:grid; gap:20px"></div>
            <button class="btn" style="margin-top:20px; padding:10px" onclick="closeLeaderboardModal()">返回</button>
        </div>
    </div>

    <script>
        let ws;
        let wsQueue = [];
        let isHost = false;
        let myName = '';
        let myAvatar = '';
        let currentState = {};
        let currentModalOption = -1;
        let leaderboardLoaded = false;
        let leaderboardModalOffset = 0;
        let leaderboardModalHasMore = false;
        let leaderboardModalLoading = false;
        let joinPending = false;

        const AVATAR_PLACEHOLDER = 'data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIxNjAiIGhlaWdodD0iMTYwIiB2aWV3Qm94PSIwIDAgMTYwIDE2MCI+PHJlY3Qgd2lkdGg9IjE2MCIgaGVpZ2h0PSIxNjAiIGZpbGw9IiNFMEUwRTAiLz48Y2lyY2xlIGN4PSI4MCIgY3k9IjYyIiByPSIzMCIgZmlsbD0iI0I1QjVCNSIvPjxwYXRoIGQ9Ik0zMCAxNDBjMTEtMjggMjktNDIgNTAtNDJoMGMyMSAwIDM5IDE0IDUwIDQydjEwSDMwdi0xMHoiIGZpbGw9IiNCNUI1QjUiLz48L3N2Zz4=';

        function renderLeaderboardSkeleton() {
            const body = document.getElementById('leaderboard-body');
            body.innerHTML = `
                <div class="leaderboard-skeleton">
                    <div class="skeleton-line" style="width:70%"></div>
                    <div class="skeleton-line" style="width:90%"></div>
                    <div class="skeleton-line" style="width:80%"></div>
                    <div class="skeleton-line" style="width:95%"></div>
                </div>
            `;
        }

        function renderLeaderboardError() {
            const body = document.getElementById('leaderboard-body');
            body.innerHTML = `<div class="leaderboard-error">排行榜加载失败</div>`;
        }

        async function fetchLeaderboard(limit, offset) {
            const resp = await fetch(`/api/leaderboard?limit=\${limit}&offset=\${offset}`, { cache: 'no-store' });
            if(!resp.ok) throw new Error('network');
            return await resp.json();
        }

        function hideLeaderboard() {
            const panel = document.getElementById('leaderboard-panel');
            const app = document.getElementById('app');
            if(panel) {
                panel.classList.remove('visible');
                panel.classList.add('hidden');
            }
            if(app) app.classList.remove('lb-padding');
        }

        function escapeHtml(s) {
            return String(s ?? '').replace(/[&<>"']/g, (c) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
        }

        function setupLazyAvatars(root) {
            const imgs = root.querySelectorAll('img[data-src]');
            if(!('IntersectionObserver' in window)) {
                imgs.forEach(img => { img.src = img.dataset.src; img.removeAttribute('data-src'); });
                return;
            }
            const io = new IntersectionObserver((entries, observer) => {
                entries.forEach(entry => {
                    if(!entry.isIntersecting) return;
                    const img = entry.target;
                    img.src = img.dataset.src;
                    img.removeAttribute('data-src');
                    observer.unobserve(img);
                });
            }, { rootMargin: '200px' });
            imgs.forEach(img => io.observe(img));
        }

        function imgTag({url, alt, cls, size}) {
            const safeAlt = escapeHtml(alt);
            const safeUrl = url ? escapeHtml(url) : '';
            const safeCls = escapeHtml(cls);
            const wh = size ? `width="\${size}" height="\${size}"` : '';
            if(safeUrl) {
                return `<img class="\${safeCls}" \${wh} loading="lazy" data-src="\${safeUrl}" src="\${AVATAR_PLACEHOLDER}" alt="\${safeAlt}" onerror="this.onerror=null;this.src='\${AVATAR_PLACEHOLDER}';">`;
            }
            return `<img class="\${safeCls}" \${wh} src="\${AVATAR_PLACEHOLDER}" alt="\${safeAlt}">`;
        }

        function renderLeaderboard(items, hasMore) {
            const panel = document.getElementById('leaderboard-panel');
            const body = document.getElementById('leaderboard-body');

            const byRank = new Map();
            items.forEach(u => {
                if(u.rank == null) return;
                if(!byRank.has(u.rank)) byRank.set(u.rank, u);
            });
            const first = byRank.get(1) ?? null;
            const second = byRank.get(2) ?? null;
            const third = byRank.get(3) ?? null;

            const podium = [
                { user: first, medal: '🥇', cls: 'score-gold', h: 100 },
                { user: second, medal: '🥈', cls: 'score-silver', h: 85 },
                { user: third, medal: '🥉', cls: 'score-bronze', h: 70 },
            ];

            const rest = items
                .filter(u => u.rank != null && u.rank >= 4)
                .slice(0, 3);

            body.innerHTML = `
                <div class="podium-grid">
                    \${podium.map(p => {
                        const u = p.user;
                        const name = u ? escapeHtml(u.name) : '—';
                        const score = u ? (u.score ?? 0) : 0;
                        const alt = u ? `\${u.name} 头像` : '默认头像';
                        const avatar = imgTag({ url: u?.avatar_url, alt, cls: 'podium-avatar', size: 80 });
                        return `
                            <div class="podium-card">
                                <svg class="podium-svg" viewBox="0 0 100 120" role="img" aria-label="\${name} 柱形">
                                    <rect x="18" y="\${120 - p.h}" width="64" height="\${p.h}" rx="10" fill="#2D3436" opacity="0.06"></rect>
                                    <rect class="podium-bar" x="18" y="\${120 - p.h}" width="64" height="\${p.h}" rx="10" fill="var(--primary)"></rect>
                                    <text x="50" y="18" text-anchor="middle" class="medal">\${p.medal}</text>
                                </svg>
                                \${avatar}
                                <p class="podium-name">\${name}</p>
                                <p class="podium-score \${p.cls}">\${score}</p>
                            </div>
                        `;
                    }).join('')}
                </div>

                <div class="top10-list">
                    \${rest.map(u => {
                        const alt = `\${u.name} 头像`;
                        return `
                            <div class="top10-row">
                                <div class="rank-num">\${u.rank}</div>
                                \${imgTag({ url: u.avatar_url, alt, cls: 'row-avatar', size: 40 })}
                                <div class="row-name">\${escapeHtml(u.name)}</div>
                                <div class="row-score">\${u.score ?? 0}</div>
                            </div>
                        `;
                    }).join('')}
                </div>
            `;

            panel.classList.remove('hidden');
            setupLazyAvatars(body);
        }

        async function loadLeaderboard() {
            const panel = document.getElementById('leaderboard-panel');
            const app = document.getElementById('app');
            panel.classList.remove('hidden');
            renderLeaderboardSkeleton();
            if(app) app.classList.add('lb-padding');
            setTimeout(() => { panel.classList.add('visible'); }, 0);
            try {
                const data = await fetchLeaderboard(6, 0);
                renderLeaderboard(data.items ?? [], false);
                leaderboardLoaded = true;
            } catch (e) {
                renderLeaderboardError();
            }
        }

        async function openLeaderboardModal() {
            const modal = document.getElementById('leaderboard-modal');
            const list = document.getElementById('leaderboard-full-list');
            modal.style.display = 'flex';
            leaderboardModalOffset = 0;
            leaderboardModalHasMore = true;
            leaderboardModalLoading = false;
            list.innerHTML = '';
            await loadLeaderboardModalMore();
            list.onscroll = async () => {
                if(leaderboardModalLoading || !leaderboardModalHasMore) return;
                if(list.scrollTop + list.clientHeight >= list.scrollHeight - 120) {
                    await loadLeaderboardModalMore();
                }
            };
        }

        function closeLeaderboardModal() {
            const modal = document.getElementById('leaderboard-modal');
            modal.style.display = 'none';
        }

        async function loadLeaderboardModalMore() {
            const list = document.getElementById('leaderboard-full-list');
            leaderboardModalLoading = true;
            try {
                const data = await fetchLeaderboard(21, leaderboardModalOffset);
                const items = data.items ?? [];
                const hasMore = !!data.hasMore;
                leaderboardModalHasMore = hasMore;
                leaderboardModalOffset += items.length;
                const frag = document.createElement('div');
                frag.style.display = 'grid';
                frag.style.gap = '20px';
                frag.innerHTML = items.map(u => `
                    <div class="top10-row">
                        <div class="rank-num">\${u.rank ?? '-'}</div>
                        \${imgTag({ url: u.avatar_url, alt: `\${u.name} 头像`, cls: 'row-avatar', size: 40 })}
                        <div class="row-name">\${escapeHtml(u.name)}</div>
                        <div class="row-score">\${u.score ?? 0}</div>
                    </div>
                `).join('');
                list.appendChild(frag);
                setupLazyAvatars(list);
            } catch (_) {
                leaderboardModalHasMore = false;
            } finally {
                leaderboardModalLoading = false;
            }
        }

        // 初始化粒子背景
        const canvas = document.getElementById('particles');
        const ctx = canvas.getContext('2d');
        let particles = [];
        
        function initParticles() {
            canvas.width = window.innerWidth;
            canvas.height = window.innerHeight;
            particles = [];
            for(let i=0; i<30; i++) {
                particles.push({
                    x: Math.random() * canvas.width,
                    y: Math.random() * canvas.height,
                    size: Math.random() * 5 + 2,
                    color: `hsla(\${Math.random() * 360}, 70%, 70%, 0.5)`,
                    speed: Math.random() * 1 + 0.5
                });
            }
        }
        
        function animateParticles() {
            ctx.clearRect(0, 0, canvas.width, canvas.height);
            particles.forEach(p => {
                p.y -= p.speed;
                if(p.y < -10) p.y = canvas.height + 10;
                ctx.beginPath();
                ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2);
                ctx.fillStyle = p.color;
                ctx.fill();
            });
            requestAnimationFrame(animateParticles);
        }
        initParticles();
        animateParticles();

        function setWsStatus(text) {
            const el = document.getElementById('ws-status');
            if(el) el.innerText = text || '';
        }

        function sendWs(payload) {
            const msg = JSON.stringify(payload);
            if(ws && ws.readyState === WebSocket.OPEN) {
                ws.send(msg);
                return true;
            }
            wsQueue.push(msg);
            setWsStatus('正在连接服务器...');
            if(!ws || ws.readyState === WebSocket.CLOSED) connect();
            return false;
        }

        function connect() {
            const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
            ws = new WebSocket(`\${protocol}//\${window.location.host}/ws`);

            ws.onopen = () => {
                setWsStatus('');
                const pending = wsQueue;
                wsQueue = [];
                pending.forEach(m => ws.send(m));

                const params = new URLSearchParams(window.location.search);
                if(params.get('role') === 'host') {
                    isHost = true;
                    showScreen('host-entry-screen');
                }
            };

            ws.onerror = () => {
                setWsStatus('连接失败，请检查网络');
            };

            ws.onclose = () => {
                setWsStatus('连接已断开，正在重连...');
                setTimeout(() => connect(), 800);
            };

            ws.onmessage = (e) => {
                const payload = JSON.parse(e.data);
                if(payload.type === 'state_update') updateState(payload);
                if(payload.type === 'join_ack') handleJoinAck(payload);
                if(payload.type === 'error') handleWsError(payload);
            };
        }

    function showScreen(id) {
        ['avatar-screen', 'wait-screen', 'quiz-screen', 'transition-screen', 'host-entry-screen', 'results-display', 'finish-screen'].forEach(s => {
            const el = document.getElementById(s);
            if(el) el.classList.add('hidden');
        });
        const target = document.getElementById(id);
        if(target) target.classList.remove('hidden');
    }

    function triggerFile() { document.getElementById('file-input').click(); }
    
    function handleFile(input) {
        const file = input.files[0];
        if(!file) return;
        const reader = new FileReader();
        reader.onload = (e) => {
            const img = new Image();
            img.onload = () => {
                const canvas = document.createElement('canvas');
                const size = Math.min(img.width, img.height);
                canvas.width = 200; canvas.height = 200;
                const ctx = canvas.getContext('2d');
                ctx.drawImage(img, (img.width-size)/2, (img.height-size)/2, size, size, 0, 0, 200, 200);
                myAvatar = canvas.toDataURL('image/jpeg', 0.7);
                document.getElementById('preview-img').src = myAvatar;
            };
            img.src = e.target.result;
        };
        reader.readAsDataURL(file);
    }

    function joinWithAvatar() {
        const nameInput = document.getElementById('name-input');
        const name = nameInput.value.trim();
        if(!name) return alert('起个响亮的名字吧！');
            if(joinPending) return;
        if(!myAvatar) {
            myAvatar = document.getElementById('preview-img').src;
        }
        if(myAvatar && typeof myAvatar === 'string' && myAvatar.startsWith('https://api.dicebear.com/')) {
            myAvatar = `https://api.dicebear.com/7.x/adventurer/svg?seed=\${encodeURIComponent(name)}`;
            document.getElementById('preview-img').src = myAvatar;
        }
        myName = name;
            joinPending = true;
        const ok = sendWs({ type: 'join', name, avatar: myAvatar });
        if(!ok) setWsStatus('正在连接中，请稍等...');
    }

        function handleJoinAck(payload) {
            joinPending = false;
            const el = document.getElementById('inherit-status');
            if(el) {
                const inherited = !!payload.inherited;
                const score = payload.score ?? 0;
                const rank = payload.rank;
                if(inherited) {
                    el.innerText = `已继承历史数据：积分 \${score}，排名 \${rank ?? '-'}。`;
                } else {
                    el.innerText = '已创建新档案：当前积分 0。';
                }
            }
            showScreen('wait-screen');
        }

        function handleWsError(payload) {
            joinPending = false;
            alert(payload.message || '发生错误');
            showScreen('avatar-screen');
        }

    function updateState(state) {
        currentState = state;
            if(state.currentQuestionIndex !== -2) hideLeaderboard();
        
        // 更新等待人数
        if(isHost) {
            const waitCountEl = document.getElementById('host-wait-count');
            if(waitCountEl) waitCountEl.innerText = state.joinedUsers.length;
            
            const qrContainer = document.getElementById('qrcode');
            if (qrContainer && !qrContainer.innerHTML) {
                new QRCode(qrContainer, {
                    text: `http://\${state.hostIp}:\${state.port}`,
                    width: 256,
                    height: 256
                });
            }
        }

        if(state.currentQuestionIndex === -1) {
            if(isHost) showScreen('host-entry-screen');
            else if(myName) {
                showScreen('wait-screen');
                document.getElementById('wait-count').innerText = state.joinedUsers.length;
                document.getElementById('joined-users').innerHTML = state.joinedUsers.map(u => 
                    `<div class="user-item"><img class="user-avatar" src="\${u.avatar || 'https://api.dicebear.com/7.x/adventurer/svg?seed=' + u.name}"><div class="user-name">\${u.name}</div></div>`
                ).join('');
            }
        } else if(state.currentQuestionIndex === -2) {
            showScreen('finish-screen');
            if(!leaderboardLoaded) loadLeaderboard();
        } else if(state.isShowingAnswer) {
            showScreen('results-display');
            renderResultsChart(state);
            
            if(isHost) {
                document.getElementById('host-next-btn').classList.remove('hidden');
                document.getElementById('participant-wait-msg').classList.add('hidden');
            } else {
                document.getElementById('host-next-btn').classList.add('hidden');
                document.getElementById('participant-wait-msg').classList.remove('hidden');
            }
        } else {
            // 答题中
            showScreen('quiz-screen');
            if(isHost) {
                document.getElementById('host-quiz-info').classList.remove('hidden');
                let totalAnswered = 0;
                Object.values(state.answers).forEach(list => totalAnswered += list.length);
                document.getElementById('submitted-count').innerText = totalAnswered;
                document.getElementById('total-participants').innerText = state.joinedUsers.length;
            }
            
            // 检查我是否已答题
            let myAnswer = -1;
            Object.entries(state.answers).forEach(([idx, users]) => {
                if(users.some(u => u.name === myName)) myAnswer = parseInt(idx);
            });

            if(myAnswer !== -1 && !isHost) {
                showScreen('transition-screen');
            } else {
                renderQuiz(state);
            }
        }
    }

    function renderQuiz(state) {
        const q = state.currentQuestion;
        if(!q) return;
        document.getElementById('q-text').innerText = q.question;
        const container = document.getElementById('options-container');
        container.innerHTML = '';
        q.options.forEach((opt, idx) => {
            const b = document.createElement('button');
            b.className = 'btn';
            b.style.background = 'white';
        b.style.color = 'var(--primary)';
        b.style.border = '2px solid var(--primary)';
        b.innerText = `\${String.fromCharCode(65 + idx)}. \${opt}`;
        if(!isHost) {
            b.onclick = () => {
                sendWs({ type: 'submit_answer', optionIndex: idx });
            };
        } else {
            b.disabled = true;
        }
        container.appendChild(b);
    });
}

function renderResultsChart(state) {
    const chart = document.getElementById('chart');
    chart.innerHTML = '';
    const q = state.currentQuestion;
    if(!q) return;

    const counts = q.options.map((_, i) => (state.answers[i.toString()] || []).length);
    const max = Math.max(...counts, 1);

    q.options.forEach((opt, i) => {
        const barGroup = document.createElement('div');
        barGroup.className = 'bar-group';
        barGroup.onclick = () => openModal(i);
        
        const count = counts[i];
        const heightPercent = (count / max) * 100;
        
        // 创建分段颜色 (模拟图片中的样式)
        let segments = '';
        if (count > 0) {
            segments = `
                <div class="bar-segment segment-light" style="height: 33%"></div>
                <div class="bar-segment segment-medium" style="height: 33%"></div>
                <div class="bar-segment segment-dark" style="height: 34%"></div>
            `;
        }

        const isCorrect = i === q.answerIndex;
        
        barGroup.innerHTML = `
            <div class="bar-count">\${count}人</div>
            <div class="bar-stack" style="height: \${Math.max(5, heightPercent)}%">
                \${segments}
            </div>
            <div class="bar-label">\${String.fromCharCode(65 + i)}</div>
            \${isCorrect ? '<div class="correct-indicator">✔ 正确</div>' : ''}
        `;
        chart.appendChild(barGroup);
    });
}

    function hostStartQuiz() { sendWs({ type: 'host_start_quiz' }); }
    function hostShowAnswer() { sendWs({ type: 'host_show_answer' }); }
    function hostNext() { sendWs({ type: 'host_next_question' }); }

    function openModal(idx) {
        currentModalOption = idx;
        const modal = document.getElementById('detail-modal');
        if(modal) {
            modal.style.display = 'flex';
            document.getElementById('modal-title').innerText = `选择 \${String.fromCharCode(65 + idx)} 的小伙伴`;
            filterUsers();
        }
    }

    function filterUsers() {
        const users = currentState.answers[currentModalOption.toString()] || [];
        
        const container = document.getElementById('modal-users');
        if(container) {
            container.innerHTML = users.map(u => `
                <div class="user-item">
                    <img class="user-avatar" src="\${u.avatar || 'https://api.dicebear.com/7.x/adventurer/svg?seed=' + u.name}">
                    <div class="user-name">\${u.name}</div>
                </div>
            `).join('');
        }
    }

    function closeModal() {
        const modal = document.getElementById('detail-modal');
        if(modal) modal.style.display = 'none';
    }

    connect();
    </script>
</body>
</html>
  ''';
}
