import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../widgets/auth_form.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({
    super.key,
    required this.auth,
    this.initialToken = '',
  });

  final AuthService auth;
  final String initialToken;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  late final TextEditingController _token;
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _token = TextEditingController(text: widget.initialToken);
  }

  @override
  void dispose() {
    _token.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? _validate() {
    if (_token.text.trim().isEmpty) return '请输入重置 token';
    if (_password.text.length < 8) return '密码至少 8 位';
    if (_confirm.text.isEmpty) return '请再次输入密码';
    if (_password.text != _confirm.text) return '两次输入的密码不一致';
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
      await widget.auth.resetPassword(
        token: _token.text,
        password: _password.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('密码已重置，请登录')),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('重置密码')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            controller: _token,
            decoration: const InputDecoration(labelText: '重置 token'),
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
            label: '重置并登录',
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}
