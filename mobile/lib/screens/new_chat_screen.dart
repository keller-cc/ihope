import 'dart:async';

import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/auth_service.dart';
import '../widgets/user_avatar.dart';

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final _search = TextEditingController();
  List<PublicUser> _users = [];
  bool _loading = true;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  bool _listTruncated = false;

  Future<void> _load(String query) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final trimmed = query.trim();
      final users = await widget.auth.conversations.listUsers(
        query: trimmed.isEmpty ? null : trimmed,
        limit: 100,
      );
      final me = widget.auth.currentUser!.id;
      if (!mounted) return;
      setState(() {
        _users = users.where((u) => u.id != me).toList();
        _listTruncated = trimmed.isEmpty && users.length >= 100;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _load(value);
    });
  }

  Future<void> _startChat(PublicUser peer) async {
    try {
      final conv = await widget.auth.conversations.createPrivateChat(peer.id);
      if (!mounted) return;
      Navigator.of(context).pop(conv);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  String _emptyMessage() {
    final q = _search.text.trim();
    if (q.isNotEmpty) {
      return '没有匹配「$q」的用户。\n'
          '请用用户名或邮箱搜索；列表不含当前登录账号。';
    }
    if (_listTruncated) {
      return '用户较多，仅显示前 100 位（按用户名排序）。\n'
          '请在上方搜索框输入对方用户名，例如 qqq。';
    }
    return '还没有其他用户。\n'
        '请确认对方已在同一服务器注册（真机与模拟器需连同一后端）。';
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.auth.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('发起单聊')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                labelText: '搜索用户名或邮箱',
                hintText: '例如 tom 或 tom@example.com',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          if (me != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                _listTruncated && _search.text.trim().isEmpty
                    ? '当前账号：${me.username}（不会出现在列表中）· 用户较多，请搜索查找'
                    : '当前账号：${me.username}（不会出现在列表中）',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_error!, textAlign: TextAlign.center),
                        ),
                      )
                    : _users.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _emptyMessage(),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: _users.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final u = _users[index];
                              return ListTile(
                                leading: UserAvatar(
                                  name: u.username,
                                  imageUrl: u.avatarUrl,
                                ),
                                title: Text(u.username),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => _startChat(u),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
