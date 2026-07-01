/// Megolm 风格群密钥定期轮换策略。
class MegolmRotationPolicy {
  MegolmRotationPolicy._();

  /// 当前 epoch 下累计群消息达到此数量后触发轮换。
  static const int maxMessagesPerEpoch = 100;

  /// 距上次轮换超过此时长后触发轮换。
  static const Duration maxEpochAge = Duration(hours: 24);
}
