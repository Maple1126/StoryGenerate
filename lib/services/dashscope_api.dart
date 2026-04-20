import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/secrets.dart';

class _DashscopeHttpException implements Exception {
  final int statusCode;
  final String body;
  final String operation;

  _DashscopeHttpException({
    required this.statusCode,
    required this.body,
    required this.operation,
  });

  @override
  String toString() {
    return 'DashScope HTTP $statusCode ($operation): $body';
  }
}

class DashscopeApi {
  static const String _baseUrl =
      'https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation';
  static const String _taskUrl = 'https://dashscope.aliyuncs.com/api/v1/tasks';
  static const String _model = 'wan2.6-t2i';
  static const Duration _requestTimeout = Duration(seconds: 90);
  static const int _max429Retries = 3;

  static String get _apiKey => Secrets.dashscopeApiKey;

  static Exception _wrapNetworkError(Object e) {
    final msg = e.toString();
    if (kIsWeb) {
      return Exception('网络请求失败（Web可能被跨域/CORS拦截）：$msg');
    }
    if (msg.contains('Failed host lookup') || msg.contains('SocketException')) {
      return Exception('网络或DNS异常，请检查真机网络/代理/VPN后重试：$msg');
    }
    if (msg.contains('HandshakeException') ||
        msg.contains('CERTIFICATE_VERIFY_FAILED')) {
      return Exception('HTTPS证书握手失败，请检查系统时间或网络拦截：$msg');
    }
    if (msg.contains('timed out') || msg.contains('TimeoutException')) {
      return Exception('请求超时，请切换网络后重试：$msg');
    }
    return Exception('网络请求失败：$msg');
  }

  static Duration _backoffForAttempt(int attempt) {
    final baseMs = 900 * (1 << attempt);
    final jitterMs = DateTime.now().microsecondsSinceEpoch % 400;
    return Duration(milliseconds: baseMs + jitterMs);
  }

  /// Generate images based on the provided prompt.
  /// Returns a list of image URLs.
  static Future<List<String>> generateImages(
    String prompt, {
    int n = 2,
    bool promptExtend = true,
    String size = "1280*1280",
  }) async {
    if (_apiKey.isEmpty) {
      throw Exception('API Key is missing');
    }

    Future<List<String>> submitOnce() async {
      final uri = Uri.parse(_baseUrl);
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
        'Accept': 'application/json',
        'User-Agent': 'ui22/flutter',
      };

      final body = jsonEncode({
        "model": _model,
        "input": {
          "messages": [
            {
              "role": "user",
              "content": [
                {"text": prompt},
              ],
            },
          ],
        },
        "parameters": {
          "prompt_extend": promptExtend,
          "watermark": false,
          "n": n,
          "size": size,
        },
      });

      final response = await http
          .post(uri, headers: headers, body: body)
          .timeout(_requestTimeout);

      if (response.statusCode != 200) {
        throw _DashscopeHttpException(
          statusCode: response.statusCode,
          body: response.body,
          operation: 'submit',
        );
      }

      final data = jsonDecode(response.body);
      final output = data['output'];

      if (output != null && output['task_id'] != null) {
        final taskId = output['task_id'];
        return await _pollTaskResult(taskId);
      } else if (output != null && output['results'] != null) {
        final results = output['results'] as List;
        return results.map((e) => e['url'] as String).toList();
      } else if (output != null && output['choices'] != null) {
        final choices = output['choices'] as List;
        final List<String> imageUrls = [];

        for (var choice in choices) {
          final message = choice['message'];
          if (message != null && message['content'] != null) {
            final contentList = message['content'] as List;
            for (var content in contentList) {
              if (content['image'] != null) {
                imageUrls.add(content['image'] as String);
              }
            }
          }
        }

        if (imageUrls.isEmpty) {
          throw Exception('No images found in response choices');
        }

        return imageUrls;
      } else {
        throw Exception('Unknown response format: $data');
      }
    }

    for (var attempt = 0; attempt <= _max429Retries; attempt++) {
      try {
        return await submitOnce();
      } on _DashscopeHttpException catch (e) {
        if (e.statusCode == 429 && attempt < _max429Retries) {
          await Future.delayed(_backoffForAttempt(attempt));
          continue;
        }
        rethrow;
      } on TimeoutException catch (e) {
        throw _wrapNetworkError(e);
      } catch (e) {
        throw _wrapNetworkError(e);
      }
    }

    throw Exception('请求失败，请稍后重试');
  }

  static Future<List<String>> _pollTaskResult(String taskId) async {
    final uri = Uri.parse('$_taskUrl/$taskId');
    final headers = {'Authorization': 'Bearer $_apiKey'};

    int retryCount = 0;
    const maxRetries = 60; // 60 * 2s = 120s timeout

    while (retryCount < maxRetries) {
      await Future.delayed(Duration(seconds: 2));

      try {
        final response =
            await http.get(uri, headers: headers).timeout(_requestTimeout);

        if (response.statusCode == 429) {
          await Future.delayed(_backoffForAttempt((retryCount / 10).floor()));
          retryCount++;
          continue;
        }
        if (response.statusCode != 200) {
          throw _DashscopeHttpException(
            statusCode: response.statusCode,
            body: response.body,
            operation: 'poll',
          );
        }

        final data = jsonDecode(response.body);
        final output = data['output'];
        final taskStatus = output['task_status'];

        if (taskStatus == 'SUCCEEDED') {
          if (output['results'] != null) {
            final results = output['results'] as List;
            return results.map((e) => e['url'] as String).toList();
          }
          return [];
        } else if (taskStatus == 'FAILED') {
          throw Exception(
            'Task failed: ${output['message'] ?? 'Unknown error'}',
          );
        } else if (taskStatus == 'PENDING' || taskStatus == 'RUNNING') {
          // Continue polling
          retryCount++;
          continue;
        } else {
          throw Exception('Unknown task status: $taskStatus');
        }
      } catch (e) {
        if (e is _DashscopeHttpException) rethrow;
        throw _wrapNetworkError(e);
      }
    }

    throw Exception('Task timed out');
  }
}
