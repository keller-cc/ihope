import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../widgets/auth_form.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? _validate() {
    if (_current.text.isEmpty) return '请输入当前密码';
    if (_password.text.length < 8) return '新密码至少 8 位';
    if (_confirm.text.isEmpty) return '请再次输入新密码';
    if (_password.text != _confirm.text) return '两次输入的新密码不一致';
    return null;
  }

  Future<void> _submit() async {
    final validationError = _validate();
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.auth.changePassword(
        currentPassword: _current.text,
        newPassword: _password.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('密码已修改，请重新登录')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('修改密码')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            controller: _current,
            decoration: const InputDecoration(labelText: '当前密码'),
            obscureText: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            decoration: const InputDecoration(labelText: '新密码（至少 8 位）'),
            obscureText: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirm,
            decoration: const InputDecoration(labelText: '确认新密码'),
            obscureText: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            FormErrorText(message: _error!),
          ],
          const SizedBox(height: 24),
          SubmitButton(
            loading: _loading,
            label: '确认修改',
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}
