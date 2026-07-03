/// Token 刷新后会话/E2EE 策略（可单测，避免误清空加密模块）。
bool shouldResetCryptoOnTokenRefresh({
  required String? priorUserId,
  required String newUserId,
}) {
  return priorUserId != null && priorUserId != newUserId;
}
