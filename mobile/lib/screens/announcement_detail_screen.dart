import 'package:flutter/material.dart';

import '../models/message.dart';
import '../utils/announcement_payload.dart';
import '../utils/message_time.dart';

/// 群公告详情（全屏页面，非底部弹窗）。
class AnnouncementDetailScreen extends StatelessWidget {
  const AnnouncementDetailScreen({
    super.key,
    required this.msg,
    required this.publisherName,
  });

  final ChatMessage msg;
  final String publisherName;

  static Future<void> open(
    BuildContext context, {
    required ChatMessage msg,
    required String publisherName,
    VoidCallback? onMarkRead,
  }) {
    onMarkRead?.call();
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AnnouncementDetailScreen(
          msg: msg,
          publisherName: publisherName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final payload = AnnouncementPayload.fromMessage(msg);
    final body = payload.body.isEmpty ? msg.displayText : payload.body;

    return Scaffold(
      appBar: AppBar(
        title: const Text('群公告'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Row(
            children: [
              Icon(Icons.campaign_outlined, color: scheme.primary, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  payload.displayTitle,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '$publisherName · ${MessageTimeFormat.formatDivider(msg.createdAt)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 24),
          Text(
            body,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  height: 1.6,
                ),
          ),
        ],
      ),
    );
  }
}
