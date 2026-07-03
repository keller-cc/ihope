import 'package:flutter/material.dart';

/// 在摘要中高亮关键字，过长时保留关键字附近片段。
class ChatHistoryHighlight {
  ChatHistoryHighlight._();

  static const defaultMaxLength = 72;

  static String snippetAround(String text, String query, {int maxLength = defaultMaxLength}) {
    final raw = text.trim();
    if (raw.isEmpty) return '';
    final q = query.trim();
    if (q.isEmpty || raw.length <= maxLength) return raw;

    final lower = raw.toLowerCase();
    final idx = lower.indexOf(q.toLowerCase());
    if (idx < 0) {
      return raw.length <= maxLength ? raw : '${raw.substring(0, maxLength)}…';
    }

    final half = (maxLength - q.length) ~/ 2;
    var start = idx - half;
    if (start < 0) start = 0;
    var end = start + maxLength;
    if (end > raw.length) {
      end = raw.length;
      start = (end - maxLength).clamp(0, raw.length);
    }
    final slice = raw.substring(start, end);
    final prefix = start > 0 ? '…' : '';
    final suffix = end < raw.length ? '…' : '';
    return '$prefix$slice$suffix';
  }

  static Widget buildText(
    BuildContext context,
    String text,
    String query, {
    int maxLines = 2,
    TextStyle? style,
  }) {
    final snippet = snippetAround(text, query);
    final q = query.trim();
    if (q.isEmpty) {
      return Text(snippet, maxLines: maxLines, overflow: TextOverflow.ellipsis, style: style);
    }

    final lower = snippet.toLowerCase();
    final qLower = q.toLowerCase();
    final idx = lower.indexOf(qLower);
    if (idx < 0) {
      return Text(snippet, maxLines: maxLines, overflow: TextOverflow.ellipsis, style: style);
    }

    final scheme = Theme.of(context).colorScheme;
    final highlightStyle = (style ?? Theme.of(context).textTheme.bodyMedium)?.copyWith(
      color: scheme.primary,
      fontWeight: FontWeight.w600,
      backgroundColor: scheme.primaryContainer.withValues(alpha: 0.45),
    );

    return Text.rich(
      TextSpan(
        style: style,
        children: [
          if (idx > 0) TextSpan(text: snippet.substring(0, idx)),
          TextSpan(text: snippet.substring(idx, idx + q.length), style: highlightStyle),
          if (idx + q.length < snippet.length)
            TextSpan(text: snippet.substring(idx + q.length)),
        ],
      ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}
