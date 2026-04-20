// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ui22/main.dart';

void main() {
  testWidgets('Story Generator App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const StoryGeneratorApp());

    // Verify that the app title is displayed.
    expect(find.text('故事生成器'), findsOneWidget);

    // Verify that navigation items are present.
    expect(find.text('故事'), findsOneWidget);
    expect(find.text('图片'), findsOneWidget);
    expect(find.text('视频'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
  });
}
