import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/secrets.dart';

class QwenApi {
  static const String _baseUrl =
      'https://dashscope.aliyuncs.com/compatible-mode/v1';
  static const String _model = 'qwen-mt-flash';
  static final List<RegExp> _unsafePatterns = [
    RegExp(
      r'(色情|性描写|性暗示|裸体|裸露|强奸|猥亵|成人影片|成人视频|A片|黄片|床戏|做爱|性交|性器官|阴茎|阴道|乳房|自慰)',
      caseSensitive: false,
    ),
    RegExp(
      r'(血腥|流血|尸体|肢解|杀人|谋杀|砍杀|刺杀|虐杀|爆炸|炸弹|枪战|手枪|步枪|匕首|砍刀|恐怖袭击)',
      caseSensitive: false,
    ),
    RegExp(r'(吸毒|毒品|海洛因|冰毒|大麻|摇头丸)', caseSensitive: false),
    RegExp(r'(赌博|赌钱|老虎机)', caseSensitive: false),
    RegExp(r'(操你|傻逼|妈的|他妈|你妈|滚蛋|屌|逼)', caseSensitive: false),
    RegExp(r'(自杀|割腕)', caseSensitive: false),
  ];

  static String _cleanPossibleCodeFence(String content) {
    var text = content.trim();
    if (text.startsWith('```json')) {
      text = text.substring(7);
    } else if (text.startsWith('```')) {
      text = text.substring(3);
    }
    if (text.endsWith('```')) {
      text = text.substring(0, text.length - 3);
    }
    return text.trim();
  }

  static String get _apiKey {
    return Secrets.dashscopeApiKey;
  }

  static Future<String> generateStory({
    required String topic,
    required String style,
    int minChars = 700,
    int maxChars = 1200,
    bool kidSafe = true,
    int maxRetries = 1,
  }) async {
    if (_apiKey.isEmpty) {
      throw Exception('未配置API密钥，请在secrets.dart中设置');
    }

    final uri = Uri.parse('$_baseUrl/chat/completions');
    final headers = {
      'Authorization': 'Bearer $_apiKey',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    String buildPrompt({required bool strictKidSafe}) {
      final safeBlock = strictKidSafe
          ? '''
安全要求（必须严格遵守，面向小学生阅读）：
1. 不得包含低俗、脏话、色情或性暗示内容。
2. 不得包含暴力血腥、恐怖惊悚、伤害他人或自残相关内容。
3. 不得包含毒品、赌博、酗酒、抽烟等不良行为的描写或引导。
4. 内容积极健康，传递友善、勇气、合作、诚信等正向价值。
'''
          : '';

      return '''
请用$style风格创作一篇中文故事。
${safeBlock.isEmpty ? '' : safeBlock}
要求：
1. 字数在$minChars到$maxChars字之间。
2. 情节完整，有开端、发展、高潮、结尾。
3. 只输出故事正文，不要额外解释。

主题/描述：
$topic
''';
    }

    Future<String> requestOnce({required bool strictKidSafe}) async {
      final prompt = buildPrompt(strictKidSafe: strictKidSafe);
      final body = jsonEncode({
        'model': _model,
        'messages': [
          {
            'role': 'user',
            'content': (kidSafe
                    ? '你是一位面向小学生创作的中文故事作者。'
                    : '你是一位擅长创作中文故事的助手。') +
                '\n\n' +
                prompt.trim(),
          },
        ],
        'stream': false,
        'max_tokens': 2200,
      });

      final resp = await http.post(uri, headers: headers, body: body);
      if (resp.statusCode != 200) {
        throw Exception('API错误(${resp.statusCode}): ${resp.body}');
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final choices = data['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) {
        throw Exception('API返回内容为空');
      }

      final message = choices.first['message'] as Map<String, dynamic>?;
      final content = message?['content'] as String?;
      if (content == null || content.isEmpty) {
        throw Exception('API未返回故事文本');
      }

      return content.trim();
    }

    bool isKidSafeText(String text) {
      return !_unsafePatterns.any((p) => p.hasMatch(text));
    }

    var attempt = 0;
    final retries = maxRetries < 0 ? 0 : maxRetries;
    while (true) {
      final strict = kidSafe;
      final story = await requestOnce(strictKidSafe: strict);
      if (!kidSafe || isKidSafeText(story)) {
        return story;
      }
      if (attempt >= retries) {
        throw Exception('生成内容未通过小学生安全校验，请修改主题后重试');
      }
      attempt++;
    }
  }

  static Future<List<Map<String, dynamic>>> generateQuiz(String story) async {
    if (_apiKey.isEmpty) {
      throw Exception('未配置API密钥，请在secrets.dart中设置');
    }

    final uri = Uri.parse('$_baseUrl/chat/completions');
    final headers = {
      'Authorization': 'Bearer $_apiKey',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    final prompt =
        '''
请根据以下故事内容，生成5个单项选择题。
每个问题必须包含4个选项（A, B, C, D），并指出正确答案。
请严格按照以下JSON格式返回，不要包含任何额外的文本或Markdown标记，只要纯JSON数组：

[
  {
    "question": "问题1的内容",
    "options": ["选项A的内容", "选项B的内容", "选项C的内容", "选项D的内容"],
    "answerIndex": 0  // 正确选项的索引，0代表A，1代表B，2代表C，3代表D
  },
  ...
]

故事内容：
$story
''';

    final body = jsonEncode({
      'model': _model,
      'messages': [
        {
          'role': 'user',
          'content':
              'You are a helpful assistant that generates JSON outputs only. \n\n' +
              prompt,
        },
      ],
      'stream': false,
    });

    try {
      final resp = await http.post(uri, headers: headers, body: body);
      if (resp.statusCode != 200) {
        throw Exception('API错误(${resp.statusCode}): ${resp.body}');
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final choices = data['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) {
        throw Exception('API返回内容为空');
      }

      final message = choices.first['message'] as Map<String, dynamic>?;
      String? content = message?['content'] as String?;

      if (content == null || content.isEmpty) {
        throw Exception('API未返回问答文本');
      }

      // 清理可能包含的 markdown 格式
      content = _cleanPossibleCodeFence(content);

      final List<dynamic> jsonResult = jsonDecode(content.trim());
      return jsonResult.map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      print('生成问答失败: $e');
      rethrow;
    }
  }

  static Future<List<String>> generateStoryScenesForImages({
    required String story,
    int count = 4,
    bool kidSafe = true,
  }) async {
    if (_apiKey.isEmpty) {
      throw Exception('未配置API密钥，请在secrets.dart中设置');
    }

    final uri = Uri.parse('$_baseUrl/chat/completions');
    final headers = {
      'Authorization': 'Bearer $_apiKey',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    final safeBlock = kidSafe
        ? '''
安全要求（必须严格遵守，面向小学生）：
1. 不得包含低俗、脏话、色情或性暗示内容。
2. 不得包含暴力血腥、恐怖惊悚、伤害他人或自残相关内容。
3. 不得包含毒品、赌博、酗酒、抽烟等不良行为的描写或引导。
4. 画面氛围积极健康、温暖明亮。
'''
        : '';

    final prompt = '''
请把下面的故事拆分为$count个连续的“分镜画面描述”，用于生成插图。
${safeBlock.isEmpty ? '' : safeBlock}
要求：
1. 只输出纯JSON数组（不要Markdown），长度必须为$count。
2. 每一项是字符串，用一句话描述画面：人物（外观/年龄大致即可）、地点、动作、表情情绪、关键道具。
3. 画面描述要具体但不要出现血腥、恐怖、性内容。

故事：
$story
''';

    final body = jsonEncode({
      'model': _model,
      'messages': [
        {
          'role': 'user',
          'content': '你是一个只输出JSON数组的助手。\n\n' + prompt,
        },
      ],
      'stream': false,
    });

    final resp = await http.post(uri, headers: headers, body: body);
    if (resp.statusCode != 200) {
      throw Exception('API错误(${resp.statusCode}): ${resp.body}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final choices = data['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw Exception('API返回内容为空');
    }

    final message = choices.first['message'] as Map<String, dynamic>?;
    final raw = message?['content'] as String?;
    if (raw == null || raw.isEmpty) {
      throw Exception('API未返回分镜文本');
    }

    final cleaned = _cleanPossibleCodeFence(raw);
    final decoded = jsonDecode(cleaned);
    if (decoded is! List) {
      throw Exception('分镜返回格式错误');
    }

    final scenes = decoded.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    if (scenes.length != count) {
      throw Exception('分镜数量不正确');
    }

    return scenes;
  }
}
