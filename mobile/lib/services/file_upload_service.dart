import 'api_client.dart';
import '../utils/cloud_drive_launcher.dart';

/// 加密 blob 上传与下载（服务端仅存密文；整包传输，非分片续传）。
class FileUploadService {
  FileUploadService(this._api);

  final ApiClient _api;

  Future<String> uploadEncrypted({
    required String conversationId,
    required List<int> encryptedBytes,
  }) async {
    final timeout = transferTimeoutForBytes(encryptedBytes.length);
    try {
      final data = await _api.postMultipart(
        '/api/upload',
        field: 'file',
        filename: 'blob.bin',
        bytes: encryptedBytes,
        fields: {'conversation_id': conversationId},
        receiveTimeout: timeout,
        sendTimeout: timeout,
      );
      final id = data['file_id'];
      if (id is! String || id.isEmpty) {
        throw StateError('upload missing file_id');
      }
      return id;
    } catch (e) {
      throw StateError(friendlyTransferError(e));
    }
  }

  Future<List<int>> downloadEncrypted(
    String fileId, {
    int expectedBytes = 0,
  }) async {
    final timeout = expectedBytes > 0
        ? transferTimeoutForBytes(expectedBytes)
        : const Duration(seconds: 600);
    try {
      return await _api.getBytes(
        '/api/files/$fileId',
        receiveTimeout: timeout,
      );
    } catch (e) {
      throw StateError(friendlyTransferError(e));
    }
  }
}
