import 'package:dio/dio.dart';

import '../../models/api_dto.dart';
import '../../models/wire.dart';
import 'api_client.dart';

/// The sync endpoints. Implementations throw `Failure`s (e.g. `NetworkFailure`) and
/// [EpochChangedException] when a push is refused because of a new epoch.
abstract interface class SyncApi {
  Future<PullResponse> pull(int since);
  Future<PushResponse> push(List<PushMutation> mutations, {String? epoch});

  /// Uploads an image or audio file (voice notes); returns the server path
  /// (`/uploads/…`, response `{url, kind}`). The server judges the type by the
  /// file's bytes — callers check the returned extension (`uploadImageRe`,
  /// `uploadAudioRe`) before using it.
  Future<String> upload(String filePath);
}

final class DioSyncApi implements SyncApi {
  DioSyncApi(this._client);
  final ApiClient _client;

  @override
  Future<PullResponse> pull(int since) => apiCall(() async {
    final r = await _client.dio.get<Json>(
      '/api/mobile/sync',
      queryParameters: {'since': since},
    );
    return PullResponse.fromJson(r.data!);
  });

  @override
  Future<PushResponse> push(
    List<PushMutation> mutations, {
    String? epoch,
  }) async {
    try {
      final r = await _client.dio.post<Json>(
        '/api/mobile/sync',
        data: {
          'epoch': ?epoch,
          'mutations': [for (final m in mutations) m.toJson()],
        },
      );
      return PushResponse.fromJson(r.data!);
    } on DioException catch (e) {
      final data = e.response?.data;
      if (e.response?.statusCode == 409 &&
          data is Map &&
          data.containsKey('epoch')) {
        throw EpochChangedException(data['epoch'] as String?);
      }
      throw mapDioError(e);
    }
  }

  @override
  Future<String> upload(String filePath) => apiCall(() async {
    final name = filePath.split(RegExp(r'[/\\]')).last;
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        filePath,
        filename: name,
        contentType: _mediaType(name),
      ),
    });
    final r = await _client.dio.post<Json>('/api/mobile/upload', data: form);
    return r.data!['url'] as String;
  });

  static DioMediaType _mediaType(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return switch (ext) {
      'png' => DioMediaType('image', 'png'),
      'webp' => DioMediaType('image', 'webp'),
      'gif' => DioMediaType('image', 'gif'),
      'heic' || 'heif' => DioMediaType('image', 'heic'),
      'm4a' || 'mp4' => DioMediaType('audio', 'mp4'),
      'aac' => DioMediaType('audio', 'aac'),
      'mp3' => DioMediaType('audio', 'mpeg'),
      'ogg' || 'opus' => DioMediaType('audio', 'ogg'),
      'webm' => DioMediaType('audio', 'webm'),
      _ => DioMediaType('image', 'jpeg'),
    };
  }
}
