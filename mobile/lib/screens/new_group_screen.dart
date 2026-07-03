import 'dart:async';

import 'package:flutter/material.dart';

import '../models/user.dart';
import '../services/auth_service.dart';
import '../widgets/user_avatar.dart';

class NewGroupScreen extends StatefulWidget {
  const NewGroupScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends State<NewGroupScreen> {
  final _name = TextEditingController();
  final _search = TextEditingController();
  List<PublicUser> _users = [];
  final Set<String> _selected = {};
  bool _loading = true;
  bool _submitting = false;
  bool _listTruncated = false;
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
    _name.dispose();
    _search.dispose();
    super.dispose();
  }

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

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入群名称')),
      );
      return;
    }
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择一位成员')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final conv = await widget.auth.createGroupChat(
        name: name,
        memberIds: _selected.toList(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(conv);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _emptyMessage() {
    final q = _search.text.trim();
    if (q.isNotEmpty) {
      return '没有匹配「$q」的用户，请用用户名或邮箱搜索。';
    }
    if (_listTruncated) {
      return '用户较多，仅显示前 100 位。请在搜索框输入用户名。';
    }
    return '没有可添加的用户';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('创建群聊'),
        actions: [
          TextButton(
            onPressed: _submitting ? null : _create,
            child: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('创建'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '群名称',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                labelText: '搜索用户名或邮箱',
                hintText: '例如 qqq',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          if (_selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('已选 ${_selected.length} 人'),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _users.isEmpty
                        ? Center(child: Text(_emptyMessage()))
                        : ListView.separated(
                            itemCount: _users.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final u = _users[index];
                              final checked = _selected.contains(u.id);
                              return CheckboxListTile(
                                secondary: UserAvatar(
                                  name: u.username,
                                  imageUrl: u.avatarUrl,
                                ),
                                title: Text(u.username),
                                value: checked,
                                onChanged: (v) {
                                  setState(() {
                                    if (v == true) {
                                      _selected.add(u.id);
                                    } else {
                                      _selected.remove(u.id);
                                    }
                                  });
                                },
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
