/// 聊天媒体修复/下载回调（文件接收进度、缺图补拉等）。
typedef MediaRetryCallback = Future<void> Function(
  String messageId, {
  void Function(double progress)? onProgress,
});

/// 单条消息媒体下载（调用方已持有 messageId）。
typedef MediaDownloadCallback = Future<void> Function({
  void Function(double progress)? onProgress,
});
