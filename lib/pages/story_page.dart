import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_components.dart';
import '../services/qwen_api.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StoryPage extends StatefulWidget {
  const StoryPage({Key? key}) : super(key: key);

  @override
  _StoryPageState createState() => _StoryPageState();
}

class _StoryPageState extends State<StoryPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final TextEditingController _storyController = TextEditingController();
  bool _isGenerating = false;
  String _generatedStory = '';
  bool _isFavorited = false;
  static const List<String> _storyStyles = ['童趣', '卡通', '科幻', '奇幻', '悬疑'];
  String _selectedStyle = _storyStyles.first;

  @override
  void dispose() {
    _storyController.dispose();
    super.dispose();
  }

  void _generateStory() async {
    if (_storyController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('请输入故事主题或描述！')));
      return;
    }

    setState(() {
      _isGenerating = true;
      _generatedStory = '';
      _isFavorited = false;
    });

    try {
      final topic = _storyController.text.trim();
      final response = await QwenApi.generateStory(
        topic: topic,
        style: _selectedStyle,
      );

      setState(() {
        _generatedStory = response;
      });

      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        await Supabase.instance.client.from('stories').insert({
          'user_id': userId,
          'content': response,
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('生成失败：$e')));
    } finally {
      setState(() {
        _isGenerating = false;
      });
    }
  }

  Future<void> _toggleFavorite() async {
    if (_generatedStory.isEmpty) return;

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('请先登录')));
      return;
    }

    // 获取当前故事对应的图片和视频 URL
    String? videoUrl;
    List<String>? imageUrls;

    final storyResponse = await Supabase.instance.client
        .from('stories')
        .select('image_urls, video_url')
        .eq('content', _generatedStory)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (storyResponse != null) {
      imageUrls = storyResponse['image_urls'] != null
          ? List<String>.from(storyResponse['image_urls'])
          : null;
      videoUrl = storyResponse['video_url'];
    }

    setState(() {
      _isFavorited = !_isFavorited;
    });

    try {
      if (_isFavorited) {
        await Supabase.instance.client.from('favorites').insert({
          'user_id': userId,
          'content': _generatedStory,
          'image_urls': imageUrls ?? [],
          'video_url': videoUrl,
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已收藏！')));
      } else {
        await Supabase.instance.client.from('favorites').delete().match({
          'user_id': userId,
          'content': _generatedStory,
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已取消收藏')));
      }
    } catch (e) {
      setState(() {
        _isFavorited = !_isFavorited;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('操作失败，请重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          '故事生成',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SoftCard(
              padding: 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '请输入故事主题或描述',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  )
                      .animate()
                      .fadeIn(duration: 600.ms)
                      .slideY(begin: 0.2, end: 0),

                  SizedBox(height: 12),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _storyController,
                          minLines: 3,
                          maxLines: 5,
                          decoration: InputDecoration(
                            hintText: '例如：一个勇敢的小女孩在森林里冒险...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: AppColors.cardBackground,
                            contentPadding: EdgeInsets.all(16),
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      SizedBox(
                        width: 120,
                        child: DropdownButtonFormField<String>(
                          value: _selectedStyle,
                          items: _storyStyles
                              .map(
                                (style) => DropdownMenuItem(
                              value: style,
                              child: Text(style),
                            ),
                          )
                              .toList(),
                          onChanged: _isGenerating
                              ? null
                              : (value) {
                            if (value == null) return;
                            setState(() {
                              _selectedStyle = value;
                            });
                          },
                          decoration: InputDecoration(
                            labelText: '风格',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: AppColors.cardBackground,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                      .animate()
                      .fadeIn(duration: 600.ms, delay: 100.ms)
                      .slideY(begin: 0.2, end: 0),

                  SizedBox(height: 24),

                  GradientButton(
                    text: _isGenerating ? '生成中...' : '生成故事',
                    onPressed: _isGenerating
                        ? () {}
                        : _generateStory,
                    isLoading: _isGenerating,
                  )
                      .animate()
                      .fadeIn(duration: 600.ms, delay: 200.ms)
                      .slideY(begin: 0.2, end: 0),
                ],
              ),
            ),

            if (_generatedStory.isNotEmpty) ...[
              SizedBox(height: 32),

              SoftCard(
                padding: 24,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '生成的故事',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    )
                        .animate()
                        .fadeIn(duration: 600.ms)
                        .slideY(begin: 0.2, end: 0),

                    SizedBox(height: 16),

                    Text(
                      _generatedStory,
                      style: TextStyle(
                        fontSize: 16,
                        color: AppColors.textPrimary,
                        height: 1.5,
                      ),
                    )
                        .animate()
                        .fadeIn(duration: 600.ms, delay: 100.ms)
                        .slideY(begin: 0.2, end: 0),

                    SizedBox(height: 20),

                    Row(
                      children: [
                        Expanded(
                          child:
                          OutlinedButton.icon(
                            onPressed: _toggleFavorite,
                            icon: Icon(
                              _isFavorited
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              size: 18,
                              color: _isFavorited ? Colors.red : null,
                            ),
                            label: Text(_isFavorited ? '已收藏' : '收藏'),
                            style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.symmetric(
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          )
                              .animate()
                              .fadeIn(duration: 600.ms, delay: 200.ms)
                              .slideY(begin: 0.2, end: 0),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              SizedBox(height: 40),
            ],
          ],
        ),
      ),
    );
  }
}