import 'dart:async';

import 'package:flutter/material.dart';

import 'services/auth_service.dart';
import 'screens/conversations_screen.dart';
import 'screens/login_screen.dart';

class IHopeApp extends StatefulWidget {
  const IHopeApp({super.key, required this.auth});

  final AuthService auth;

  @override
  State<IHopeApp> createState() => _IHopeAppState();
}

class _IHopeAppState extends State<IHopeApp> {
  bool? _loggedIn;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    final local = await widget.auth.restoreLocalSession();
    if (!mounted) return;
    setState(() => _loggedIn = local);
    if (!local) return;

    final ok = await widget.auth.restoreSession();
    if (!mounted) return;
    if (!ok) setState(() => _loggedIn = false);
  }

  Future<void> _onLoggedIn() async {
    setState(() => _loggedIn = true);
  }

  Future<void> _onLogout() async {
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
        null => const Scaffold(),
        true => ConversationsScreen(auth: widget.auth, onLogout: _onLogout),
        false => LoginScreen(auth: widget.auth, onLoggedIn: _onLoggedIn),
      },
    );
  }
}
