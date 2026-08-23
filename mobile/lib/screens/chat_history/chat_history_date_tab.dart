import 'package:flutter/material.dart';

import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../services/auth_service.dart';
import 'chat_history_loader.dart';
import 'widgets/chat_history_result_tile.dart';

/// 按月份日历查找；有消息的日子点进去在本页展示当天记录（QQ 风格）。
class ChatHistoryDateTab extends StatefulWidget {
  const ChatHistoryDateTab({
    super.key,
    required this.auth,
    required this.conversation,
    required this.messages,
    required this.onPick,
    required this.onEmpty,
    this.loadMessages,
  });

  final AuthService auth;
  final ConversationItem conversation;
  final List<ChatMessage> messages;
  final void Function(String messageId) onPick;
  final VoidCallback onEmpty;
  final Future<List<ChatMessage>> Function()? loadMessages;

  @override
  State<ChatHistoryDateTab> createState() => _ChatHistoryDateTabState();
}

class _ChatHistoryDateTabState extends State<ChatHistoryDateTab> {
  DateTime? _selected;
  List<ChatMessage> _dayMessages = const [];
  bool _showingDay = false;

  Set<DateTime> get _daysWithMessages =>
      ChatHistoryLoader.daysWithMessages(widget.messages);

  List<DateTime> get _months {
    final now = DateTime.now();
    if (widget.messages.isEmpty) {
      return [DateTime(now.year, now.month)];
    }
    var earliest = widget.messages.first.createdAt.toLocal();
    for (final m in widget.messages) {
      final t = m.createdAt.toLocal();
      if (t.isBefore(earliest)) earliest = t;
    }
    final end = DateTime(earliest.year, earliest.month);
    final months = <DateTime>[];
    var cur = DateTime(now.year, now.month);
    while (!cur.isBefore(end)) {
      months.add(cur);
      if (cur.year == end.year && cur.month == end.month) break;
      cur = DateTime(cur.year, cur.month - 1);
    }
    return months;
  }

  Future<void> _onDayTap(DateTime day) async {
    var messages = widget.messages;
    if (messages.isEmpty && widget.loadMessages != null) {
      messages = await widget.loadMessages!();
      if (!mounted) return;
    }
    final onDay = ChatHistoryLoader.filterByDay(messages, day);
    if (onDay.isEmpty) {
      setState(() {
        _selected = day;
        _showingDay = false;
        _dayMessages = const [];
      });
      widget.onEmpty();
      return;
    }
    setState(() {
      _selected = day;
      _showingDay = true;
      _dayMessages = onDay;
    });
  }

  void _backToCalendar() {
    setState(() {
      _showingDay = false;
      _dayMessages = const [];
    });
  }

  String _nameFor(ChatMessage msg) {
    final me = widget.auth.currentUser;
    if (me != null && msg.senderId == me.id) return me.username;
    return widget.auth.groupMemberUsername(widget.conversation, msg.senderId);
  }

  String? _avatarFor(ChatMessage msg) {
    final me = widget.auth.currentUser;
    if (me != null && msg.senderId == me.id) return me.avatarUrl;
    return widget.auth.groupMemberAvatarUrl(widget.conversation, msg.senderId);
  }

  @override
  Widget build(BuildContext context) {
    final body = _showingDay && _selected != null
        ? _buildDayMessages(context, _selected!)
        : _buildCalendar(context);
    return PopScope(
      canPop: !_showingDay,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _showingDay) _backToCalendar();
      },
      child: body,
    );
  }

  Widget _buildDayMessages(BuildContext context, DateTime day) {
    final title = '${day.year}年${day.month}月${day.day}日';
    final isGroup = widget.conversation.type == 'group';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: InkWell(
            onTap: _backToCalendar,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.arrow_back_ios_new, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  Text(
                    '返回日历',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: _dayMessages.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final msg = _dayMessages[index];
              return ChatHistoryResultTile(
                msg: msg,
                name: _nameFor(msg),
                senderTitle: isGroup
                    ? widget.conversation.memberTitle(msg.senderId)
                    : null,
                avatarUrl: _avatarFor(msg),
                onTap: () => widget.onPick(msg.id),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCalendar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final marked = _daysWithMessages;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: _months.length,
      itemBuilder: (context, index) {
        final month = _months[index];
        final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
        final firstWeekday = DateTime(month.year, month.month, 1).weekday % 7;
        final isCurrentMonth =
            month.year == today.year && month.month == today.month;

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Card(
            elevation: 0,
            color: scheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${month.year}年${month.month}月',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: ['日', '一', '二', '三', '四', '五', '六']
                        .map(
                          (w) => Expanded(
                            child: Center(
                              child: Text(
                                w,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 4),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                    ),
                    itemCount: firstWeekday + daysInMonth,
                    itemBuilder: (context, cell) {
                      if (cell < firstWeekday) return const SizedBox.shrink();
                      final day = cell - firstWeekday + 1;
                      final date = DateTime(month.year, month.month, day);
                      if (isCurrentMonth && day > today.day) {
                        return const SizedBox.shrink();
                      }
                      final isToday = date == todayDate;
                      final isSelected = _selected != null &&
                          _selected!.year == date.year &&
                          _selected!.month == date.month &&
                          _selected!.day == date.day;
                      final hasMsg = marked.contains(date);

                      return InkWell(
                        onTap: () => _onDayTap(date),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isSelected
                                ? scheme.primary
                                : isToday
                                    ? scheme.primaryContainer
                                        .withValues(alpha: 0.5)
                                    : null,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '$day',
                                style: TextStyle(
                                  fontWeight: isToday || isSelected || hasMsg
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? scheme.onPrimary
                                      : scheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              if (hasMsg)
                                Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? scheme.onPrimary
                                        : scheme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                )
                              else if (isToday)
                                Text(
                                  '今天',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        fontSize: 9,
                                        color: isSelected
                                            ? scheme.onPrimary
                                            : scheme.primary,
                                      ),
                                )
                              else
                                const SizedBox(height: 5),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
