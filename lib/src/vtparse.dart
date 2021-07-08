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

/// An event representing a sequence of one or more bytes.
///
/// For example, control sequences send two bytes representing the combination
/// of pressing control and something else. One event would represent that two
/// byte action
class VTEvent {
  final VTAction action;

  /// The character that was typed or is associated with this event
  final int? ch;

  /// The intermediate characters included with some events
  final List<int>? intermediateChars;

  /// The parameters included with some events
  ///
  /// For example, PgUp and PgDn keys have params to differentiate the two
  final List<int>? params;

  VTEvent(this.action, [this.ch, this.intermediateChars, this.params]);

  @override
  String toString() {
    return 'VTEvent: $action, $ch, $intermediateChars, $params';
  }
}

class VTParse {
  final VTStateMachine _stateMachine;

  VTParse(Stream<int> feed)
      : _stateMachine = VTStateMachine(feed.asBroadcastStream());

  /// Event stream that emits VTEvent's after parsing one or more bytes
  Stream<VTEvent> get events => _stateMachine.events;
}
