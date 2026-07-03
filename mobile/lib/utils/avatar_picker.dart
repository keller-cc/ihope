import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../widgets/app_page_route.dart';
import '../screens/avatar_crop_screen.dart';

/// 从相册选图并裁剪为方形头像；取消时返回 null。
Future<Uint8List?> pickAndCropAvatar(BuildContext context) async {
  final picker = ImagePicker();
  final file = await picker.pickImage(
    source: ImageSource.gallery,
    imageQuality: 95,
  );
  if (file == null || !context.mounted) return null;

  final rawBytes = await file.readAsBytes();
  if (!context.mounted) return null;
  return Navigator.of(context).push<Uint8List>(
    appPageRoute(
      builder: (_) => AvatarCropScreen(imageBytes: rawBytes),
    ),
  );
}
