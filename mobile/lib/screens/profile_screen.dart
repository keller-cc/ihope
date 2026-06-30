import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/auth_service.dart';
import '../widgets/auth_form.dart';
import 'change_password_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.auth,
    required this.onProfileUpdated,
  });

  final AuthService auth;
  final VoidCallback onProfileUpdated;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _username;
  bool _loading = false;
  bool _uploadingAvatar = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _username = TextEditingController(text: widget.auth.currentUser!.username);
  }

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<void> _saveUsername() async {
    final username = _username.text.trim();
    if (username.isEmpty) {
      setState(() => _error = '请输入用户名');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.auth.updateUsername(username);
      if (!mounted) return;
      widget.onProfileUpdated();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('用户名已更新')),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (file == null) return;

    setState(() {
      _uploadingAvatar = true;
      _error = null;
    });
    try {
      final bytes = await file.readAsBytes();
      await widget.auth.uploadAvatar(
        bytes,
        filename: file.name.isNotEmpty ? file.name : 'avatar.jpg',
      );
      if (!mounted) return;
      setState(() {});
      widget.onProfileUpdated();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('头像已更新')),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _openChangePassword() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ChangePasswordScreen(auth: widget.auth),
      ),
    );
    if (changed == true && mounted) {
      Navigator.of(context).pop('logout');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.auth.currentUser!;
    return Scaffold(
      appBar: AppBar(title: const Text('个人资料')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 48,
                  backgroundImage: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                      ? NetworkImage(user.avatarUrl!)
                      : null,
                  child: user.avatarUrl == null || user.avatarUrl!.isEmpty
                      ? Text(
                          user.username.isNotEmpty
                              ? user.username[0].toUpperCase()
                              : '?',
                          style: const TextStyle(fontSize: 32),
                        )
                      : null,
                ),
                if (_uploadingAvatar)
                  const Positioned.fill(
                    child: CircularProgressIndicator(),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _uploadingAvatar ? null : _pickAvatar,
              child: const Text('更换头像'),
            ),
          ),
          const SizedBox(height: 16),
          InputDecorator(
            decoration: const InputDecoration(labelText: '邮箱'),
            child: Text(user.email),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _username,
            decoration: const InputDecoration(labelText: '用户名'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            FormErrorText(message: _error!),
          ],
          const SizedBox(height: 24),
          SubmitButton(
            loading: _loading,
            label: '保存用户名',
            onPressed: _saveUsername,
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _loading ? null : _openChangePassword,
            child: const Text('修改密码'),
          ),
        ],
      ),
    );
  }
}
