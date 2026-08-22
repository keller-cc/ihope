import 'package:flutter/material.dart';

/// 全局路由观察，用于会话列表页感知子页面压栈（QQ 式横幅仅留在列表顶栏）。
final appRouteObserver = RouteObserver<ModalRoute<void>>();
