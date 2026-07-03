import 'package:flutter/material.dart';

import '../../models/message.dart';
import 'chat_history_loader.dart';

/// 按月份日历查找，选中日期跳转到该日之后最近一条消息。
class ChatHistoryDateTab extends StatefulWidget {
  const ChatHistoryDateTab({
    super.key,
    required this.messages,
    required this.onPick,
    required this.onEmpty,
    this.loadMessages,
  });

  final List<ChatMessage> messages;
  final void Function(String messageId) onPick;
  final VoidCallback onEmpty;
  final Future<List<ChatMessage>> Function()? loadMessages;

  @override
  State<ChatHistoryDateTab> createState() => _ChatHistoryDateTabState();
}

class _ChatHistoryDateTabState extends State<ChatHistoryDateTab> {
  DateTime? _selected;

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
    setState(() => _selected = day);
    var messages = widget.messages;
    if (messages.isEmpty && widget.loadMessages != null) {
      messages = await widget.loadMessages!();
      if (!mounted) return;
    }
    final hit = ChatHistoryLoader.nearestOnOrAfter(messages, day);
    if (hit == null) {
      widget.onEmpty();
      return;
    }
    widget.onPick(hit.id);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

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
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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

                      return InkWell(
                        onTap: () => _onDayTap(date),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isSelected
                                ? scheme.primary
                                : isToday
                                    ? scheme.primaryContainer.withValues(alpha: 0.5)
                                    : null,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '$day',
                                style: TextStyle(
                                  fontWeight: isToday || isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? scheme.onPrimary
                                      : scheme.onSurface,
                                ),
                              ),
                              if (isToday)
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
                                ),
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
