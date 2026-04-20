import 'dart:convert';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_clients.dart';

class QuizUserCreateResult {
  final String id;
  final String? imageUrl;
  final int score;
  final int? rank;
  final bool inherited;

  QuizUserCreateResult({
    required this.id,
    required this.imageUrl,
    required this.score,
    required this.rank,
    required this.inherited,
  });
}

class QuizUserService {
  static const String _avatarBucket = 'quiz-avatars';
  static const String _defaultAvatarBase =
      'https://api.dicebear.com/7.x/adventurer/svg?seed=';

  static String _defaultAvatarUrl(String seed) {
    return _defaultAvatarBase + Uri.encodeComponent(seed);
  }

  static bool _looksLikeHttpUrl(String? value) {
    if (value == null) return false;
    final v = value.trim();
    return v.startsWith('http://') || v.startsWith('https://');
  }

  static bool _looksLikeDataUrl(String? value) {
    if (value == null) return false;
    return value.trim().startsWith('data:');
  }

  static Future<QuizUserCreateResult> createUser({
    required String name,
    required String? avatarDataUrl,
  }) async {
    final trimmedName = name.trim();
    final defaultAvatarUrl = _defaultAvatarUrl(trimmedName);

    final existing = await serviceSupabase
        .from('quiz_users')
        .select('id, image, score, rank')
        .eq('name', trimmedName)
        .limit(2);

    if (existing.length > 1) {
      throw Exception('NAME_CONFLICT');
    }

    if (existing.length == 1) {
      final row = existing.first;
      final id = row['id'] as String;
      final imageUrl = row['image'] as String?;
      final score = (row['score'] as int?) ?? 0;
      final rank = row['rank'] as int?;

      if (imageUrl == null || imageUrl.isEmpty) {
        final raw = (avatarDataUrl ?? '').trim();

        if (raw.isEmpty) {
          try {
            await serviceSupabase
                .from('quiz_users')
                .update({'image': defaultAvatarUrl})
                .eq('id', id);
          } catch (_) {}
          return QuizUserCreateResult(
            id: id,
            imageUrl: defaultAvatarUrl,
            score: score,
            rank: rank,
            inherited: true,
          );
        }

        if (_looksLikeHttpUrl(raw)) {
          try {
            await serviceSupabase
                .from('quiz_users')
                .update({'image': raw})
                .eq('id', id);
            return QuizUserCreateResult(
              id: id,
              imageUrl: raw,
              score: score,
              rank: rank,
              inherited: true,
            );
          } catch (_) {}
        }

        if (_looksLikeDataUrl(raw) &&
            (_tryDecodeDataUrlToBytes(raw)?.isNotEmpty ?? false)) {
          final updated = await _tryUploadAvatarAndUpdateRow(
            id: id,
            avatarDataUrl: raw,
          );
          if (updated != null && updated.isNotEmpty) {
            return QuizUserCreateResult(
              id: id,
              imageUrl: updated,
              score: score,
              rank: rank,
              inherited: true,
            );
          }
        }

        try {
          await serviceSupabase
              .from('quiz_users')
              .update({'image': defaultAvatarUrl})
              .eq('id', id);
        } catch (_) {}
        return QuizUserCreateResult(
          id: id,
          imageUrl: defaultAvatarUrl,
          score: score,
          rank: rank,
          inherited: true,
        );
      }

      return QuizUserCreateResult(
        id: id,
        imageUrl: imageUrl,
        score: score,
        rank: rank,
        inherited: true,
      );
    }

    final insertResp = await serviceSupabase
        .from('quiz_users')
        .insert({'name': trimmedName, 'image': null})
        .select('id, image, score, rank')
        .single();

    final id = insertResp['id'] as String;
    final createdScore = (insertResp['score'] as int?) ?? 0;
    final createdRank = insertResp['rank'] as int?;

    final raw = (avatarDataUrl ?? '').trim();

    if (raw.isEmpty) {
      try {
        await serviceSupabase
            .from('quiz_users')
            .update({'image': defaultAvatarUrl})
            .eq('id', id);
        return QuizUserCreateResult(
          id: id,
          imageUrl: defaultAvatarUrl,
          score: createdScore,
          rank: createdRank,
          inherited: false,
        );
      } catch (_) {
        return QuizUserCreateResult(
          id: id,
          imageUrl: null,
          score: createdScore,
          rank: createdRank,
          inherited: false,
        );
      }
    }

    if (_looksLikeHttpUrl(raw)) {
      try {
        await serviceSupabase
            .from('quiz_users')
            .update({'image': raw})
            .eq('id', id);
        return QuizUserCreateResult(
          id: id,
          imageUrl: raw,
          score: createdScore,
          rank: createdRank,
          inherited: false,
        );
      } catch (_) {}
    }

    final bytes = _tryDecodeDataUrlToBytes(raw);
    if (bytes == null || bytes.isEmpty) {
      try {
        await serviceSupabase
            .from('quiz_users')
            .update({'image': defaultAvatarUrl})
            .eq('id', id);
        return QuizUserCreateResult(
          id: id,
          imageUrl: defaultAvatarUrl,
          score: createdScore,
          rank: createdRank,
          inherited: false,
        );
      } catch (_) {
        return QuizUserCreateResult(
          id: id,
          imageUrl: null,
          score: createdScore,
          rank: createdRank,
          inherited: false,
        );
      }
    }

    final uploaded = await _tryUploadAvatarAndUpdateRow(
      id: id,
      avatarDataUrl: raw,
    );

    if (uploaded == null || uploaded.isEmpty) {
      try {
        await serviceSupabase
            .from('quiz_users')
            .update({'image': defaultAvatarUrl})
            .eq('id', id);
        return QuizUserCreateResult(
          id: id,
          imageUrl: defaultAvatarUrl,
          score: createdScore,
          rank: createdRank,
          inherited: false,
        );
      } catch (_) {
        return QuizUserCreateResult(
          id: id,
          imageUrl: null,
          score: createdScore,
          rank: createdRank,
          inherited: false,
        );
      }
    }

    return QuizUserCreateResult(
      id: id,
      imageUrl: uploaded,
      score: createdScore,
      rank: createdRank,
      inherited: false,
    );
  }

  static Future<void> incrementScore(String id) async {
    try {
      await serviceSupabase.rpc(
        'quiz_users_increment_score',
        params: {'p_id': id},
      );
      return;
    } catch (_) {}

    final row = await serviceSupabase
        .from('quiz_users')
        .select('score')
        .eq('id', id)
        .single();
    final score = (row['score'] as int?) ?? 0;
    await serviceSupabase
        .from('quiz_users')
        .update({'score': score + 1})
        .eq('id', id);
  }

  static Future<String?> _tryUploadAvatarAndUpdateRow({
    required String id,
    required String? avatarDataUrl,
  }) async {
    final bytes = _tryDecodeDataUrlToBytes(avatarDataUrl);
    if (bytes == null || bytes.isEmpty) return null;

    final path = 'quiz_users/$id.jpg';
    try {
      await serviceSupabase.storage
          .from(_avatarBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              cacheControl: '3600',
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );
      final publicUrl = serviceSupabase.storage
          .from(_avatarBucket)
          .getPublicUrl(path);

      await serviceSupabase
          .from('quiz_users')
          .update({'image': publicUrl})
          .eq('id', id);

      return publicUrl;
    } catch (e) {
      print('头像上传失败: $e');
      return null;
    }
  }

  static Uint8List? _tryDecodeDataUrlToBytes(String? dataUrl) {
    if (dataUrl == null) return null;
    final trimmed = dataUrl.trim();
    if (trimmed.isEmpty) return null;
    if (!_looksLikeDataUrl(trimmed)) return null;
    final commaIndex = trimmed.indexOf(',');
    final base64Part = commaIndex >= 0
        ? trimmed.substring(commaIndex + 1)
        : trimmed;
    try {
      return base64Decode(base64Part);
    } catch (_) {
      return null;
    }
  }
}
