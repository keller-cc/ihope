import 'package:flutter/material.dart';

import 'app.dart';
import 'services/auth_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(IHopeApp(auth: AuthService()));
}
