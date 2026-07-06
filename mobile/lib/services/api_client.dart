import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/server_config.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final String? code;

  bool get isEmailNotVerified => code == 'email_not_verified';

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({String? accessToken, String? baseUrl}) {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl ?? ServerConfig.apiBase,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Content-Type': 'application/json'},
      ),
    );
    if (kDebugMode) {
      _dio.interceptors.add(
        LogInterceptor(
          requestBody: true,
          responseBody: false,
          logPrint: (line) => debugPrint(line.toString()),
        ),
      );
    }
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.extra['skipBearer'] == true) {
            options.headers.remove('Authorization');
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final status = error.response?.statusCode;
          final path = error.requestOptions.path;
          final canRefresh = status == 401 &&
              onUnauthorized != null &&
              !path.startsWith('/api/auth/');
          if (!canRefresh) {
            return handler.next(error);
          }
          final refreshed = await onUnauthorized!.call();
          if (!refreshed) {
            return handler.next(error);
          }
          try {
            final auth = _dio.options.headers['Authorization'];
            if (auth != null) {
              error.requestOptions.headers['Authorization'] = auth;
            }
            final response = await _dio.fetch<dynamic>(error.requestOptions);
            return handler.resolve(response);
          } on DioException catch (e) {
            return handler.next(e);
          }
        },
      ),
    );
    if (accessToken != null && accessToken.isNotEmpty) {
      setAccessToken(accessToken);
    }
  }

  late final Dio _dio;

  /// 401 时尝试 refresh；返回 true 表示已成功刷新并可重试原请求。
  Future<bool> Function()? onUnauthorized;

  void setAccessToken(String? token) {
    if (token == null || token.isEmpty) {
      _dio.options.headers.remove('Authorization');
      return;
    }
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  void setBaseUrl(String url) {
    _dio.options.baseUrl = ServerConfig.normalizeApiBase(url);
  }

  String get baseUrl => _dio.options.baseUrl;

  Future<Map<String, dynamic>> getJson(String path,
      {Map<String, dynamic>? query}) async {
    try {
      final res =
          await _dio.get<Map<String, dynamic>>(path, queryParameters: query);
      return res.data ?? {};
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? body,
    Duration? receiveTimeout,
    Duration? sendTimeout,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        path,
        data: body ?? {},
        options: Options(
          receiveTimeout: receiveTimeout,
          sendTimeout: sendTimeout,
        ),
      );
      return res.data ?? {};
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// 不带 Authorization 的 POST（用于 refresh）。
  ///
  /// 通过 [skipBearer] 仅对本请求去掉 Bearer，不修改 [BaseOptions.headers]，
  /// 避免 Dio 5 清掉全局 Authorization 导致后续请求 401→refresh 循环。
  Future<Map<String, dynamic>> postJsonPublic(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        path,
        data: body ?? {},
        options: Options(extra: {'skipBearer': true}),
      );
      return res.data ?? {};
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<Map<String, dynamic>> patchJson(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final res =
          await _dio.patch<Map<String, dynamic>>(path, data: body ?? {});
      return res.data ?? {};
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<Map<String, dynamic>> putJson(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final res = await _dio.put<Map<String, dynamic>>(path, data: body ?? {});
      return res.data ?? {};
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<Map<String, dynamic>> deleteJson(String path) async {
    try {
      final res = await _dio.delete<Map<String, dynamic>>(path);
      return res.data ?? {};
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<Map<String, dynamic>> postMultipart(
    String path, {
    required String field,
    required String filename,
    required List<int> bytes,
    Map<String, String>? fields,
    Duration? receiveTimeout,
    Duration? sendTimeout,
    Duration? connectTimeout,
  }) async {
    try {
      // 服务端按 part 顺序解析：conversation_id 须在 file 之前。
      final form = FormData();
      if (fields != null) {
        for (final entry in fields.entries) {
          form.fields.add(MapEntry(entry.key, entry.value));
        }
      }
      form.files.add(
        MapEntry(
          field,
          MultipartFile.fromBytes(bytes, filename: filename),
        ),
      );
      final res = await _dio.post<Map<String, dynamic>>(
        path,
        data: form,
        options: Options(
          contentType: 'multipart/form-data',
          connectTimeout: connectTimeout ?? const Duration(seconds: 60),
          receiveTimeout: receiveTimeout,
          sendTimeout: sendTimeout,
        ),
      );
      return res.data ?? {};
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<List<int>> getBytes(
    String path, {
    Duration? receiveTimeout,
  }) async {
    try {
      final res = await _dio.get<List<int>>(
        path,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: receiveTimeout,
        ),
      );
      return res.data ?? [];
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  ApiException _mapError(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final message = data['error'];
      if (message is String && message.isNotEmpty) {
        final code = data['code'];
        return ApiException(
          message,
          statusCode: e.response?.statusCode,
          code: code is String ? code : null,
        );
      }
    }
    return ApiException(
      e.message ?? 'network error',
      statusCode: e.response?.statusCode,
    );
  }
}
