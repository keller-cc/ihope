import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../widgets/auth_form.dart';
import '../widgets/app_page_route.dart';
import 'verify_email_pending_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({
    super.key,
    required this.auth,
  });

  final AuthService auth;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _email = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _username.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  String? _validateForm() {
    final email = _email.text.trim();
    final username = _username.text.trim();
    final password = _password.text;
    final confirm = _confirmPassword.text;

    if (email.isEmpty) return '请输入邮箱';
    if (username.isEmpty) return '请输入用户名';
    if (password.length < 8) return '密码至少 8 位';
    if (confirm.isEmpty) return '请再次输入密码';
    if (password != confirm) return '两次输入的密码不一致';
    return null;
  }

  Future<void> _submit() async {
    final validationError = _validateForm();
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.auth.register(
        email: _email.text,
        username: _username.text,
        password: _password.text,
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        appPageRoute(
          builder: (_) => VerifyEmailPendingScreen(
            auth: widget.auth,
            email: result.email,
            initialDevToken: result.devVerifyToken,
          ),
        ),
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('注册')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            controller: _email,
            decoration: const InputDecoration(labelText: '邮箱'),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _username,
            decoration: const InputDecoration(labelText: '用户名'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            decoration: const InputDecoration(labelText: '密码（至少 8 位）'),
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmPassword,
            decoration: const InputDecoration(labelText: '确认密码'),
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
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
            label: '注册',
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}
