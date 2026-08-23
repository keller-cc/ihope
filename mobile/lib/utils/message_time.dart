import 'package:intl/intl.dart';

/// 聊天消息时间展示（微信/QQ 风格）。
class MessageTimeFormat {
  MessageTimeFormat._();

  /// 相邻消息间隔超过 [dividerGapMinutes] 分钟则插入居中时间条。
  static const dividerGapMinutes = 5;

  static final _md = DateFormat('M月d日');
  static final _ymd = DateFormat('yyyy年M月d日');
  static final _mdSlash = DateFormat('M/d');
  static final _ymdSlash = DateFormat('yyyy/M/d');
  static final _weekday = DateFormat('EEEE', 'zh_CN');

  /// 固定 24 小时制，不跟随系统 12 小时 / 上午下午。
  static String formatHm(DateTime time) {
    final t = time.toLocal();
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static bool shouldShowDivider(DateTime? previous, DateTime current) {
    if (previous == null) return true;
    return current.difference(previous).inMinutes >= dividerGapMinutes;
  }

  /// 居中时间条：今天 HH:mm，昨天 HH:mm，同年 M月d日 HH:mm，否则 yyyy年M月d日 HH:mm。
  static String formatDivider(DateTime time) {
    final t = time.toLocal();
    final now = DateTime.now();
    final today = _dateOnly(now);
    final msgDay = _dateOnly(t);

    if (msgDay == today) return formatHm(t);
    if (msgDay == today.subtract(const Duration(days: 1))) {
      return '昨天 ${formatHm(t)}';
    }
    if (t.year == now.year) return '${_md.format(t)} ${formatHm(t)}';
    return '${_ymd.format(t)} ${formatHm(t)}';
  }

  /// 会话列表右侧（QQ）：今天 HH:mm，昨天 HH:mm，近 7 天 星期X，同年 M/d。
  static String formatList(DateTime time) {
    final t = time.toLocal();
    final now = DateTime.now();
    final today = _dateOnly(now);
    final msgDay = _dateOnly(t);
    final dayDiff = today.difference(msgDay).inDays;

    if (msgDay == today) return formatHm(t);
    if (msgDay == today.subtract(const Duration(days: 1))) {
      return '昨天 ${formatHm(t)}';
    }
    if (dayDiff >= 2 && dayDiff < 7) return _weekday.format(t);
    if (t.year == now.year) return _mdSlash.format(t);
    return _ymdSlash.format(t);
  }

  static String formatBubble(DateTime time) {
    final t = time.toLocal();
    final now = DateTime.now();
    final today = _dateOnly(now);
    final msgDay = _dateOnly(t);

    if (msgDay == today) return formatHm(t);
    if (t.year == now.year) return '${_mdSlash.format(t)} ${formatHm(t)}';
    return '${_ymdSlash.format(t)} ${formatHm(t)}';
  }

  /// 群公告卡片左下角：yyyy年M月d日 HH:mm。
  static String formatAnnouncementCard(DateTime time) {
    final t = time.toLocal();
    return '${_ymd.format(t)} ${formatHm(t)}';
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}
