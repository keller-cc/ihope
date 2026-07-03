import 'dart:async';

import 'package:flutter/material.dart';

import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'screens/conversations_screen.dart';
import 'screens/login_screen.dart';

class IHopeApp extends StatefulWidget {
  const IHopeApp({
    super.key,
    required this.auth,
    required this.notification,
  });

  final AuthService auth;
  final NotificationService notification;

  @override
  State<IHopeApp> createState() => _IHopeAppState();
}

class _IHopeAppState extends State<IHopeApp> with WidgetsBindingObserver {
  bool? _loggedIn;
  final ValueNotifier<String?> _pendingPushConversation =
      ValueNotifier<String?>(null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_bootstrap());
    unawaited(
      widget.notification.initialize(
        auth: widget.auth,
        onOpenConversation: _onPushOpenConversation,
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pendingPushConversation.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.notification.onLifecycleChanged(state);
    if (state == AppLifecycleState.resumed && _loggedIn == true) {
      unawaited(widget.auth.ensureRealtimeConnected());
    }
  }

  Future<void> _bootstrap() async {
    final local = await widget.auth.restoreLocalSession();
    if (!mounted) return;
    if (!local) {
      setState(() => _loggedIn = false);
      return;
    }
    setState(() => _loggedIn = true);
    unawaited(_restoreSessionInBackground());
  }

  Future<void> _restoreSessionInBackground() async {
    final ok = await widget.auth.restoreSession();
    if (!mounted) return;
    if (ok) {
      unawaited(widget.notification.resumeAfterLogin());
    } else {
      final hasLocal = await widget.auth.hasLocalSession();
      if (!mounted) return;
      setState(() => _loggedIn = hasLocal);
    }
  }

  void _onPushOpenConversation(String conversationId) {
    if (_loggedIn != true) return;
    _pendingPushConversation.value = conversationId;
  }

  Future<void> _onLoggedIn() async {
    setState(() => _loggedIn = true);
    unawaited(widget.notification.resumeAfterLogin());
  }

  Future<void> _onLogout() async {
    await widget.notification.pauseForLogout();
    await widget.auth.logout();
    if (!mounted) return;
    setState(() => _loggedIn = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IHope',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: switch (_loggedIn) {
        null => const Scaffold(body: Center(child: CircularProgressIndicator())),
        true => ConversationsScreen(
            auth: widget.auth,
            notification: widget.notification,
            onLogout: _onLogout,
            pendingPushConversation: _pendingPushConversation,
          ),
        false => LoginScreen(auth: widget.auth, onLoggedIn: _onLoggedIn),
      },
    );
  }
}
