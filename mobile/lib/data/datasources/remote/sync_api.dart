import 'package:dio/dio.dart';

import '../../models/api_dto.dart';
import '../../models/wire.dart';
import 'api_client.dart';

/// The sync endpoints. Implementations throw `Failure`s (e.g. `NetworkFailure`) and
/// [EpochChangedException] when a push is refused because of a new epoch.
abstract interface class SyncApi {
  Future<PullResponse> pull(int since);
  Future<PushResponse> push(List<PushMutation> mutations, {String? epoch});

  /// Uploads an image file; returns the server path (`/uploads/…`).
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
        contentType: DioMediaType('image', _imageSubtype(name)),
      ),
    });
    final r = await _client.dio.post<Json>('/api/mobile/upload', data: form);
    return r.data!['url'] as String;
  });

  static String _imageSubtype(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return switch (ext) {
      'png' => 'png',
      'webp' => 'webp',
      'gif' => 'gif',
      'heic' => 'heic',
      _ => 'jpeg',
    };
  }
}
