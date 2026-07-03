import 'package:flutter_test/flutter_test.dart';
import 'package:ihope/utils/chat_history_highlight.dart';

void main() {
  test('snippetAround keeps keyword visible', () {
    final text = '你好世界这是一段很长的聊天记录包含关键词测试内容';
    final snippet = ChatHistoryHighlight.snippetAround(text, '关键词', maxLength: 20);
    expect(snippet.contains('关键词'), isTrue);
  });
}
