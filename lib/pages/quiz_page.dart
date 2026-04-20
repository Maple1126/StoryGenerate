import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_components.dart';
import '../services/qwen_api.dart';
import '../services/quiz_server_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// 新增：WebView 页面，用于在 App 内部打开问答网页
class QuizWebViewPage extends StatelessWidget {
  final String url;
  const QuizWebViewPage({Key? key, required this.url}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('答题派对'),
        backgroundColor: AppColors.accent,
        centerTitle: true,
      ),
      body: WebViewWidget(
        controller: WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..loadRequest(Uri.parse(url)),
      ),
    );
  }
}

class QuizPage extends StatefulWidget {
  const QuizPage({Key? key}) : super(key: key);

  @override
  _QuizPageState createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String? _selectedStory;
  bool _isGenerating = false;

  List<Map<String, String>> _stories = [];
  bool _isLoadingStories = true;

  List<Map<String, dynamic>>? _questions;

  Future<void> _openStoryPicker() async {
    if (_isGenerating) return;
    await _loadStories();
    if (!mounted) return;
    if (_isLoadingStories) return;
    if (_stories.isEmpty) return;

    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final controller = TextEditingController();
        return SafeArea(
          child: Container(
            height: MediaQuery.of(context).size.height * 0.82,
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: StatefulBuilder(
              builder: (context, setModalState) {
                final query = controller.text.trim();
                final filtered = query.isEmpty
                    ? _stories
                    : _stories.where((s) {
                        final title = (s['title'] ?? '').trim();
                        final content = (s['content'] ?? '').trim();
                        return title.contains(query) || content.contains(query);
                      }).toList();

                return Column(
                  children: [
                    SizedBox(height: 10),
                    Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.textSecondary.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 10),
                      child: TextField(
                        controller: controller,
                        onChanged: (_) => setModalState(() {}),
                        decoration: InputDecoration(
                          hintText: '搜索故事...',
                          prefixIcon: Icon(
                            Icons.search,
                            color: AppColors.accent,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: AppColors.background,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: EdgeInsets.fromLTRB(8, 0, 8, 12),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          final title = item['title'] ?? '';
                          final content = item['content'] ?? '';
                          final selected = _selectedStory == content;
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => Navigator.of(context).pop(content),
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? AppColors.accent.withOpacity(0.12)
                                      : AppColors.background,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                          SizedBox(height: 4),
                                          Text(
                                            content,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    Icon(
                                      selected
                                          ? Icons.check_circle
                                          : Icons.chevron_right,
                                      color: selected
                                          ? AppColors.accent
                                          : AppColors.textSecondary,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    if (!mounted) return;
    if (selected == null) return;
    setState(() {
      _selectedStory = selected;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadStories();
  }

  Future<void> _loadStories() async {
    setState(() {
      _isLoadingStories = true;
    });

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        if (!mounted) return;
        setState(() {
          _isLoadingStories = false;
        });
        return;
      }

      final response = await Supabase.instance.client
          .from('stories')
          .select('content')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      setState(() {
        _stories = response.map<Map<String, String>>((item) {
          String fullContent = item['content'] as String;
          String title = fullContent.length > 20
              ? fullContent.substring(0, 20) + '...'
              : fullContent;
          return {'title': title, 'content': fullContent};
        }).toList();
        _isLoadingStories = false;
      });
    } catch (e) {
      print('加载故事失败：$e');
      setState(() {
        _isLoadingStories = false;
      });
    }
  }

  void _generateQuiz() async {
    if (_selectedStory == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('请先选择一个故事')));
      return;
    }

    setState(() {
      _isGenerating = true;
      _questions = null;
    });

    try {
      final questions = await QwenApi.generateQuiz(_selectedStory!);

      setState(() {
        _questions = questions;
        _isGenerating = false;
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('生成问题失败: $e')));
      setState(() {
        _isGenerating = false;
      });
    }
  }

  Widget _buildQuizView() {
    if (_questions == null || _questions!.isEmpty) return SizedBox();

    return Column(
      children: [
        ..._questions!.asMap().entries.map((entry) {
          int qIndex = entry.key;
          var question = entry.value;
          final options = List<String>.from(question['options']);
          final correctIndex = question['answerIndex'] as int;

          return Padding(
                padding: const EdgeInsets.only(bottom: 20.0),
                child: SoftCard(
                  padding: 24,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '问题 ${qIndex + 1} / ${_questions!.length}',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        question['question'],
                        style: Theme.of(
                          context,
                        ).textTheme.titleLarge?.copyWith(fontSize: 18),
                      ),
                      SizedBox(height: 24),
                      ...List.generate(options.length, (index) {
                        bool isCorrectOption = index == correctIndex;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12.0),
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              color: isCorrectOption
                                  ? Colors.green.withOpacity(0.1)
                                  : AppColors.background,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isCorrectOption
                                    ? Colors.green
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  String.fromCharCode(65 + index) +
                                      '.', // A, B, C, D
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isCorrectOption
                                        ? Colors.green
                                        : AppColors.textPrimary,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    options[index],
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                                if (isCorrectOption)
                                  Icon(Icons.check_circle, color: Colors.green),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              )
              .animate()
              .fadeIn(delay: (qIndex * 100).ms)
              .slideY(begin: 0.1, end: 0);
        }).toList(),
        SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: GradientButton(
                text: _isGenerating ? '正在重新生成...' : '重新生成问题',
                onPressed: _generateQuiz,
                isLoading: _isGenerating,
                icon: Icons.refresh,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: GradientButton(
                text: '跳转答题网页',
                onPressed: _openQuizWebpage,
                icon: Icons.open_in_new,
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        GradientButton(
          text: '重新选择故事',
          onPressed: () {
            setState(() {
              _questions = null;
              _selectedStory = null;
            });
          },
          icon: Icons.history,
        ).animate().fadeIn(delay: (_questions!.length * 100).ms),
      ],
    );
  }

  @override
  void dispose() {
    QuizServerService().stopServer();
    super.dispose();
  }

  // 修改：使用 WebView 在 App 内部打开，不跳转浏览器
  void _openQuizWebpage() async {
    if (_questions == null || _questions!.isEmpty) return;

    try {
      await QuizServerService().startServer(_questions!);
      final ip = await QuizServerService().localIp ?? '127.0.0.1';
      final url = 'http://$ip:8080?role=host';

      // 在 App 内部打开 WebView
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => QuizWebViewPage(url: url)),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('启动失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          '故事问答',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_questions == null) ...[
                SoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                            '选择故事生成问答',
                            style: Theme.of(context).textTheme.titleMedium,
                          )
                          .animate()
                          .fadeIn(duration: 800.ms, delay: 200.ms)
                          .slideX(begin: -0.2, end: 0),

                      SizedBox(height: 16),

                      Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: _openStoryPicker,
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _isLoadingStories
                                              ? '加载中...'
                                              : (_selectedStory == null
                                                    ? '请选择一个故事'
                                                    : (_stories.firstWhere(
                                                            (s) =>
                                                                s['content'] ==
                                                                _selectedStory,
                                                            orElse: () => {
                                                              'title': '已选择故事',
                                                            },
                                                          )['title'] ??
                                                          '已选择故事')),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 14),
                                        ),
                                      ),
                                      Icon(
                                        Icons.arrow_drop_down,
                                        color: AppColors.textSecondary,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          )
                          .animate()
                          .fadeIn(duration: 800.ms, delay: 400.ms)
                          .scale(begin: Offset(0.9, 0.9), end: Offset(1, 1)),

                      if (_selectedStory != null) ...[
                        SizedBox(height: 20),
                        GradientButton(
                              text: _isGenerating ? '生成中...' : '生成问答',
                              onPressed: _generateQuiz,
                              isLoading: _isGenerating,
                              icon: _isGenerating
                                  ? null
                                  : Icons.question_answer,
                            )
                            .animate()
                            .fadeIn(duration: 800.ms, delay: 600.ms)
                            .slideY(begin: 0.2, end: 0),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: 24),
              ],

              if (_questions != null) _buildQuizView(),

              SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
