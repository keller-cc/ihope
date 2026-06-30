import 'package:flutter/material.dart';

import '../models/conversation.dart';
import '../models/user.dart';
import '../services/auth_service.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    final visible = _filtered;
    return Scaffold(
      appBar: AppBar(title: const Text('发起单聊')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                labelText: '搜索用户名',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
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
                              return ListTile(
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
