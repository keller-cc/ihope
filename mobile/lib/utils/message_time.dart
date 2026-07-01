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

  /// 会话列表右侧（QQ）：今天 HH:mm，昨天 HH:mm，近 7 天 星期X，同年 M/d。
  static String formatList(DateTime time) {
    final t = time.toLocal();
    final now = DateTime.now();
    final hm = _hm(t);
    final today = _dateOnly(now);
    final msgDay = _dateOnly(t);
    final dayDiff = today.difference(msgDay).inDays;

    if (msgDay == today) return hm;
    if (msgDay == today.subtract(const Duration(days: 1))) return '昨天 $hm';
    if (dayDiff >= 2 && dayDiff < 7) return _weekdayLabel(t);
    if (t.year == now.year) return '${t.month}/${t.day}';
    return '${t.year}/${t.month}/${t.day}';
  }

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

  /// 群公告卡片左下角：yyyy年M月d日 HH:mm。
  static String formatAnnouncementCard(DateTime time) {
    final t = time.toLocal();
    return '${t.year}年${t.month}月${t.day}日 ${_hm(t)}';
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _hm(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static String _weekdayLabel(DateTime t) {
    const labels = [
      '星期一',
      '星期二',
      '星期三',
      '星期四',
      '星期五',
      '星期六',
      '星期日',
    ];
    return labels[t.weekday - 1];
  }
}
