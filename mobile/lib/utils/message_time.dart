/// 聊天消息时间展示（微信/QQ 风格）。
class MessageTimeFormat {
  MessageTimeFormat._();

  /// 相邻消息间隔超过 [dividerGapMinutes] 分钟则插入居中时间条。
  static const dividerGapMinutes = 5;

  static bool shouldShowDivider(DateTime? previous, DateTime current) {
    if (previous == null) return true;
    return current.difference(previous).inMinutes >= dividerGapMinutes;
  }

  /// 居中时间条：今天 HH:mm，昨天 HH:mm，同年 M月d日 HH:mm，否则 yyyy年M月d日 HH:mm。
  static String formatDivider(DateTime time) {
    final t = time.toLocal();
    final now = DateTime.now();
    final hm = _hm(t);
    final today = _dateOnly(now);
    final msgDay = _dateOnly(t);

    if (msgDay == today) return hm;
    if (msgDay == today.subtract(const Duration(days: 1))) {
      return '昨天 $hm';
    }
    if (t.year == now.year) {
      return '${t.month}月${t.day}日 $hm';
    }
    return '${t.year}年${t.month}月${t.day}日 $hm';
  }

  /// 气泡旁小字时间（当天仅 HH:mm，否则简短日期）。
  static String formatBubble(DateTime time) {
    final t = time.toLocal();
    final now = DateTime.now();
    final hm = _hm(t);
    final today = _dateOnly(now);
    final msgDay = _dateOnly(t);

    if (msgDay == today) return hm;
    if (t.year == now.year) {
      return '${t.month}/${t.day} $hm';
    }
    return '${t.year}/${t.month}/${t.day} $hm';
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _hm(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
