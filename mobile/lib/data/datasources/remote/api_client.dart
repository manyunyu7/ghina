import 'package:dio/dio.dart';

import '../../../core/failure.dart';
import 'token_store.dart';

/// Configured [Dio] for `/api/mobile/**`: bearer token, JSON, timeouts, and a
/// 401 hook for authenticated calls.
final class ApiClient {
  ApiClient({
    required String baseUrl,
    required TokenStore tokens,
    void Function()? onUnauthorized,
    Dio? dio,
  }) : dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: baseUrl,
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 30),
               sendTimeout: const Duration(seconds: 60),
               contentType: Headers.jsonContentType,
               responseType: ResponseType.json,
             ),
           ) {
    this.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (options.extra['auth'] != false) {
            final token = await tokens.readToken();
            if (token != null) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }
          handler.next(options);
        },
        onError: (e, handler) {
          final authed = e.requestOptions.headers.containsKey('Authorization');
          if (e.response?.statusCode == 401 && authed) onUnauthorized?.call();
          handler.next(e);
        },
      ),
    );
  }

  final Dio dio;

  /// Options for endpoints that must not carry the token (login/register/google).
  static Options get anonymous => Options(extra: {'auth': false});
}

/// Converts dio errors to domain [Failure]s using the server's `{error}` message.
Failure mapDioError(Object error) {
  if (error is Failure) return error;
  if (error is! DioException) return UnknownFailure('Terjadi kesalahan', error);
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.connectionError:
      return const NetworkFailure();
    case DioExceptionType.unknown:
      return error.response == null
          ? const NetworkFailure()
          : UnknownFailure('Terjadi kesalahan', error);
    default:
      break;
  }
  final res = error.response;
  final data = res?.data;
  final msg = data is Map && data['error'] is String
      ? data['error'] as String
      : null;
  return switch (res?.statusCode) {
    401 => UnauthorizedFailure(msg ?? 'Sesi kamu sudah berakhir'),
    400 || 422 => ValidationFailure(msg ?? 'Data tidak valid'),
    404 => NotFoundFailure(msg ?? 'Data tidak ditemukan'),
    409 => ConflictFailure(msg ?? 'Terjadi konflik data'),
    503 => UnknownFailure(msg ?? 'Layanan belum tersedia', error),
    _ => UnknownFailure(msg ?? 'Server bermasalah (${res?.statusCode})', error),
  };
}

/// Runs a request, rethrowing any error as a [Failure].
Future<T> apiCall<T>(Future<T> Function() body) async {
  try {
    return await body();
  } catch (e) {
    throw mapDioError(e);
  }
}
