import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:video_player/video_player.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_components.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/volcengine_api.dart';
import 'package:http/http.dart' as http;
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:device_info_plus/device_info_plus.dart';

class VideoPage extends StatefulWidget {
  const VideoPage({super.key});

  @override
  _VideoPageState createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  String? _selectedStory;
  bool _isGenerating = false;
  String? _generatedVideo;
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  double _videoDuration = 10;

  List<Map<String, String>> _stories = [];
  bool _isLoadingStories = true;

  @override
  void initState() {
    super.initState();
    _loadStories();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _loadStories() async {
    if (!mounted) return;

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

      if (!mounted) return;

      setState(() {
        _stories = response.map<Map<String, String>>((item) {
          String fullContent = item['content'] as String;
          String title = fullContent.length > 20
              ? '${fullContent.substring(0, 20)}...'
              : fullContent;
          return {'title': title, 'content': fullContent};
        }).toList();
        _isLoadingStories = false;
      });
    } catch (e) {
      debugPrint('加载故事失败：$e');
      if (mounted) {
        setState(() {
          _isLoadingStories = false;
        });
      }
    }
  }

  Future<void> _openStoryPicker() async {
    await _loadStories();
    if (!mounted) return;
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

  void _generateVideo() async {
    if (_selectedStory == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先选择一个故事')));
      return;
    }

    if (!mounted) return;

    setState(() {
      _isGenerating = true;
      _generatedVideo = null;
      _videoController?.dispose();
      _videoController = null;
      _isVideoInitialized = false;
    });

    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('视频生成中，请耐心等待约${(_videoDuration ~/ 5) + 1}分钟...'),
            duration: const Duration(seconds: 3),
          ),
        );
      }

      String durationText = '${_videoDuration.toInt()}秒';

      String prompt = _selectedStory!.length > 300
          ? '${_selectedStory!.substring(0, 300)}，生成一個生動的短視頻，卡通風格，$durationText'
          : '$_selectedStory!，生成一個生動的短視頻，卡通風格，$durationText';

      debugPrint('开始生成视频，prompt长度: ${prompt.length}，时长: ${_videoDuration}秒');

      final videoUrl = await VolcengineApi.generateVideo(
        prompt,
        duration: _videoDuration.toInt(),
      );

      debugPrint('视频生成成功，URL: $videoUrl');

      if (!mounted) return;

      setState(() {
        _generatedVideo = videoUrl;
      });

      await _initializeVideoPlayer(videoUrl);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('视频生成成功！'),
            backgroundColor: Colors.green,
          ),
        );
      }

      await _saveVideoToSupabase(videoUrl);

      // 保存视频 URL 到 stories 表
      final storyResponse = await Supabase.instance.client
          .from('stories')
          .select('id')
          .eq('content', _selectedStory!)
          .order('created_at', ascending: false)
          .limit(1)
          .single();

      await Supabase.instance.client
          .from('stories')
          .update({'video_url': videoUrl})
          .eq('id', storyResponse['id']);
      print('✅ 已保存视频 URL 到 stories 表');
    } catch (e) {
      debugPrint('生成錯誤: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('生成失敗: ${e.toString()}'),
            duration: const Duration(seconds: 5),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  Future<void> _initializeVideoPlayer(String videoUrl) async {
    try {
      if (_videoController != null) {
        await _videoController!.dispose();
      }

      _videoController = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      await _videoController!.initialize();

      if (mounted) {
        setState(() {
          _isVideoInitialized = true;
        });
      }

      debugPrint('视频播放器初始化成功');
    } catch (e) {
      debugPrint('视频播放器初始化失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('视频加载失败: $e')));
      }
    }
  }

  void _playVideo() {
    if (_videoController != null && _isVideoInitialized) {
      if (_videoController!.value.isPlaying) {
        _videoController!.pause();
      } else {
        _videoController!.play();
      }
      setState(() {});
    } else if (_generatedVideo != null) {
      _initializeVideoPlayer(_generatedVideo!);
    }
  }

  Future<void> _saveVideoToSupabase(String videoUrl) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        await Supabase.instance.client.from('generated_media').insert({
          'user_id': userId,
          'media_type': 'video',
          'public_url': videoUrl,
          'file_path':
              'generated_video_${DateTime.now().millisecondsSinceEpoch}.mp4',
          'created_at': DateTime.now().toIso8601String(),
        });
        debugPrint('视频URL已保存到数据库');
      }
    } catch (e) {
      debugPrint('保存视频URL失败: $e');
    }
  }

  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  Future<void> _downloadVideo() async {
    if (_generatedVideo == null) return;

    bool hasPermission = false;

    if (Theme.of(context).platform == TargetPlatform.android) {
      AndroidDeviceInfo androidInfo = await _deviceInfo.androidInfo;
      int sdkInt = androidInfo.version.sdkInt;

      if (sdkInt >= 33) {
        PermissionStatus status = await Permission.photos.request();
        hasPermission = status.isGranted;
        if (!hasPermission) {
          status = await Permission.photos.request();
          hasPermission = status.isGranted;
        }
      } else {
        PermissionStatus status = await Permission.storage.request();
        hasPermission = status.isGranted;
        if (!hasPermission) {
          status = await Permission.storage.request();
          hasPermission = status.isGranted;
        }
      }
    } else if (Theme.of(context).platform == TargetPlatform.iOS) {
      PermissionStatus status = await Permission.photos.request();
      hasPermission = status.isGranted;
      if (!hasPermission) {
        status = await Permission.photos.request();
        hasPermission = status.isGranted;
      }
    }

    if (!hasPermission) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('需要权限才能保存视频，请在设置中开启')));
      await openAppSettings();
      return;
    }

    try {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('正在下载视频...')));

      final response = await http.get(Uri.parse(_generatedVideo!));
      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;

        final directory = await getTemporaryDirectory();
        final String fileName =
            'generated_video_${DateTime.now().millisecondsSinceEpoch}.mp4';
        final File file = File('${directory.path}/$fileName');

        await file.writeAsBytes(bytes);

        final result = await ImageGallerySaverPlus.saveFile(
          file.path,
          name: fileName,
        );

        await file.delete();

        if (!mounted) return;

        if (result['isSuccess'] == true) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('视频已保存到相册')));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('保存失败: ${result['error'] ?? '未知错误'}')),
          );
        }
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('下载视频失败')));
      }
    } catch (e) {
      debugPrint('下载视频错误: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('发生错误: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '视频生成',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ).animate().fadeIn(duration: 600.ms).slideY(begin: -0.2, end: 0),

              const SizedBox(height: 24),

              SoftCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('选择故事', style: Theme.of(context).textTheme.titleMedium)
                        .animate()
                        .fadeIn(duration: 800.ms, delay: 200.ms)
                        .slideX(begin: -0.2, end: 0),

                    const SizedBox(height: 16),

                    Container(
                          padding: const EdgeInsets.symmetric(
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
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
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
                                                            'title': '已选择故事',
                                                          },
                                                        )['title'] ??
                                                        '已选择故事')),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 14),
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
                        .scale(
                          begin: const Offset(0.9, 0.9),
                          end: const Offset(1, 1),
                        ),

                    if (_selectedStory != null) ...[
                      const SizedBox(height: 16),
                      Container(
                            padding: const EdgeInsets.all(16),
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

                    const SizedBox(height: 20),

                    Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '视频时长 (5-12秒)',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.accent.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      '${_videoDuration.toInt()}秒',
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
                                value: _videoDuration,
                                min: 5,
                                max: 12,
                                divisions: 7,
                                label: '${_videoDuration.toInt()}秒',
                                onChanged: (value) {
                                  setState(() {
                                    _videoDuration = value.roundToDouble();
                                  });
                                },
                                activeColor: AppColors.accent,
                                inactiveColor: AppColors.textSecondary
                                    .withOpacity(0.3),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [5, 6, 7, 8, 9, 10, 11, 12].map((
                                  duration,
                                ) {
                                  return Text(
                                    '$duration',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _videoDuration.toInt() == duration
                                          ? AppColors.accent
                                          : AppColors.textSecondary,
                                      fontWeight:
                                          _videoDuration.toInt() == duration
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        )
                        .animate()
                        .fadeIn(duration: 800.ms, delay: 500.ms)
                        .slideY(begin: 0.2, end: 0),

                    const SizedBox(height: 20),

                    GradientButton(
                          text: _isGenerating ? '生成中...' : '生成视频',
                          onPressed: _generateVideo,
                          isLoading: _isGenerating,
                          icon: _isGenerating ? null : Icons.videocam,
                        )
                        .animate()
                        .fadeIn(duration: 800.ms, delay: 600.ms)
                        .slideY(begin: 0.2, end: 0),
                  ],
                ),
              ),

              if (_generatedVideo != null) ...[
                const SizedBox(height: 24),
                SoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                            children: [
                              Icon(
                                Icons.videocam,
                                color: AppColors.accent,
                                size: 24,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '生成的视频 (${_videoDuration.toInt()}秒)',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          )
                          .animate()
                          .fadeIn(duration: 600.ms)
                          .slideX(begin: -0.2, end: 0),

                      const SizedBox(height: 16),

                      Container(
                            height: 200,
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.shadow,
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child:
                                  _isVideoInitialized &&
                                      _videoController != null
                                  ? Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        VideoPlayer(_videoController!),
                                        Positioned.fill(
                                          child: Material(
                                            color: Colors.transparent,
                                            child: InkWell(
                                              onTap: _playVideo,
                                              child: Center(
                                                child: AnimatedOpacity(
                                                  opacity:
                                                      _videoController!
                                                          .value
                                                          .isPlaying
                                                      ? 0
                                                      : 0.7,
                                                  duration: const Duration(
                                                    milliseconds: 300,
                                                  ),
                                                  child: Container(
                                                    decoration:
                                                        const BoxDecoration(
                                                          shape:
                                                              BoxShape.circle,
                                                        ),
                                                    child: Icon(
                                                      _videoController!
                                                              .value
                                                              .isPlaying
                                                          ? Icons.pause
                                                          : Icons.play_arrow,
                                                      size: 50,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          bottom: 8,
                                          left: 8,
                                          right: 8,
                                          child: VideoProgressIndicator(
                                            _videoController!,
                                            allowScrubbing: true,
                                            colors: VideoProgressColors(
                                              playedColor: AppColors.accent,
                                              bufferedColor: Colors.grey,
                                              backgroundColor: Colors.grey
                                                  .withValues(alpha: 0.5),
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  : const Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          CircularProgressIndicator(),
                                          SizedBox(height: 8),
                                          Text(
                                            '加载视频中...',
                                            style: TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                            ),
                          )
                          .animate()
                          .fadeIn(duration: 800.ms)
                          .scale(
                            begin: const Offset(0.95, 0.95),
                            end: const Offset(1, 1),
                          ),

                      const SizedBox(height: 16),

                      Row(
                        children: [
                          Expanded(
                            child:
                                OutlinedButton.icon(
                                      onPressed: _playVideo,
                                      icon: Icon(
                                        _videoController != null &&
                                                _videoController!
                                                    .value
                                                    .isPlaying
                                            ? Icons.pause
                                            : Icons.play_arrow,
                                        size: 18,
                                      ),
                                      label: Text(
                                        _videoController != null &&
                                                _videoController!
                                                    .value
                                                    .isPlaying
                                            ? '暂停'
                                            : '播放',
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                    )
                                    .animate()
                                    .fadeIn(duration: 600.ms, delay: 200.ms)
                                    .slideY(begin: 0.2, end: 0),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child:
                                ElevatedButton.icon(
                                      onPressed: _downloadVideo,
                                      icon: const Icon(
                                        Icons.download,
                                        size: 18,
                                      ),
                                      label: const Text('下载'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.accent,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                    )
                                    .animate()
                                    .fadeIn(duration: 600.ms, delay: 400.ms)
                                    .slideY(begin: 0.2, end: 0),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
