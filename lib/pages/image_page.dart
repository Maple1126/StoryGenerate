import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_components.dart';
import '../services/dashscope_api.dart';
import '../services/qwen_api.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class ImagePage extends StatefulWidget {
  const ImagePage({Key? key}) : super(key: key);

  @override
  _ImagePageState createState() => _ImagePageState();
}

class _ImagePageState extends State<ImagePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  static const int _minImageCount = 2;
  static const int _maxImageCount = 5;

  String? _selectedStory;
  bool _isGenerating = false;
  List<String?> _generatedImages = [];
  int _targetImageCount = 4;

  List<Map<String, String>> _stories = [];
  bool _isLoadingStories = true;
  static const List<String> _imageStyles = [
    '卡通绘本风格',
    '迪士尼动画风格',
    '动物派对风格',
    '宫崎骏/吉卜力风格',
    '手绘水彩风格',
  ];
  String _selectedStyle = _imageStyles.first;

  Future<void> _runWithConcurrency(
      List<Future<void> Function()> tasks, {
        int concurrency = 2,
      }) async {
    final limit = concurrency < 1 ? 1 : concurrency;
    var nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        final i = nextIndex++;
        if (i >= tasks.length) return;
        await tasks[i]();
      }
    }

    await Future.wait(List.generate(limit, (_) => worker()));
  }

  @override
  void initState() {
    super.initState();
    _generatedImages = List.filled(_targetImageCount, null);
    _loadStories();
  }

  Future<void> _loadStories() async {
    setState(() {
      _isLoadingStories = true;
    });

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
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

  void _generateImages() async {
    if (_selectedStory == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('请先选择一个故事')));
      return;
    }

    final story = _selectedStory!;
    final style = _selectedStyle;

    setState(() {
      _isGenerating = true;
      _generatedImages = List.filled(_targetImageCount, null);
    });

    final tasks = <Future<void> Function()>[];
    try {
      final scenes = await QwenApi.generateStoryScenesForImages(
        story: story,
        count: _targetImageCount,
        kidSafe: true,
      );

      for (var i = 0; i < scenes.length; i++) {
        final scene = scenes[i];
        final prompt =
        '''
请生成一张适合小学生观看的中文故事插画。
风格：$style
画面描述：$scene
要求：无暴力血腥、无恐怖惊悚、无色情低俗、无毒品赌博；画面温暖明亮；主体清晰；不要出现文字水印。
''';
        tasks.add(() async {
          final images = await DashscopeApi.generateImages(
            prompt.trim(),
            n: 1,
            promptExtend: false,
          );
          if (!mounted) return;
          if (images.isEmpty) return;

          final imageUrl = images.first;

          setState(() {
            _generatedImages[i] = imageUrl;
          });

          _saveImageToSupabase(imageUrl);
        });
      }
      await _runWithConcurrency(tasks, concurrency: 2);

      // 保存图片 URL 到 stories 表
      final validImageUrls = _generatedImages.whereType<String>().toList();
      if (validImageUrls.isNotEmpty) {
        final storyResponse = await Supabase.instance.client
            .from('stories')
            .select('id')
            .eq('content', story)
            .order('created_at', ascending: false)
            .limit(1)
            .single();

        await Supabase.instance.client
            .from('stories')
            .update({'image_urls': validImageUrls})
            .eq('id', storyResponse['id']);
        print('✅ 已保存图片 URL 到 stories 表');
      }

    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('生成失败: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  Future<void> _saveImageToSupabase(String imageUrl) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null && imageUrl.isNotEmpty) {
        await Supabase.instance.client.from('generated_media').insert({
          'user_id': userId,
          'media_type': 'image',
          'public_url': imageUrl,
          'file_path': 'generated/${DateTime.now().millisecondsSinceEpoch}.png',
          'created_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      print('保存图片到 Supabase 失败: $e');
    }
  }

  Future<void> _downloadImage(String imageUrl) async {
    try {
      var status = await Permission.storage.request();
      if (!status.isGranted) {
        status = await Permission.photos.request();
      }

      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('需要存储权限才能保存图片')),
        );
        return;
      }

      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        final result = await ImageGallerySaverPlus.saveImage(
          bytes,
          name: 'story_image_${DateTime.now().millisecondsSinceEpoch}.png',
        );

        if (result['isSuccess'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('图片已保存到相册')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('保存失败，请重试')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载图片失败')),
        );
      }
    } catch (e) {
      print('下载图片错误: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e')),
      );
    }
  }

  Future<void> _saveAllImages() async {
    if (_generatedImages.isEmpty) return;

    final validImages = _generatedImages.where((url) => url != null).toList();
    if (validImages.isEmpty) return;

    int successCount = 0;
    for (final url in validImages) {
      try {
        final response = await http.get(Uri.parse(url!));
        if (response.statusCode == 200) {
          final result = await ImageGallerySaverPlus.saveImage(
            response.bodyBytes,
            name: 'story_image_${DateTime.now().millisecondsSinceEpoch}.png',
          );
          if (result['isSuccess'] == true) successCount++;
        }
      } catch (e) {
        print('批量保存失败: $url -> $e');
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存完成：$successCount/${validImages.length} 张')),
      );
    }
  }

  Future<void> _openStoryPicker() async {
    await _loadStories();
    if (_isLoadingStories || _isGenerating) return;
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

  Widget _buildPlaceholderTile(int index) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: AppColors.cardBackground,
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.background,
                      AppColors.cardBackground,
                      AppColors.background,
                    ],
                  ),
                ),
              ).animate().shimmer(duration: 1200.ms),
            ),
            Positioned(
              left: 10,
              top: 10,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '${index + 1}/$_targetImageCount',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppColors.accent,
                  ),
                  strokeWidth: 3,
                ),
              ),
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 250.ms)
        .scale(begin: Offset(0.98, 0.98), end: Offset(1, 1));
  }

  Widget _buildImageTile(String imageUrl, int index) {
    return GestureDetector(
      onTap: () {
        showDialog(
          context: context,
          builder: (context) => Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                image: DecorationImage(
                  image: NetworkImage(imageUrl),
                  fit: BoxFit.cover,
                ),
              ),
              height: 300,
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadow,
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.accent,
                        ),
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                left: 10,
                top: 10,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${index + 1}/$_targetImageCount',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.cardBackground.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: IconButton(
                    icon: Icon(Icons.download, size: 20),
                    onPressed: () => _downloadImage(imageUrl),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 450.ms, delay: (index * 80).ms)
        .scale(begin: Offset(0.96, 0.96), end: Offset(1, 1));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final generatedCount = _generatedImages.where((e) => e != null).length;
    final hasImages = generatedCount > 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '图片生成',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ).animate().fadeIn(duration: 600.ms).slideY(begin: -0.2, end: 0),

              SizedBox(height: 24),

              SoftCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('选择故事', style: Theme.of(context).textTheme.titleMedium)
                        .animate()
                        .fadeIn(duration: 800.ms, delay: 200.ms)
                        .slideX(begin: -0.2, end: 0),

                    SizedBox(height: 16),

                    Column(
                      children: [
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
                                            ? '请选择故事'
                                            : (_stories.firstWhere(
                                              (s) =>
                                          s['content'] ==
                                              _selectedStory,
                                          orElse: () => {
                                            'title':
                                            '已选择故事',
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
                        ),
                        SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: _selectedStyle,
                          isExpanded: true,
                          items: _imageStyles
                              .map(
                                (style) => DropdownMenuItem(
                              value: style,
                              child: Text(
                                style,
                                style: TextStyle(fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                              ),
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
                              borderRadius: BorderRadius.circular(12),
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
                      ],
                    )
                        .animate()
                        .fadeIn(duration: 800.ms, delay: 400.ms)
                        .scale(begin: Offset(0.9, 0.9), end: Offset(1, 1)),

                    if (_selectedStory != null) ...[
                      SizedBox(height: 16),
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _selectedStory!,
                          style: Theme.of(context).textTheme.bodyMedium,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      )
                          .animate()
                          .fadeIn(duration: 600.ms)
                          .slideY(begin: 0.2, end: 0),
                    ],

                    SizedBox(height: 20),

                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '生成数量 ($_minImageCount-$_maxImageCount张)',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.accent.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  '${_targetImageCount}张',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.accent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Slider(
                            value: _targetImageCount.toDouble(),
                            min: _minImageCount.toDouble(),
                            max: _maxImageCount.toDouble(),
                            divisions: _maxImageCount - _minImageCount,
                            label: '${_targetImageCount}张',
                            onChanged: _isGenerating ? null : (value) {
                              setState(() {
                                _targetImageCount = value.round();
                                _generatedImages = List.filled(_targetImageCount, null);
                              });
                            },
                            activeColor: AppColors.accent,
                            inactiveColor: AppColors.textSecondary.withOpacity(0.3),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: List.generate(_maxImageCount - _minImageCount + 1, (index) {
                              final count = _minImageCount + index;
                              return Text(
                                '$count',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _targetImageCount == count
                                      ? AppColors.accent
                                      : AppColors.textSecondary,
                                  fontWeight: _targetImageCount == count
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ).animate()
                        .fadeIn(duration: 800.ms, delay: 500.ms)
                        .slideY(begin: 0.2, end: 0),

                    SizedBox(height: 20),

                    GradientButton(
                      text: _isGenerating ? '生成中...' : '生成图片',
                      onPressed: _generateImages,
                      isLoading: _isGenerating,
                      icon: _isGenerating ? null : Icons.image,
                    )
                        .animate()
                        .fadeIn(duration: 800.ms, delay: 600.ms)
                        .slideY(begin: 0.2, end: 0),
                  ],
                ),
              ),

              if (_isGenerating || hasImages) ...[
                SizedBox(height: 24),
                SoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.image,
                            color: AppColors.accent,
                            size: 24,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _isGenerating
                                  ? '图片生成中 $generatedCount/$_targetImageCount'
                                  : '生成的图片',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          if (!_isGenerating && hasImages)
                            TextButton.icon(
                              onPressed: _saveAllImages,
                              icon: Icon(Icons.save_alt, size: 18),
                              label: Text('保存全部'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.accent,
                              ),
                            ),
                        ],
                      )
                          .animate()
                          .fadeIn(duration: 600.ms)
                          .slideX(begin: -0.2, end: 0),

                      if (_isGenerating) ...[
                        SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: (generatedCount / _targetImageCount).clamp(
                              0,
                              1,
                            ),
                            minHeight: 8,
                            backgroundColor: AppColors.background.withOpacity(
                              0.8,
                            ),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.accent,
                            ),
                          ),
                        ).animate().fadeIn(duration: 300.ms),
                      ],

                      SizedBox(height: 16),

                      GridView.builder(
                        shrinkWrap: true,
                        physics: NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 1,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: _targetImageCount,
                        itemBuilder: (context, index) {
                          final url = _generatedImages[index];
                          if (url != null) {
                            return _buildImageTile(url, index);
                          }
                          return _buildPlaceholderTile(index);
                        },
                      ),
                    ],
                  ),
                ),
              ],

              SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}