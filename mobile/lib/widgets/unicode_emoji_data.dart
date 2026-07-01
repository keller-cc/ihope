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

/// 基督教语境 Unicode 表情，简单分类（参考 QQ 底栏结构）。
const kEmojiCategories = <EmojiCategory>[
  EmojiCategory(
    label: '常用',
    icon: Icons.schedule_outlined,
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
      '✝️', '☦️', '⛪', '💒', '📖', '🙏', '🕊️', '🕯️', '👼', '⭐',
      '🌟', '✨', '🎄', '🐑', '🍞', '🫒', '☮️', '🤲', '🧎', '🧎‍♂️',
      '🧎‍♀️', '🛐', '📿', '🎵', '🎶', '🎤', '🎹', '🎻', '🕊️', '🌿',
    ],
  ),
  EmojiCategory(
    label: '表情',
    icon: Icons.emoji_emotions_outlined,
    emojis: [
      '😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂', '🙂', '🙃',
      '😉', '😊', '😇', '🥰', '😍', '🤩', '😘', '☺️', '😚', '😙',
      '🥲', '😋', '🤗', '🤭', '🤫', '🤔', '😌', '😔', '😪', '😴',
      '🥺', '😢', '😭', '😥', '😮', '😯', '😲', '😳', '😦', '😧',
      '😨', '😰', '😓', '😩', '😫', '🥱', '😤', '🙏', '🤍', '😊',
    ],
  ),
  EmojiCategory(
    label: '祝福',
    icon: Icons.favorite_border,
    emojis: [
      '❤️', '🧡', '💛', '💚', '💙', '💜', '🤍', '🤎', '💕', '💞',
      '💓', '💗', '💖', '💘', '💝', '💟', '✨', '🌟', '⭐', '🌈',
      '☀️', '🌞', '🌻', '🌷', '🌹', '💐', '🌸', '🌼', '🎉', '🎊',
      '🙌', '👏', '🤝', '🤲', '🎁', '🕊️', '🙏', '👼', '🍀', '🌿',
    ],
  ),
];

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
