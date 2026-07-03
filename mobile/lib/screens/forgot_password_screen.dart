import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../widgets/auth_form.dart';
import '../widgets/app_page_route.dart';
import 'reset_password_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _devToken;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = '请输入邮箱');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _devToken = null;
    });
    try {
      final token = await widget.auth.forgotPassword(email);
      if (!mounted) return;
      setState(() {
        _devToken = token;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('若邮箱已注册，重置链接已发送（开发环境见下方 token）'),
        ),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goResetWithToken() {
    Navigator.of(context).push(
      appPageRoute(
        builder: (_) => ResetPasswordScreen(
          auth: widget.auth,
          initialToken: _devToken ?? '',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('忘记密码')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('输入注册邮箱，我们将发送重置链接。'),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            decoration: const InputDecoration(labelText: '邮箱'),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            FormErrorText(message: _error!),
          ],
          if (_devToken != null && _devToken!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              '开发环境重置 token：',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            SelectableText(_devToken!),
            TextButton(
              onPressed: _goResetWithToken,
              child: const Text('用此 token 去重置密码'),
            ),
          ],
          const SizedBox(height: 24),
          SubmitButton(
            loading: _loading,
            label: '发送重置邮件',
            onPressed: _submit,
          ),
          TextButton(
            onPressed: _loading
                ? null
                : () {
                    Navigator.of(context).push(
                      appPageRoute(
                        builder: (_) => ResetPasswordScreen(auth: widget.auth),
                      ),
                    );
                  },
            child: const Text('已有重置 token？直接重置'),
          ),
        ],
      ),
    );
  }
}
