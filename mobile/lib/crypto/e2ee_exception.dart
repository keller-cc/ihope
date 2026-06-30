/// 无法端到端加密时抛出；消息仅展示 [message]，便于 SnackBar 直接显示。
class E2eeException implements Exception {
  E2eeException(this.message);

  final String message;

  @override
  String toString() => message;
}
