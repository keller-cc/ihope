import 'package:flutter/material.dart';

import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../services/auth_service.dart';
import '../../widgets/member_title_badge.dart';
import '../../widgets/user_avatar.dart';
import 'chat_history_loader.dart';
import 'chat_history_member_messages_screen.dart';

class _MemberSection {
  _MemberSection({required this.label, required this.members});

  final String label;
  final List<ConversationMember> members;
}

/// 群成员 Tab：群主置顶 + 字母分组 + 右侧 A-Z 索引。
class ChatHistoryMembersTab extends StatefulWidget {
  const ChatHistoryMembersTab({
    super.key,
    required this.auth,
    required this.conversation,
    required this.messages,
    required this.onJump,
  });

  final AuthService auth;
  final ConversationItem conversation;
  final List<ChatMessage> messages;
  final void Function(String? messageId) onJump;

  @override
  State<ChatHistoryMembersTab> createState() => _ChatHistoryMembersTabState();
}

class _ChatHistoryMembersTabState extends State<ChatHistoryMembersTab> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _sectionKeys = <String, GlobalKey>{};

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _sectionLabel(String username) {
    if (username.isEmpty) return '#';
    final c = username[0].toUpperCase();
    final code = c.codeUnitAt(0);
    if (code >= 65 && code <= 90) return c;
    return '#';
  }

  List<_MemberSection> get _sections {
    final q = _search.text.trim().toLowerCase();
    var members = widget.conversation.members.toList();
    if (q.isNotEmpty) {
      members = members
          .where((m) => m.username.toLowerCase().contains(q))
          .toList();
    }

    final ownerId = widget.conversation.ownerId;
    final owner = ownerId == null
        ? <ConversationMember>[]
        : members.where((m) => m.userId == ownerId).toList();
    final rest = members.where((m) => m.userId != ownerId).toList()
      ..sort((a, b) => a.username.compareTo(b.username));

    final map = <String, List<ConversationMember>>{};
    for (final m in rest) {
      final key = _sectionLabel(m.username);
      map.putIfAbsent(key, () => []).add(m);
    }

    final keys = map.keys.toList()..sort((a, b) {
      if (a == '#') return 1;
      if (b == '#') return -1;
      return a.compareTo(b);
    });

    final sections = <_MemberSection>[];
    if (owner.isNotEmpty) {
      sections.add(_MemberSection(label: '群主', members: owner));
    }
    for (final k in keys) {
      sections.add(_MemberSection(label: k, members: map[k]!));
    }
    return sections;
  }

  List<String> get _indexLetters {
    final letters = <String>[];
    for (final s in _sections) {
      if (s.label == '群主') continue;
      letters.add(s.label);
    }
    return letters;
  }

  void _scrollToSection(String label) {
    final key = _sectionKeys[label];
    final ctx = key?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _openMember(ConversationMember member) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ChatHistoryMemberMessagesScreen(
          auth: widget.auth,
          conversation: widget.conversation,
          member: member,
          messages: ChatHistoryLoader.filterBySender(
            widget.messages,
            member.userId,
          ),
          onJump: widget.onJump,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sections = _sections;
    _sectionKeys.clear();
    for (final s in sections) {
      if (s.label != '群主') _sectionKeys.putIfAbsent(s.label, GlobalKey.new);
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '搜索群成员',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: sections.length,
                itemBuilder: (context, index) {
                  final section = sections[index];
                  return Column(
                    key: section.label == '群主'
                        ? null
                        : _sectionKeys[section.label],
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          section.label == '群主'
                              ? '群主（${section.members.length}人）'
                              : '${section.label}（${section.members.length}人）',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ),
                      ...section.members.map((m) {
                        final title =
                            widget.conversation.memberTitle(m.userId);
                        return ListTile(
                          leading: UserAvatar(
                            name: m.username,
                            imageUrl: m.avatarUrl,
                            radius: 22,
                          ),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  m.username,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (title != null) ...[
                                const SizedBox(width: 6),
                                MemberTitleBadge(title: title),
                              ],
                            ],
                          ),
                          onTap: () => _openMember(m),
                        );
                      }),
                    ],
                  );
                },
              ),
              Positioned(
                right: 4,
                top: 0,
                bottom: 0,
                child: _IndexRail(
                  letters: _indexLetters,
                  onTap: _scrollToSection,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _IndexRail extends StatelessWidget {
  const _IndexRail({required this.letters, required this.onTap});

  final List<String> letters;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: letters
              .map(
                (l) => GestureDetector(
                  onTap: () => onTap(l),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
                    child: Text(
                      l,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}
