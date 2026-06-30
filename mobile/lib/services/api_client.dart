import 'package:dio/dio.dart';

import '../config/env.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({String? accessToken}) {
    _dio = Dio(
      BaseOptions(
        baseUrl: Env.apiBase,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Content-Type': 'application/json'},
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
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
  }) async {
    try {
      final res =
          await _dio.post<Map<String, dynamic>>(path, data: body ?? {});
      return res.data ?? {};
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  /// 不带 Authorization 的 POST（用于 refresh）。
  Future<Map<String, dynamic>> postJsonPublic(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        path,
        data: body ?? {},
        options: Options(headers: {'Authorization': null}),
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
  }) async {
    try {
      final form = FormData.fromMap({
        field: MultipartFile.fromBytes(bytes, filename: filename),
      });
      final res = await _dio.post<Map<String, dynamic>>(
        path,
        data: form,
        options: Options(contentType: 'multipart/form-data'),
      );
      return res.data ?? {};
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  ApiException _mapError(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final message = data['error'];
      if (message is String && message.isNotEmpty) {
        return ApiException(message, statusCode: e.response?.statusCode);
      }
    }
    return ApiException(
      e.message ?? 'network error',
      statusCode: e.response?.statusCode,
    );
  }
}
