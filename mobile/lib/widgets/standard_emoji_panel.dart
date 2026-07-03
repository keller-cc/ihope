import 'package:flutter/material.dart';

import '../services/recent_emoji_store.dart';
import 'unicode_emoji_data.dart';

/// QQ 风格底部分类栏 + 基督教主题 Unicode 表情（纯 Dart）。
class StandardEmojiPanel extends StatefulWidget {
  const StandardEmojiPanel({
    super.key,
    this.controller,
    this.height = 280,
    this.recentEmojiStore,
  });

  final TextEditingController? controller;
  final double height;
  final RecentEmojiStore? recentEmojiStore;

  @override
  State<StandardEmojiPanel> createState() => _StandardEmojiPanelState();
}

class _StandardEmojiPanelState extends State<StandardEmojiPanel> {
  static const _recentTabIndex = 0;

  int _categoryIndex = _recentTabIndex;
  List<String> _recentEmojis = const [];
  late final RecentEmojiStore _recentStore =
      widget.recentEmojiStore ?? RecentEmojiStore();

  @override
  void initState() {
    super.initState();
    _loadRecentEmojis();
  }

  Future<void> _loadRecentEmojis() async {
    final emojis = await _recentStore.read();
    if (!mounted) return;
    setState(() => _recentEmojis = emojis);
  }

  Future<void> _insertEmoji(String emoji) async {
    insertAtCursor(widget.controller, emoji);
    final next = await _recentStore.record(emoji);
    if (!mounted) return;
    setState(() => _recentEmojis = next);
  }

  bool get _isRecentTab => _categoryIndex == _recentTabIndex;

  List<String> get _currentEmojis {
    if (_isRecentTab) return _recentEmojis;
    return kEmojiCategories[_categoryIndex - 1].emojis;
  }

  int get _tabCount => kEmojiCategories.length + 1;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surface = scheme.surfaceContainerLow;
    final emojis = _currentEmojis;

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
              child: _isRecentTab && emojis.isEmpty
                  ? Center(
                      child: Text(
                        '暂无最近使用的表情',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 14,
                        ),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 6,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
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
                              child: Text(
                                emoji,
                                style: const TextStyle(fontSize: 26),
                              ),
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
                itemCount: _tabCount,
                separatorBuilder: (_, _) => const SizedBox(width: 4),
                itemBuilder: (context, index) {
                  final selected = index == _categoryIndex;
                  final IconData icon;
                  if (index == _recentTabIndex) {
                    icon = Icons.history;
                  } else {
                    icon = kEmojiCategories[index - 1].icon;
                  }
                  return InkWell(
                    onTap: () => setState(() => _categoryIndex = index),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Icon(
                        icon,
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
