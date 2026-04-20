import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/app_icons.dart';
import 'story_page.dart';
import 'image_page.dart';
import 'video_page.dart';
import 'quiz_page.dart';
import 'profile_page.dart';

class MainNavigation extends StatefulWidget {
  final int initialIndex;
  const MainNavigation({Key? key, this.initialIndex = 0}) : super(key: key);
  
  @override
  _MainNavigationState createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    int idx = widget.initialIndex;
    if (idx < 0) idx = 0;

    if (idx > 4) idx = 0;
    _currentIndex = idx;
  }
  
  final List<Widget> _pages = [
    StoryPage(),
    ImagePage(),
    VideoPage(),
    QuizPage(),
    ProfilePage(),
  ];
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          boxShadow: [
            BoxShadow(
              color: AppColors.shadow,
              blurRadius: 8,
              offset: Offset(0, -2),
            ),
          ],
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: AppColors.accent,
          unselectedItemColor: AppColors.textSecondary,
          selectedLabelStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          unselectedLabelStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
          ),
          items: [
            BottomNavigationBarItem(
              icon: Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: AppIcons.story(
                  size: 24,
                  color: _currentIndex == 0 ? AppColors.accent : AppColors.textSecondary,
                ),
              ),
              label: '故事',
            ),
            BottomNavigationBarItem(
              icon: Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: AppIcons.image(
                  size: 24,
                  color: _currentIndex == 1 ? AppColors.accent : AppColors.textSecondary,
                ),
              ),
              label: '图片',
            ),
            BottomNavigationBarItem(
              icon: Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: AppIcons.video(
                  size: 24,
                  color: _currentIndex == 2 ? AppColors.accent : AppColors.textSecondary,
                ),
              ),
              label: '视频',
            ),
            BottomNavigationBarItem(
              icon: Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Icon(
                  Icons.quiz,
                  size: 24,
                  color: _currentIndex == 3 ? AppColors.accent : AppColors.textSecondary,
                ),
              ),
              label: '问答',
            ),
            BottomNavigationBarItem(
              icon: Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: AppIcons.profile(
                  size: 24,
                  color: _currentIndex == 4 ? AppColors.accent : AppColors.textSecondary,
                ),
              ),
              label: '我的',
            ),
          ],
        ),
      ),
    );
  }
}