import 'dart:async';
import 'package:statemachine/statemachine.dart';

part 'vtparse_state_machine.dart';

enum VTAction {
  csiDispatch,
  dcsHook,
  dcsPut,
  dcsUnhook,
  error,
  escapeDispatch,
  execute,
  oscEnd,
  oscPut,
  oscStart,
  print,
}

class VTEvent {
  final VTAction action;
  final int? ch;
  final List<int>? intermediateChars;
  final List<int>? params;
  VTEvent(this.action, [this.ch, this.intermediateChars, this.params]);

  @override
  String toString() {
    return 'VTEvent: $action, $ch, $intermediateChars, $params';
  }
}

class VTParse {
  final VTStateMachine _stateMachine;

  Stream<VTEvent> get events => _stateMachine.events;
  VTParse(Stream<int> feed)
      : _stateMachine = VTStateMachine(feed.asBroadcastStream());
}
