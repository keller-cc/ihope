import 'package:flutter/material.dart';

import '../models/conversation.dart';
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
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = await widget.auth.conversations.listUsers();
      final me = widget.auth.currentUser!.id;
      if (!mounted) return;
      setState(() {
        _users = users.where((u) => u.id != me).toList();
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<PublicUser> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _users;
    return _users.where((u) => u.username.toLowerCase().contains(q)).toList();
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

  @override
  Widget build(BuildContext context) {
    final visible = _filtered;
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
                labelText: '搜索成员',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
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
                    : visible.isEmpty
                        ? const Center(child: Text('没有匹配的用户'))
                        : ListView.separated(
                            itemCount: visible.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final u = visible[index];
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
