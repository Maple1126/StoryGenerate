import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_components.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'login_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({Key? key}) : super(key: key);

  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  int _selectedTab = 0;
  int _refreshKey = 0;

  // 头像相关变量
  String? _avatarUrl;
  bool _isUploadingAvatar = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadAvatar();
  }

  // 加载用户头像
  Future<void> _loadAvatar() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final response = await Supabase.instance.client
          .from('profiles')
          .select('avatar_url')
          .eq('id', userId)
          .maybeSingle();

      if (mounted && response != null) {
        setState(() {
          _refreshKey++;
          _avatarUrl = response['avatar_url'] as String?;
        });
      }
    } catch (e) {
      print('加载头像失败: $e');
    }
  }

  // 选择并上传头像
  Future<void> _pickAndUploadAvatar() async {
    // 请求权限
    final status = await Permission.photos.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要相册权限才能选择头像')),
        );
      }
      return;
    }

    // 选择图片
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );

    if (image == null) return;

    if (!mounted) return;

    setState(() {
      _isUploadingAvatar = true;
    });

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final file = File(image.path);
      final fileExt = image.path.split('.').last;
      // 使用 generated_media bucket，放在 avatars 文件夹下
      final fileName = 'avatars/$userId.$fileExt';

      // 读取文件字节
      final bytes = await file.readAsBytes();

      // 上传到 Supabase Storage（使用现有的 generated_media bucket）
      await Supabase.instance.client.storage
          .from('generated_media')
          .uploadBinary(
        fileName,
        bytes,
        fileOptions: const FileOptions(
          upsert: true,
          contentType: 'image/jpeg',
        ),
      );

      // 获取公开 URL
      final avatarUrl = Supabase.instance.client.storage
          .from('generated_media')
          .getPublicUrl(fileName);

      // 更新 profiles 表
      await Supabase.instance.client
          .from('profiles')
          .upsert({
        'id': userId,
        'avatar_url': avatarUrl,
        'updated_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        setState(() {
          _avatarUrl = avatarUrl;
          _isUploadingAvatar = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('头像上传成功！'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('上传头像失败: $e');
      if (mounted) {
        setState(() {
          _isUploadingAvatar = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('上传失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 显示头像选择选项
  void _showAvatarOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '更换头像',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.photo_library, color: AppColors.accent),
                title: const Text('从相册选择'),
                onTap: () {
                  Navigator.pop(context);
                  _pickAndUploadAvatar();
                },
              ),
              if (_avatarUrl != null)
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text('移除头像'),
                  onTap: () {
                    Navigator.pop(context);
                    _removeAvatar();
                  },
                ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  // 移除头像
  Future<void> _removeAvatar() async {
    setState(() {
      _isUploadingAvatar = true;
    });

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      await Supabase.instance.client
          .from('profiles')
          .update({'avatar_url': null})
          .eq('id', userId);

      if (mounted) {
        setState(() {
          _avatarUrl = null;
          _isUploadingAvatar = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('头像已移除')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploadingAvatar = false;
        });
      }
    }
  }

  Widget _buildHistoryTab() {
    return FutureBuilder(
      key: ValueKey(_refreshKey),
      future: Supabase.instance.client
          .from('stories')
          .select('content, created_at, image_urls, video_url')
          .eq('user_id', Supabase.instance.client.auth.currentUser!.id)
          .order('created_at', ascending: false),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || (snapshot.data as List).isEmpty) {
          return Center(
            child: Text(
              '还没有生成过故事哦～\n去"故事"页面创作一个吧！',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
            ),
          );
        }

        final stories = snapshot.data as List;

        return ListView.builder(
          padding: EdgeInsets.all(16),
          itemCount: stories.length,
          itemBuilder: (context, index) {
            final story = stories[index];
            final content = story['content'] as String;
            final createdAt = DateTime.parse(story['created_at']).toLocal();

            return FutureBuilder(
              key: ValueKey(_refreshKey),
              future: Supabase.instance.client

                  .from('favorites')
                  .select('id')
                  .eq('user_id', Supabase.instance.client.auth.currentUser!.id)
                  .eq('content', content)
                  .maybeSingle(),
              builder: (context, favSnapshot) {
                bool isFavorited = favSnapshot.hasData && favSnapshot.data != null;

                return Container(
                  margin: EdgeInsets.only(bottom: 12),
                  child: SoftCard(
                    padding: 16,
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: AppColors.cardBackground,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          title: Row(
                            children: [
                              Icon(Icons.auto_stories, color: AppColors.accent),
                              SizedBox(width: 8),
                              Text(
                                '完整故事',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          content: SizedBox(
                            width: double.maxFinite,
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    content,
                                    style: TextStyle(
                                      fontSize: 16,
                                      height: 1.6,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  // 显示图片
                                  if (story['image_urls'] != null && (story['image_urls'] as List).isNotEmpty) ...[
                                    SizedBox(height: 16),
                                    Text(
                                      '生成的图片：',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    SizedBox(height: 8),
                                    SizedBox(
                                      height: 150,
                                      child: ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: (story['image_urls'] as List).length,
                                        itemBuilder: (context, imgIndex) {
                                          return Container(
                                            width: 150,
                                            margin: EdgeInsets.only(right: 8),
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(8),
                                              image: DecorationImage(
                                                image: NetworkImage((story['image_urls'] as List)[imgIndex]),
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                  // 显示视频链接
                                  if (story['video_url'] != null && story['video_url'].toString().isNotEmpty) ...[
                                    SizedBox(height: 16),
                                    Text(
                                      '生成的视频：',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    SizedBox(height: 8),
                                    GestureDetector(
                                      onTap: () {
                                        final videoUrl = story['video_url'].toString();
                                        launchUrl(Uri.parse(videoUrl), mode: LaunchMode.externalApplication);
                                      },
                                      child: Container(
                                        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(8),
                                          color: AppColors.accent.withOpacity(0.1),
                                          border: Border.all(color: AppColors.accent),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(Icons.videocam, color: AppColors.accent, size: 20),
                                            SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                '点击观看视频',
                                                style: TextStyle(color: AppColors.accent),
                                              ),
                                            ),
                                            Icon(Icons.open_in_new, color: AppColors.accent, size: 16),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: Text(
                                '关闭',
                                style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    child: Row(
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: LinearGradient(
                              colors: [AppColors.primaryGradientStart, AppColors.primaryGradientEnd],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Icon(
                            Icons.auto_stories,
                            color: Colors.white,
                            size: 30,
                          ),
                        ).animate()
                            .fadeIn(duration: 600.ms, delay: (index * 100).ms)
                            .scale(begin: Offset(0.8, 0.8), end: Offset(1, 1)),

                        SizedBox(width: 16),

                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.auto_stories,
                                    size: 16,
                                    color: AppColors.accent,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    '我的故事 ${stories.length - index}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8),
                              Text(
                                content.length > 60 ? content.substring(0, 60) + '...' : content,
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 14,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: 4),
                              Text(
                                '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary.withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        ),

                        IconButton(
                          iconSize: 30,
                          icon: Icon(
                            isFavorited ? Icons.favorite : Icons.favorite_border,
                            color: isFavorited ? Colors.red : AppColors.textSecondary.withOpacity(0.8),
                          ),
                          onPressed: () async {
                            final userId = Supabase.instance.client.auth.currentUser?.id;
                            if (userId == null) return;

                            try {
                              if (isFavorited) {
                                await Supabase.instance.client
                                    .from('favorites')
                                    .delete()
                                    .match({'user_id': userId, 'content': content});
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('已取消收藏')),
                                );
                              } else {
                                await Supabase.instance.client.from('favorites').insert({
                                  'user_id': userId,
                                  'content': content,
                                  'image_urls': story['image_urls'] ?? [],
                                  'video_url': story['video_url'],
                                  'created_at': DateTime.now().toIso8601String(),
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('已收藏！')),
                                );
                              }
                              setState(() {});
// 刷新当前页面
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(builder: (context) => const ProfilePage()),
                              );
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('操作失败，请重试')),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildFavoritesTab() {
    return FutureBuilder(
      future: Supabase.instance.client
          .from('favorites')
          .select('content, created_at, image_urls, video_url')
          .eq('user_id', Supabase.instance.client.auth.currentUser!.id)
          .order('created_at', ascending: false),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || (snapshot.data as List).isEmpty) {
          return Center(
            child: Text(
              '你还没有收藏故事～',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
            ),
          );
        }

        final favorites = snapshot.data as List;

        return ListView.builder(
          padding: EdgeInsets.all(16),
          itemCount: favorites.length,
          itemBuilder: (context, index) {
            final favorite = favorites[index];
            final content = favorite['content'] as String;
            final createdAt = DateTime.parse(favorite['created_at']).toLocal();

            return Container(
              margin: EdgeInsets.only(bottom: 12),
              child: SoftCard(
                padding: 16,
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: AppColors.cardBackground,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      title: Row(
                        children: [
                          Icon(Icons.favorite, color: Colors.red),
                          SizedBox(width: 8),
                          Text(
                            '收藏的故事',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      content: SizedBox(
                        width: double.maxFinite,
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                content,
                                style: TextStyle(
                                  fontSize: 16,
                                  height: 1.6,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              // 显示图片
                              if (favorite['image_urls'] != null && (favorite['image_urls'] as List).isNotEmpty) ...[
                                SizedBox(height: 16),
                                Text(
                                  '生成的图片：',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                SizedBox(height: 8),
                                SizedBox(
                                  height: 150,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: (favorite['image_urls'] as List).length,
                                    itemBuilder: (context, imgIndex) {
                                      return Container(
                                        width: 150,
                                        margin: EdgeInsets.only(right: 8),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(8),
                                          image: DecorationImage(
                                            image: NetworkImage((favorite['image_urls'] as List)[imgIndex]),
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                              // 显示视频链接
                              if (favorite['video_url'] != null && favorite['video_url'].toString().isNotEmpty) ...[
                                SizedBox(height: 16),
                                Text(
                                  '生成的视频：',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                SizedBox(height: 8),
                                GestureDetector(
                                  onTap: () {
                                    final videoUrl = favorite['video_url'].toString();
                                    launchUrl(Uri.parse(videoUrl), mode: LaunchMode.externalApplication);
                                  },
                                  child: Container(
                                    padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      color: AppColors.accent.withOpacity(0.1),
                                      border: Border.all(color: AppColors.accent),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.videocam, color: AppColors.accent, size: 20),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '点击观看视频',
                                            style: TextStyle(color: AppColors.accent),
                                          ),
                                        ),
                                        Icon(Icons.open_in_new, color: AppColors.accent, size: 16),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(
                            '关闭',
                            style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                child: Row(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          colors: [Colors.redAccent, Colors.pinkAccent],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Icon(
                        Icons.favorite,
                        color: Colors.white,
                        size: 30,
                      ),
                    ).animate()
                        .fadeIn(duration: 600.ms, delay: (index * 100).ms)
                        .scale(begin: Offset(0.8, 0.8), end: Offset(1, 1)),

                    SizedBox(width: 16),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.favorite,
                                size: 16,
                                color: Colors.red,
                              ),
                              SizedBox(width: 4),
                              Text(
                                '收藏的故事 ${favorites.length - index}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 8),
                          Text(
                            content.length > 60 ? content.substring(0, 60) + '...' : content,
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 4),
                          Text(
                            '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),

                    IconButton(
                      iconSize: 30,
                      icon: Icon(
                        Icons.delete_outline,
                        color: AppColors.textSecondary.withOpacity(0.8),
                      ),
                      onPressed: () async {
                        final userId = Supabase.instance.client.auth.currentUser?.id;
                        if (userId == null) return;

                        try {
                          await Supabase.instance.client
                              .from('favorites')
                              .delete()
                              .match({'user_id': userId, 'content': content});

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('已移除收藏')),
                          );
                          setState(() {});
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('操作失败')),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // 登出功能
  Future<void> _logout() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '确认登出',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
        content: Text(
          '确定要登出当前账号吗？',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '取消',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await Supabase.instance.client.auth.signOut();
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                      (route) => false,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              '确认登出',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // 清除所有生成记录
  Future<void> _clearHistory() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '清除历史记录',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
        content: Text(
          '确定要清除所有故事生成记录吗？此操作不可恢复。',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '取消',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await Supabase.instance.client
                    .from('stories')
                    .delete()
                    .eq('user_id', userId);
                await Supabase.instance.client
                    .from('generated_media')
                    .delete()
                    .eq('user_id', userId);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('历史记录已清除'), backgroundColor: Colors.green),
                );
                setState(() {});
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('清除失败：$e'), backgroundColor: Colors.red),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              '确认清除',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // 清除所有收藏
  Future<void> _clearAllFavorites() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '清除所有收藏',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
        content: Text(
          '确定要清除所有收藏的故事吗？此操作不可恢复。',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '取消',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await Supabase.instance.client
                    .from('favorites')
                    .delete()
                    .eq('user_id', userId);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('所有收藏已清除'), backgroundColor: Colors.green),
                );
                setState(() {});
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('清除失败：$e'), backgroundColor: Colors.red),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              '确认清除',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // 显示关于信息
  void _showAbout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.info_outline, color: AppColors.accent),
            SizedBox(width: 8),
            Text(
              '关于',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '故事生成器',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            SizedBox(height: 8),
            Text(
              '版本 1.0.0',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            SizedBox(height: 8),
            Text(
              '功能列表：',
              style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            SizedBox(height: 4),
            Text('• AI 故事生成', style: TextStyle(color: AppColors.textSecondary)),
            Text('• AI 图片生成（2-5张）', style: TextStyle(color: AppColors.textSecondary)),
            Text('• AI 视频生成（5-12秒）', style: TextStyle(color: AppColors.textSecondary)),
            Text('• 故事收藏功能', style: TextStyle(color: AppColors.textSecondary)),
            Text('• 历史记录查看', style: TextStyle(color: AppColors.textSecondary)),
            Text('• 头像自定义功能', style: TextStyle(color: AppColors.textSecondary)),
            SizedBox(height: 16),
            Text(
              '技术支持：火山引擎、阿里云',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary.withOpacity(0.7)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '关闭',
              style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    return ListView(
      padding: EdgeInsets.all(16),
      children: [
        // 账号信息卡片
        SoftCard(
          padding: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.account_circle, color: AppColors.accent, size: 24),
                  SizedBox(width: 12),
                  Text(
                    '账号信息',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                ],
              ),
              SizedBox(height: 12),
              Row(
                children: [
                  Text('邮箱：', style: TextStyle(color: AppColors.textSecondary)),
                  SizedBox(width: 8),
                  Text(
                    Supabase.instance.client.auth.currentUser?.email ?? '未知',
                    style: TextStyle(color: AppColors.textPrimary),
                  ),
                ],
              ),
            ],
          ),
        ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.2, end: 0),

        SizedBox(height: 16),

        // 数据管理卡片
        SoftCard(
          padding: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.data_usage, color: AppColors.accent, size: 24),
                  SizedBox(width: 12),
                  Text(
                    '数据管理',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                ],
              ),
              SizedBox(height: 12),
              _buildSettingItem(
                icon: Icons.delete_sweep,
                title: '清除历史记录',
                subtitle: '删除所有故事和媒体生成记录',
                color: Colors.orange,
                onTap: _clearHistory,
              ),
              Divider(height: 1, color: AppColors.textSecondary.withOpacity(0.2)),
              _buildSettingItem(
                icon: Icons.favorite,
                title: '清除所有收藏',
                subtitle: '删除所有收藏的故事',
                color: Colors.red,
                onTap: _clearAllFavorites,
              ),
            ],
          ),
        ).animate().fadeIn(duration: 600.ms, delay: 100.ms).slideY(begin: 0.2, end: 0),

        SizedBox(height: 16),

        // 关于卡片
        SoftCard(
          padding: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info, color: AppColors.accent, size: 24),
                  SizedBox(width: 12),
                  Text(
                    '关于',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                ],
              ),
              SizedBox(height: 12),
              _buildSettingItem(
                icon: Icons.info_outline,
                title: '关于应用',
                subtitle: '版本 1.0.0',
                color: AppColors.accent,
                onTap: _showAbout,
              ),
              Divider(height: 1, color: AppColors.textSecondary.withOpacity(0.2)),
              _buildSettingItem(
                icon: Icons.privacy_tip,
                title: '隐私政策',
                subtitle: '查看隐私政策',
                color: AppColors.accent,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('隐私政策功能开发中...')),
                  );
                },
              ),
            ],
          ),
        ).animate().fadeIn(duration: 600.ms, delay: 200.ms).slideY(begin: 0.2, end: 0),

        SizedBox(height: 16),

        // 登出按钮
        GestureDetector(
          onTap: _logout,
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.logout, color: Colors.red, size: 24),
                SizedBox(width: 12),
                Text(
                  '登出账号',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.red),
                ),
              ],
            ),
          ),
        ).animate().fadeIn(duration: 600.ms, delay: 300.ms).slideY(begin: 0.2, end: 0),
      ],
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    VoidCallback? onTap,
    bool showArrow = true,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(
        title,
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      trailing: showArrow
          ? Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 20)
          : null,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final userEmail = Supabase.instance.client.auth.currentUser?.email ?? '用户';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.all(20),
              child: Row(
                children: [
                  // 头像可点击
                  GestureDetector(
                    onTap: _showAvatarOptions,
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: _avatarUrl == null
                            ? LinearGradient(
                          colors: [AppColors.primaryGradientStart, AppColors.primaryGradientEnd],
                        )
                            : null,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: AppColors.accent.withOpacity(0.5),
                          width: 2,
                        ),
                      ),
                      child: _isUploadingAvatar
                          ? const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                      )
                          : _avatarUrl != null
                          ? ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: Image.network(
                          _avatarUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(Icons.person, color: Colors.white, size: 36);
                          },
                        ),
                      )
                          : Icon(Icons.person, color: Colors.white, size: 36),
                    ),
                  ),
                  SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '欢迎回来！',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      Text(
                        userEmail,
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 600.ms).slideY(begin: -0.2, end: 0),

            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedTab = 0),
                      child: Container(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _selectedTab == 0 ? AppColors.accent : AppColors.cardBackground,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 4, offset: Offset(0, 2))],
                        ),
                        child: Text(
                          '历史记录',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _selectedTab == 0 ? Colors.white : AppColors.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedTab = 1),
                      child: Container(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _selectedTab == 1 ? AppColors.accent : AppColors.cardBackground,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 4, offset: Offset(0, 2))],
                        ),
                        child: Text(
                          '收藏',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _selectedTab == 1 ? Colors.white : AppColors.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedTab = 2),
                      child: Container(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _selectedTab == 2 ? AppColors.accent : AppColors.cardBackground,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 4, offset: Offset(0, 2))],
                        ),
                        child: Text(
                          '设置',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _selectedTab == 2 ? Colors.white : AppColors.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 800.ms).slideY(begin: 0.2, end: 0),

            SizedBox(height: 16),

            Expanded(
              child: AnimatedSwitcher(
                duration: Duration(milliseconds: 300),
                child: _selectedTab == 0
                    ? _buildHistoryTab()
                    : _selectedTab == 1
                    ? _buildFavoritesTab()
                    : _buildSettingsTab(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}