import 'package:flutter/material.dart';

import 'unicode_emoji_data.dart';

/// QQ 风格底部分类栏 + 基督教主题 Unicode 表情（纯 Dart）。
class StandardEmojiPanel extends StatefulWidget {
  const StandardEmojiPanel({
    super.key,
    this.controller,
    this.height = 280,
  });

  final TextEditingController? controller;
  final double height;

  @override
  State<StandardEmojiPanel> createState() => _StandardEmojiPanelState();
}

class _StandardEmojiPanelState extends State<StandardEmojiPanel> {
  int _categoryIndex = 0;

  void _insertEmoji(String emoji) => insertAtCursor(widget.controller, emoji);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surface = scheme.surfaceContainerLow;
    final emojis = kEmojiCategories[_categoryIndex].emojis;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface,
        border: Border(
          top: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
      ),
      child: SizedBox(
        height: widget.height,
        child: Column(
          children: [
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 8,
                  mainAxisSpacing: 2,
                  crossAxisSpacing: 2,
                ),
                itemCount: emojis.length,
                itemBuilder: (context, index) {
                  final emoji = emojis[index];
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _insertEmoji(emoji),
                      child: Center(
                        child: Text(emoji, style: const TextStyle(fontSize: 26)),
                      ),
                    ),
                  );
                },
              ),
            ),
            Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.3),
            ),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: kEmojiCategories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 4),
                itemBuilder: (context, index) {
                  final cat = kEmojiCategories[index];
                  final selected = index == _categoryIndex;
                  return InkWell(
                    onTap: () => setState(() => _categoryIndex = index),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Icon(
                        cat.icon,
                        size: 24,
                        color: selected
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
