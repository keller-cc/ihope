import 'package:flutter/material.dart';

import '../config/server_config.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../widgets/auth_form.dart';
import '../widgets/app_page_route.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';
import 'server_settings_screen.dart';
import 'verify_email_pending_screen.dart';

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
  final _loginId = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLastLoginId();
  }

  Future<void> _loadLastLoginId() async {
    final saved = await widget.auth.storage.readLastLoginIdentifier();
    if (!mounted || saved == null || saved.isEmpty) return;
    _loginId.text = saved;
  }

  @override
  void dispose() {
    _loginId.dispose();
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
        login: _loginId.text,
        password: _password.text,
      );
      widget.onLoggedIn();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
      if (e.isEmailNotVerified && mounted) {
        final raw = _loginId.text.trim();
        final email = raw.contains('@') ? raw.toLowerCase() : null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('请先验证邮箱'),
            action: email == null
                ? null
                : SnackBarAction(
                    label: '去验证',
                    onPressed: () {
                      Navigator.of(context).push(
                        appPageRoute(
                          builder: (_) => VerifyEmailPendingScreen(
                            auth: widget.auth,
                            email: email,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        );
      }
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
            controller: _loginId,
            decoration: const InputDecoration(
              labelText: '用户名或邮箱',
              hintText: '支持用户名或注册邮箱',
            ),
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.username, AutofillHints.email],
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
                      appPageRoute(
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
                      appPageRoute(
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
                      appPageRoute(
                        builder: (_) => RegisterScreen(auth: widget.auth),
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
