import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ihope/screens/login_screen.dart';
import 'package:ihope/services/auth_service.dart';

void main() {
  testWidgets('login screen renders email and password fields', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          auth: AuthService(),
          onLoggedIn: () {},
        ),
      ),
    );

    expect(find.text('登录 IHope'), findsOneWidget);
    expect(find.text('邮箱'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
  });
}
