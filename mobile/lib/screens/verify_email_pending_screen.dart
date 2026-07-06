import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../widgets/auth_form.dart';

/// 注册后等待邮箱验证；也可从登录页「邮箱未验证」进入。
class VerifyEmailPendingScreen extends StatefulWidget {
  const VerifyEmailPendingScreen({
    super.key,
    required this.auth,
    required this.email,
    this.initialDevToken,
  });

  final AuthService auth;
  final String email;
  final String? initialDevToken;

  @override
  State<VerifyEmailPendingScreen> createState() =>
      _VerifyEmailPendingScreenState();
}

class _VerifyEmailPendingScreenState extends State<VerifyEmailPendingScreen> {
  bool _loading = false;
  String? _error;
  String? _devToken;

  @override
  void initState() {
    super.initState();
    _devToken = widget.initialDevToken;
  }

  Future<void> _resend() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await widget.auth.resendVerification(widget.email);
      if (!mounted) return;
      setState(() => _devToken = token);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('若邮箱已注册且未验证，验证邮件已发送')),
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _devVerify() async {
    final token = _devToken?.trim() ?? '';
    if (token.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.auth.verifyEmail(token);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('邮箱已验证，请返回登录')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('验证邮箱')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            '我们已向你的邮箱发送了验证链接。请打开邮件并点击链接完成激活，然后返回 App 登录。',
          ),
          const SizedBox(height: 12),
          Text(
            widget.email,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '没收到？检查垃圾箱，或点击下方重新发送。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            FormErrorText(message: _error!),
          ],
          if (_devToken != null && _devToken!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              '开发环境验证 token：',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            SelectableText(_devToken!),
            TextButton(
              onPressed: _loading ? null : _devVerify,
              child: const Text('用此 token 直接验证（开发）'),
            ),
          ],
          const SizedBox(height: 24),
          SubmitButton(
            loading: _loading,
            label: '重新发送验证邮件',
            onPressed: _resend,
          ),
          TextButton(
            onPressed: _loading ? null : () => Navigator.of(context).pop(),
            child: const Text('返回登录'),
          ),
        ],
      ),
    );
  }
}
