/// One Server-Sent Event.
class SseMessage {
  const SseMessage({required this.event, required this.data, this.id});

  final String? id;
  final String event;
  final String data;
}

/// Parses the text/event-stream format line by line.
///
///   id: 12
///   event: alert
///   data: {"id":"alt_1"}
///   (blank line ends the event; lines starting with ':' are heartbeats)
class SseParser {
  String? _id;
  String? _event;
  final _data = StringBuffer();
  var _hasData = false;

  /// Feed one line without its newline. Returns an event when a blank line
  /// completes one, otherwise null.
  SseMessage? addLine(String line) {
    if (line.isEmpty) {
      if (!_hasData) {
        _event = null;
        return null;
      }
      final message = SseMessage(
        id: _id,
        event: _event ?? 'message',
        data: _data.toString(),
      );
      _event = null;
      _data.clear();
      _hasData = false;
      return message;
    }
    if (line.startsWith(':')) return null;

    final colon = line.indexOf(':');
    final field = colon == -1 ? line : line.substring(0, colon);
    var value = colon == -1 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);

    switch (field) {
      case 'id':
        _id = value;
      case 'event':
        _event = value;
      case 'data':
        if (_hasData) _data.write('\n');
        _data.write(value);
        _hasData = true;
    }
    return null;
  }
}
