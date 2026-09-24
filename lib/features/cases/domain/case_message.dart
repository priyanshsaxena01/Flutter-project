enum MessageSender {
  customer('CUSTOMER'),
  bank('BANK');

  const MessageSender(this.api);

  final String api;
}

/// A secure message on a case (F8).
class CaseMessage {
  const CaseMessage({
    required this.id,
    required this.from,
    required this.text,
    required this.at,
    this.attachmentName,
  });

  factory CaseMessage.fromJson(Map<String, Object?> json) => CaseMessage(
    id: json['id']! as String,
    from:
        json['from'] == 'CUSTOMER'
            ? MessageSender.customer
            : MessageSender.bank,
    text: json['text'] as String? ?? '',
    at: DateTime.parse(json['at']! as String).toLocal(),
    attachmentName: json['attachmentName'] as String?,
  );

  final String id;
  final MessageSender from;
  final String text;
  final DateTime at;
  final String? attachmentName;
}

/// One page of messages, newest first. [nextCursor] loads older ones.
class MessagePage {
  const MessagePage({required this.items, this.nextCursor});

  final List<CaseMessage> items;
  final String? nextCursor;
}
