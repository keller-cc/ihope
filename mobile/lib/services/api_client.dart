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
    if (accessToken != null && accessToken.isNotEmpty) {
      setAccessToken(accessToken);
    }
  }

  late final Dio _dio;

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
