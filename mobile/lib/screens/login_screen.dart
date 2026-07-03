import 'package:flutter/material.dart';

import '../config/server_config.dart';
import '../services/auth_service.dart';
import '../widgets/auth_form.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';
import 'server_settings_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.auth,
    required this.onLoggedIn,
  });

  final AuthService auth;
  final VoidCallback onLoggedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.auth.login(
        email: _email.text,
        password: _password.text,
      );
      widget.onLoggedIn();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('登录 IHope')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            controller: _email,
            decoration: const InputDecoration(labelText: '邮箱'),
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            decoration: const InputDecoration(labelText: '密码'),
            obscureText: true,
            autofillHints: const [AutofillHints.password],
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
            label: '登录',
            onPressed: _submit,
          ),
          TextButton(
            onPressed: _loading
                ? null
                : () async {
                    final result = await Navigator.of(context).push<Object?>(
                      MaterialPageRoute(
                        builder: (_) => ServerSettingsScreen(auth: widget.auth),
                      ),
                    );
                    if (result == 'logout' && mounted) {
                      setState(() => _error = null);
                    }
                  },
            child: Text('服务器：${ServerConfig.apiBase}'),
          ),
          TextButton(
            onPressed: _loading
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ForgotPasswordScreen(auth: widget.auth),
                      ),
                    );
                  },
            child: const Text('忘记密码？'),
          ),
          TextButton(
            onPressed: _loading
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => RegisterScreen(
                          auth: widget.auth,
                          onRegistered: widget.onLoggedIn,
                        ),
                      ),
                    );
                  },
            child: const Text('没有账号？注册'),
          ),
        ],
      ),
    );
  }
}
