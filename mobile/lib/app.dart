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
  bool _ready = false;
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final ok = await widget.auth.restoreSession();
    if (!mounted) return;
    setState(() {
      _loggedIn = ok;
      _ready = true;
    });
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
      home: !_ready
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _loggedIn
              ? ConversationsScreen(auth: widget.auth, onLogout: _onLogout)
              : LoginScreen(auth: widget.auth, onLoggedIn: _onLoggedIn),
    );
  }
}
