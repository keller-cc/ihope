import 'package:flutter/material.dart';

class EmojiCategory {
  const EmojiCategory({
    required this.label,
    required this.icon,
    required this.emojis,
  });

  final String label;
  final IconData icon;
  final List<String> emojis;
}

const _rawEmojiCategories = <EmojiCategory>[
  EmojiCategory(
    label: '常用',
    icon: Icons.star_outline,
    emojis: [
      '🙏', '✝️', '😊', '😇', '🥰', '❤️', '🤍', '🕊️', '⭐', '✨',
      '🌟', '👼', '⛪', '📖', '🕯️', '☀️', '🌈', '🤗', '😌', '🥲',
      '💐', '🌷', '🌹', '🙌', '👏', '🤝', '🎵', '🎶', '✅', '🙂',
    ],
  ),
  EmojiCategory(
    label: '信仰',
    icon: Icons.church_outlined,
    emojis: [
      '☦️', '💒', '🐑', '🍞', '🫒', '☮️', '🤲', '🧎', '🧎‍♂️',
      '🧎‍♀️', '🛐', '📿', '🎤', '🎹', '🎻', '🌿', '🎄',
    ],
  ),
  EmojiCategory(
    label: '表情',
    icon: Icons.sentiment_satisfied_alt_outlined,
    emojis: [
      '😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂', '🙃',
      '😉', '😍', '🤩', '😘', '☺️', '😚', '😙',
      '😋', '🤭', '🤫', '🤔', '😔', '😪', '😴',
      '🥺', '😢', '😭', '😥', '😮', '😯', '😲', '😳', '😦', '😧',
      '😨', '😰', '😓', '😩', '😫', '🥱', '😤',
    ],
  ),
  EmojiCategory(
    label: '祝福',
    icon: Icons.volunteer_activism_outlined,
    emojis: [
      '🧡', '💛', '💚', '💙', '💜', '🤎', '💕', '💞',
      '💓', '💗', '💖', '💘', '💝', '💟',
      '🌞', '🌻', '🌸', '🌼', '🎉', '🎊', '🎁', '🍀',
    ],
  ),
];

/// 分类间去重：后序分类不重复前序已出现的表情。
final kEmojiCategories = _dedupeCategories(_rawEmojiCategories);

List<EmojiCategory> _dedupeCategories(List<EmojiCategory> input) {
  final seen = <String>{};
  final out = <EmojiCategory>[];
  for (final cat in input) {
    final unique = <String>[];
    for (final emoji in cat.emojis) {
      if (seen.add(emoji)) unique.add(emoji);
    }
    if (unique.isNotEmpty) {
      out.add(EmojiCategory(label: cat.label, icon: cat.icon, emojis: unique));
    }
  }
  return out;
}

/// 在 [controller] 光标处插入 [text]。
void insertAtCursor(TextEditingController? controller, String text) {
  final c = controller;
  if (c == null) return;
  final sel = c.selection;
  final start = sel.start >= 0 ? sel.start : c.text.length;
  final end = sel.end >= 0 ? sel.end : c.text.length;
  final next = c.text.replaceRange(start, end, text);
  c.value = TextEditingValue(
    text: next,
    selection: TextSelection.collapsed(offset: start + text.length),
  );
}
