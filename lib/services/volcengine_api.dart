import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/secrets.dart';

class VolcengineApi {
  static const String _baseUrl =
      'https://ark.cn-beijing.volces.com/api/v3/contents/generations/tasks';
  static const String _model = 'doubao-seedance-1-0-pro-fast-251015';

  static String get _apiKey => Secrets.arkApiKey;

  static Future<String> generateVideo(String prompt, {int duration = 5}) async {
    if (_apiKey.isEmpty) {
      throw Exception('API Key is missing');
    }

    debugPrint('开始生成视频，prompt: ${prompt.substring(0, prompt.length > 100 ? 100 : prompt.length)}...');
    debugPrint('请求时长: ${duration}秒');

    final uri = Uri.parse(_baseUrl);
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $_apiKey',
    };

    // 修改请求体，添加时长参数
    final body = jsonEncode({
      "model": _model,
      "content": [
        {"type": "text", "text": prompt},
      ],
      "duration": duration,  // 直接放在根节点
    });

    debugPrint('请求体: $body');

    try {
      debugPrint('提交视频生成任务...');
      final response = await http.post(uri, headers: headers, body: body);

      debugPrint('提交响应状态码: ${response.statusCode}');
      debugPrint('提交响应内容: ${response.body}');

      if (response.statusCode != 200) {
        throw Exception(
          'Failed to submit task: ${response.statusCode} ${response.body}',
        );
      }

      final data = jsonDecode(response.body);

      // 获取任务ID
      if (data['id'] != null) {
        final taskId = data['id'].toString();
        debugPrint('获取到任务ID: $taskId');
        return await _pollTaskResult(taskId);
      } else {
        throw Exception('Task ID not found in response: $data');
      }
    } catch (e) {
      debugPrint('Volcengine API Error: $e');
      rethrow;
    }
  }

  static Future<String> _pollTaskResult(String taskId) async {
    final uri = Uri.parse('$_baseUrl/$taskId');
    final headers = {'Authorization': 'Bearer $_apiKey'};

    int retryCount = 0;
    const maxRetries = 300; // 300 * 2s = 600s (10分钟)
    String? lastStatus;

    debugPrint('开始轮询任务结果，任务ID: $taskId');

    while (retryCount < maxRetries) {
      await Future.delayed(const Duration(seconds: 2));
      retryCount++;

      if (retryCount % 15 == 0) {
        debugPrint('轮询中... 已等待 ${retryCount * 2} 秒');
      }

      try {
        final response = await http.get(uri, headers: headers);

        if (response.statusCode != 200) {
          debugPrint('轮询失败，状态码: ${response.statusCode}');
          throw Exception(
            'Polling failed: ${response.statusCode} ${response.body}',
          );
        }

        final data = jsonDecode(response.body);

        // 获取状态
        final status = data['status']?.toString();
        lastStatus = status;

        debugPrint('轮询响应 (第$retryCount次): status = $status');

        // 成功状态
        if (status == 'Succeeded' ||
            status == 'SUCCEEDED' ||
            status == 'succeeded') {

          debugPrint('任务成功，正在提取视频URL...');

          // 尝试提取视频URL
          String? videoUrl;

          // 情况1: content 是 Map
          if (data['content'] != null && data['content'] is Map) {
            final content = data['content'] as Map;
            debugPrint('content 的 keys: ${content.keys}');

            if (content['video_url'] != null) {
              videoUrl = content['video_url'].toString();
              debugPrint('✅ 从 content.video_url 获取到URL: $videoUrl');
              return videoUrl;
            }
          }

          // 情况2: content 是 List
          if (data['content'] != null && data['content'] is List) {
            final contentList = data['content'] as List;
            if (contentList.isNotEmpty) {
              final firstItem = contentList[0];
              if (firstItem is Map && firstItem['video_url'] != null) {
                videoUrl = firstItem['video_url'].toString();
                debugPrint('✅ 从 content[0].video_url 获取到URL: $videoUrl');
                return videoUrl;
              }
            }
          }

          // 情况3: 直接有 video_url
          if (data['video_url'] != null) {
            videoUrl = data['video_url'].toString();
            debugPrint('✅ 从根节点 video_url 获取到URL: $videoUrl');
            return videoUrl;
          }

          debugPrint('❌ 无法找到视频URL，完整响应数据:');
          debugPrint(jsonEncode(data));
          throw Exception('任务成功但未找到视频URL');
        }

        // 失败状态
        else if (status == 'Failed' ||
            status == 'FAILED' ||
            status == 'failed') {
          String errorMsg = data['error']?.toString() ??
              data['message']?.toString() ??
              'Unknown error';
          debugPrint('任务失败: $errorMsg');
          throw Exception('任务失败: $errorMsg');
        }

        // 进行中状态
        else if (status == 'Running' ||
            status == 'RUNNING' ||
            status == 'running' ||
            status == 'Queued' ||
            status == 'queued' ||
            status == 'Processing' ||
            status == 'processing') {
          continue;
        }

        // 未知状态
        else {
          if (retryCount % 30 == 0) {
            debugPrint('未知状态: $status，继续等待...');
          }
          continue;
        }
      } catch (e) {
        debugPrint('轮询错误: $e');
        if (retryCount < maxRetries) {
          debugPrint('发生错误，继续重试...');
          continue;
        }
        rethrow;
      }
    }

    throw Exception('任务超时 (${maxRetries * 2}秒)。最后状态: $lastStatus');
  }
}