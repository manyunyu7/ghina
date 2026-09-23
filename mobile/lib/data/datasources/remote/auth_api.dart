import '../../models/api_dto.dart';
import '../../models/wire.dart';
import 'api_client.dart';
import '../../../domain/entities/entities.dart';

/// `/api/mobile/auth/*` and `/api/mobile/me`. Throws `Failure`s.
class AuthApi {
  AuthApi(this._client);
  final ApiClient _client;

  Future<AuthResponse> login(String email, String password) =>
      apiCall(() async {
        final r = await _client.dio.post<Json>(
          '/api/mobile/auth/login',
          data: {'email': email, 'password': password},
          options: ApiClient.anonymous,
        );
        return AuthResponse.fromJson(r.data!);
      });

  Future<AuthResponse> register(String name, String email, String password) =>
      apiCall(() async {
        final r = await _client.dio.post<Json>(
          '/api/mobile/auth/register',
          data: {'name': name, 'email': email, 'password': password},
          options: ApiClient.anonymous,
        );
        return AuthResponse.fromJson(r.data!);
      });

  Future<AuthResponse> google(String idToken) => apiCall(() async {
    final r = await _client.dio.post<Json>(
      '/api/mobile/auth/google',
      data: {'idToken': idToken},
      options: ApiClient.anonymous,
    );
    return AuthResponse.fromJson(r.data!);
  });

  Future<AppUser> me() => apiCall(() async {
    final r = await _client.dio.get<Json>('/api/mobile/me');
    return appUserFromJson(r.data!['user'] as Json);
  });

  Future<AppUser> updateMe({String? name, String? currency}) =>
      apiCall(() async {
        final r = await _client.dio.patch<Json>(
          '/api/mobile/me',
          data: {'name': ?name, 'currency': ?currency},
        );
        return appUserFromJson(r.data!['user'] as Json);
      });
}
