import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

/// 选择图片后裁剪为方形头像，确认后返回 JPEG 字节。
class AvatarCropScreen extends StatefulWidget {
  const AvatarCropScreen({super.key, required this.imageBytes});

  final Uint8List imageBytes;

  @override
  State<AvatarCropScreen> createState() => _AvatarCropScreenState();
}

class _AvatarCropScreenState extends State<AvatarCropScreen> {
  final _cropController = CropController();
  bool _cropping = false;

  Future<void> _confirm() async {
    if (_cropping) return;
    setState(() => _cropping = true);
    try {
      _cropController.crop();
    } catch (_) {
      if (mounted) setState(() => _cropping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('裁剪头像'),
        actions: [
          TextButton(
            onPressed: _cropping ? null : _confirm,
            child: _cropping
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('确认'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Crop(
              controller: _cropController,
              image: widget.imageBytes,
              aspectRatio: 1,
              withCircleUi: true,
              initialRectBuilder: InitialRectBuilder.withSizeAndRatio(
                size: 0.85,
                aspectRatio: 1,
              ),
              onCropped: (result) {
                if (!mounted) return;
                switch (result) {
                  case CropSuccess(:final croppedImage):
                    Navigator.of(context).pop(croppedImage);
                  case CropFailure(:final cause):
                    setState(() => _cropping = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('裁剪失败：$cause')),
                    );
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '拖动、缩放图片，确认后将上传为新头像',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
