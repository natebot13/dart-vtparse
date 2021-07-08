import 'dart:async';
import 'dart:io';

import 'package:vtparse/vtparse.dart';

final q = 'q'.codeUnitAt(0);

void main() async {
  // Don't echo the things typed
  stdin.echoMode = false;
  // Accept char by char instead of line by line
  stdin.lineMode = false;

  // This could use stdin.expand(...) instead, but since you can't close stdin,
  // manually listening to it and passing events to a StreamController allows
  // us to close the StreamController when we're done with it.
  final _stdioByteController = StreamController<int>();
  final _stdioSubscription = stdin.listen((event) {
    for (final byte in event) {
      _stdioByteController.sink.add(byte);
    }
  });

  final parser = VTParse(_stdioByteController.stream);
  parser.events.listen((event) {
    print(event);
    // For example, this closes the stream if 'q' is typed. We wouldn't be able
    // to close the stream if we used stdin.expand above. Using our own stream
    // gives us the ability to close things properly if we're done taking user
    // input.
    if (event.action == VTAction.print && event.ch == q) {
      _stdioSubscription.cancel();
      _stdioByteController.close();
    }
  });
}
