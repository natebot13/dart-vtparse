part of 'vtparse.dart';

enum _State {
  csiEntry,
  csiIgnore,
  csiIntermediate,
  csiParam,
  dcsEntry,
  dcsIgnore,
  dcsIntermediate,
  dcsParam,
  dcsPassthrough,
  escape,
  escapeIntermediate,
  ground,
  oscString,
  sosPmApcString,
}

enum _ParseAction {
  clear,
  collect,
  csiDispatch,
  dcsHook,
  dcsPut,
  dcsUnhook,
  error,
  escDispatch,
  execute,
  ignore,
  oscEnd,
  oscPut,
  oscStart,
  param,
  print,
}

class VTStateMachine {
  /// Maximum number of private markers and intermediate characters to collect.
  /// If more than this many private markers or intermediate characters are
  /// encountered by Action.COLLECT, the control sequence is considered
  /// malformed, and ignored.
  ///
  /// This effects the following states, which contain Action.COLLECT:
  ///
  /// State.ESCAPE_INTERMEDIATE:
  ///
  /// When transitioning to State.GROUND, Action.ESC_DISPATCH is ignored.
  ///
  /// State.CSI_INTERMEDIATE:
  ///
  /// When transitioning to State.GROUND, Action.CSI_DISPATCH is ignored.
  ///
  /// (Effectively, behaves as State.CSI_IGNORE instead.)
  ///
  /// State.DCS_INTERMEDIATE:
  ///
  /// After transitioning to State.DCS_PASSTHROUGH, these actions are ignored:
  ///
  /// Action.DCS_HOOK, Action.DCS_PUT, Action.DCS_UNHOOK
  ///
  /// (Effectively, behaves as State.DCS_IGNORE instead.)
  ///
  ///
  static const int _MAX_INTERMEDIATE_BYTES = 2;

  final _intermediateBytes = <int>[];

  /// Maximum number of parameters to collect.
  /// If more than this many parameters are encountered by Action.PARAM,
  /// the extra parameters are simply ignored.
  static const int _MAX_PARAMS = 16;

  final _params = <int>[];
  int _currentParam = 0;

  final _machine = Machine<_State>();

  StreamSubscription<int>? _anywhereSubscription;

  final _eventController = StreamController<VTEvent>();
  Stream<VTEvent> get events => _eventController.stream;

  /// Creates a VT State Machine using the feed to transition between states.
  /// [feed] must be a broadcast stream in order for different states to start
  /// and stop listening to the feed
  VTStateMachine(Stream<int> feed) {
    // Create Anywhere handler
    _anywhereSubscription = feed.listen((byte) {
      if (_doWhen(_ParseAction.execute, byte, 0x18)) {
        _machine.current = _State.ground;
      }
      if (_doWhen(_ParseAction.execute, byte, 0x1a)) {
        _machine.current = _State.ground;
      }
      if (_doWhen(null, byte, 0x1b)) _machine.current = _State.escape;
      if (_doWhen(_ParseAction.execute, byte, 0x80, 0x8f)) {
        _machine.current = _State.ground;
      }
      if (_doWhen(null, byte, 0x90)) _machine.current = _State.dcsEntry;
      if (_doWhen(_ParseAction.execute, byte, 0x91, 0x97)) {
        _machine.current = _State.ground;
      }
      if (_doWhen(null, byte, 0x98)) _machine.current = _State.sosPmApcString;
      if (_doWhen(_ParseAction.execute, byte, 0x99)) {
        _machine.current = _State.ground;
      }
      if (_doWhen(_ParseAction.execute, byte, 0x9a)) {
        _machine.current = _State.ground;
      }
      if (_doWhen(null, byte, 0x9b)) _machine.current = _State.csiEntry;
      if (_doWhen(null, byte, 0x9c)) _machine.current = _State.ground;
      if (_doWhen(null, byte, 0x9d)) _machine.current = _State.oscString;
      if (_doWhen(null, byte, 0x9e)) _machine.current = _State.sosPmApcString;
      if (_doWhen(null, byte, 0x9f)) _machine.current = _State.sosPmApcString;
    }, onDone: close);

    // Ground state
    _machine.newState(_State.ground).onStream<int>(feed, (byte) {
      _doWhen(_ParseAction.execute, byte, 0x00, 0x17);
      _doWhen(_ParseAction.execute, byte, 0x19);
      _doWhen(_ParseAction.execute, byte, 0x1c, 0x1f);
      _doWhen(_ParseAction.print, byte, 0x20, 0x7f);
    });

    // Escape state
    _machine.newState(_State.escape)
      ..onStream<int>(feed, (byte) {
        _doWhen(_ParseAction.execute, byte, 0x00, 0x17);
        _doWhen(_ParseAction.execute, byte, 0x19);
        _doWhen(_ParseAction.execute, byte, 0x1c, 0x1f);
        if (_doWhen(_ParseAction.collect, byte, 0x20, 0x2f)) {
          _machine.current = _State.escapeIntermediate;
        }
        if (_doWhen(_ParseAction.escDispatch, byte, 0x30, 0x4f)) {
          _machine.current = _State.ground;
        }
        if (_doWhen(null, byte, 0x50)) _machine.current = _State.dcsEntry;
        if (_doWhen(_ParseAction.escDispatch, byte, 0x51, 0x57)) {
          _machine.current = _State.ground;
        }
        if (_doWhen(null, byte, 0x58)) _machine.current = _State.sosPmApcString;
        if (_doWhen(_ParseAction.escDispatch, byte, 0x59)) {
          _machine.current = _State.ground;
        }
        if (_doWhen(_ParseAction.escDispatch, byte, 0x5a)) {
          _machine.current = _State.ground;
        }
        if (_doWhen(null, byte, 0x5b)) _machine.current = _State.csiEntry;
        if (_doWhen(_ParseAction.escDispatch, byte, 0x5c)) {
          _machine.current = _State.ground;
        }
        if (_doWhen(null, byte, 0x5d)) _machine.current = _State.oscString;
        if (_doWhen(null, byte, 0x5e)) _machine.current = _State.sosPmApcString;
        if (_doWhen(null, byte, 0x5f)) _machine.current = _State.sosPmApcString;
        if (_doWhen(_ParseAction.escDispatch, byte, 0x60, 0x7e)) {
          _machine.current = _State.ground;
        }
        _doWhen(_ParseAction.ignore, byte, 0x7f);
      })
      ..onEntry(() {
        _doAction(_ParseAction.clear, 0);
      });

    // Escape intermediate state
    _machine.newState(_State.escapeIntermediate).onStream<int>(feed, (byte) {
      _doWhen(_ParseAction.execute, byte, 0x00, 0x17);
      _doWhen(_ParseAction.execute, byte, 0x19);
      _doWhen(_ParseAction.execute, byte, 0x1c, 0x1f);
      _doWhen(_ParseAction.collect, byte, 0x20, 0x2f);
      if (_doWhen(_ParseAction.escDispatch, byte, 0x30, 0x7e)) {
        _machine.current = _State.ground;
      }
      _doWhen(_ParseAction.ignore, byte, 0x7f);
    });

    // CSI entry state
    _machine.newState(_State.csiEntry)
      ..onStream<int>(feed, (byte) {
        _doWhen(_ParseAction.execute, byte, 0x00, 0x17);
        _doWhen(_ParseAction.execute, byte, 0x19);
        _doWhen(_ParseAction.execute, byte, 0x1c, 0x1f);
        if (_doWhen(_ParseAction.collect, byte, 0x20, 0x2f)) {
          _machine.current = _State.csiIntermediate;
        }
        if (_doWhen(_ParseAction.param, byte, 0x30, 0x39)) {
          _machine.current = _State.csiParam;
        }
        if (_doWhen(null, byte, 0x3a)) _machine.current = _State.csiIgnore;
        if (_doWhen(_ParseAction.param, byte, 0x3b)) {
          _machine.current = _State.csiParam;
        }
        if (_doWhen(_ParseAction.collect, byte, 0x3c, 0x3f)) {
          _machine.current = _State.csiParam;
        }
        if (_doWhen(_ParseAction.csiDispatch, byte, 0x40, 0x7e)) {
          _machine.current = _State.ground;
        }
        _doWhen(_ParseAction.ignore, byte, 0x7f);
      })
      ..onEntry(() {
        _doAction(_ParseAction.clear, 0);
      });

    // CSI ignore state
    _machine.newState(_State.csiIgnore).onStream<int>(feed, (byte) {
      _doWhen(_ParseAction.execute, byte, 0x00, 0x17);
      _doWhen(_ParseAction.execute, byte, 0x19);
      _doWhen(_ParseAction.execute, byte, 0x1c, 0x1f);
      _doWhen(_ParseAction.ignore, byte, 0x20, 0x3f);
      if (_doWhen(null, byte, 0x40, 0x7e)) _machine.current = _State.ground;
      _doWhen(_ParseAction.ignore, byte, 0x7f);
    });

    // CSI params state
    _machine.newState(_State.csiParam).onStream<int>(feed, (byte) {
      _doWhen(_ParseAction.execute, byte, 0x00, 0x17);
      _doWhen(_ParseAction.execute, byte, 0x19);
      _doWhen(_ParseAction.execute, byte, 0x1c, 0x1f);
      if (_doWhen(_ParseAction.collect, byte, 0x20, 0x2f)) {
        _machine.current = _State.csiIntermediate;
      }
      _doWhen(_ParseAction.param, byte, 0x30, 0x39);
      if (_doWhen(null, byte, 0x3a)) _machine.current = _State.csiIgnore;
      _doWhen(_ParseAction.param, byte, 0x3b);
      if (_doWhen(null, byte, 0x3c, 0x3f)) _machine.current = _State.csiIgnore;
      if (_doWhen(_ParseAction.csiDispatch, byte, 0x40, 0x7e)) {
        _machine.current = _State.ground;
      }
      _doWhen(_ParseAction.ignore, byte, 0x7f);
    });

    // CSI intermediate state
    _machine.newState(_State.csiIntermediate).onStream<int>(feed, (byte) {
      _doWhen(_ParseAction.execute, byte, 0x00, 0x17);
      _doWhen(_ParseAction.execute, byte, 0x19);
      _doWhen(_ParseAction.execute, byte, 0x1c, 0x1f);
      _doWhen(_ParseAction.collect, byte, 0x20, 0x2f);
      if (_doWhen(null, byte, 0x30, 0x3f)) _machine.current = _State.csiIgnore;
      if (_doWhen(_ParseAction.csiDispatch, byte, 0x40, 0x7e)) {
        _machine.current = _State.ground;
      }
      _doWhen(_ParseAction.ignore, byte, 0x7f);
    });

    // DCS entry state
    _machine.newState(_State.dcsEntry)
      ..onStream<int>(feed, (byte) {
        _doWhen(_ParseAction.ignore, byte, 0x00, 0x17);
        _doWhen(_ParseAction.ignore, byte, 0x19);
        _doWhen(_ParseAction.ignore, byte, 0x1c, 0x1f);
        if (_doWhen(_ParseAction.collect, byte, 0x20, 0x2f)) {
          _machine.current = _State.dcsIntermediate;
        }
        if (_doWhen(_ParseAction.param, byte, 0x30, 0x39)) {
          _machine.current = _State.dcsParam;
        }
        if (_doWhen(null, byte, 0x3a)) _machine.current = _State.dcsIgnore;
        if (_doWhen(_ParseAction.param, byte, 0x3b)) {
          _machine.current = _State.dcsParam;
        }
        if (_doWhen(_ParseAction.collect, byte, 0x3c, 0x3f)) {
          _machine.current = _State.dcsParam;
        }
        if (_doWhen(null, byte, 0x40, 0x7e)) {
          _machine.current = _State.dcsPassthrough;
        }
        _doWhen(_ParseAction.ignore, byte, 0x7f);
      })
      ..onEntry(() {
        _doAction(_ParseAction.clear, 0);
      });

    // DCS intermediate state
    _machine.newState(_State.dcsIntermediate).onStream<int>(feed, (byte) {
      _doWhen(_ParseAction.ignore, byte, 0x00, 0x17);
      _doWhen(_ParseAction.ignore, byte, 0x19);
      _doWhen(_ParseAction.ignore, byte, 0x1c, 0x1f);
      _doWhen(_ParseAction.collect, byte, 0x20, 0x2f);
      if (_doWhen(null, byte, 0x30, 0x3f)) _machine.current = _State.dcsIgnore;
      if (_doWhen(null, byte, 0x40, 0x7e)) {
        _machine.current = _State.dcsPassthrough;
      }
      _doWhen(_ParseAction.ignore, byte, 0x7f);
    });

    // DCS ignore state
    _machine.newState(_State.dcsIgnore).onStream<int>(feed, (byte) {
      _doWhen(_ParseAction.ignore, byte, 0x00, 0x17);
      _doWhen(_ParseAction.ignore, byte, 0x19);
      _doWhen(_ParseAction.ignore, byte, 0x1c, 0x1f);
      _doWhen(_ParseAction.ignore, byte, 0x20, 0x7f);
    });

    // DCS param state
    _machine.newState(_State.dcsParam).onStream<int>(feed, (byte) {
      _doWhen(_ParseAction.ignore, byte, 0x00, 0x17);
      _doWhen(_ParseAction.ignore, byte, 0x19);
      _doWhen(_ParseAction.ignore, byte, 0x1c, 0x1f);
      if (_doWhen(_ParseAction.collect, byte, 0x20, 0x2f)) {
        _machine.current = _State.dcsIntermediate;
      }
      _doWhen(_ParseAction.param, byte, 0x30, 0x39);
      if (_doWhen(null, byte, 0x3a)) _machine.current = _State.dcsIgnore;
      _doWhen(_ParseAction.param, byte, 0x3b);
      if (_doWhen(null, byte, 0x3c, 0x3f)) _machine.current = _State.dcsIgnore;
      if (_doWhen(null, byte, 0x40, 0x7e)) {
        _machine.current = _State.dcsPassthrough;
      }
      _doWhen(_ParseAction.ignore, byte, 0x7f);
    });

    // DCS passthrough state
    _machine.newState(_State.dcsPassthrough)
      ..onStream<int>(feed, (byte) {
        _doWhen(_ParseAction.dcsPut, byte, 0x00, 0x17);
        _doWhen(_ParseAction.dcsPut, byte, 0x19);
        _doWhen(_ParseAction.dcsPut, byte, 0x1c, 0x1f);
        _doWhen(_ParseAction.dcsPut, byte, 0x20, 0x7e);
        _doWhen(_ParseAction.ignore, byte, 0x7f);
      })
      ..onEntry(() {
        _doAction(_ParseAction.dcsHook, 0);
      })
      ..onExit(() {
        _doAction(_ParseAction.dcsUnhook, 0);
      });

    // SOS PM APC string state
    _machine.newState(_State.sosPmApcString).onStream<int>(feed, (byte) {
      _doWhen(_ParseAction.ignore, byte, 0x00, 0x17);
      _doWhen(_ParseAction.ignore, byte, 0x19);
      _doWhen(_ParseAction.ignore, byte, 0x1c, 0x1f);
      _doWhen(_ParseAction.ignore, byte, 0x20, 0x7f);
    });

    // OSC string state
    _machine.newState(_State.oscString)
      ..onStream<int>(feed, (byte) {
        _doWhen(_ParseAction.ignore, byte, 0x00, 0x17);
        _doWhen(_ParseAction.ignore, byte, 0x19);
        _doWhen(_ParseAction.ignore, byte, 0x1c, 0x1f);
        _doWhen(_ParseAction.oscPut, byte, 0x20, 0x7f);
      })
      ..onEntry(() {
        _doAction(_ParseAction.oscStart, 0);
      })
      ..onExit(() {
        _doAction(_ParseAction.oscEnd, 0);
      });

    _machine.start();
  }

  void _sendEvent(VTAction action,
      [int? byte, List<int>? intermediate, List<int>? params]) {
    _eventController.sink.add(VTEvent(action, byte, intermediate, params));
  }

  bool _doWhen(_ParseAction? action, int byte, int start, [int? stop]) {
    if (byte == start) {
      _doAction(action, byte);
      return true;
    }
    if (stop != null && start < stop) {
      if (byte > start && byte <= stop) {
        _doAction(action, byte);
        return true;
      }
    }
    return false;
  }

  void _doAction(_ParseAction? action, int byte) {
    if (action == null) return;
    switch (action) {
      // Actions to hand off to emulator:
      case _ParseAction.csiDispatch:
        if (_intermediateBytes.length <= _MAX_INTERMEDIATE_BYTES) {
          _sendEvent(VTAction.csiDispatch, byte, _intermediateBytes, _params);
        }
        break;
      case _ParseAction.dcsHook:
        if (_intermediateBytes.length <= _MAX_INTERMEDIATE_BYTES) {
          _sendEvent(VTAction.dcsHook, byte, _intermediateBytes, _params);
        }
        break;
      case _ParseAction.dcsPut:
        if (_intermediateBytes.length <= _MAX_INTERMEDIATE_BYTES) {
          _sendEvent(VTAction.dcsPut, byte);
        }
        break;
      case _ParseAction.dcsUnhook:
        if (_intermediateBytes.length <= _MAX_INTERMEDIATE_BYTES) {
          _sendEvent(VTAction.dcsUnhook);
        }
        break;
      case _ParseAction.error:
        _sendEvent(VTAction.error);
        break;
      case _ParseAction.escDispatch:
        if (_intermediateBytes.length <= _MAX_INTERMEDIATE_BYTES) {
          _sendEvent(VTAction.escapeDispatch, byte, _intermediateBytes);
        }
        break;
      case _ParseAction.execute:
        _sendEvent(VTAction.execute, byte);
        break;
      case _ParseAction.oscEnd:
        _sendEvent(VTAction.oscEnd);
        break;
      case _ParseAction.oscPut:
        _sendEvent(VTAction.oscPut, byte);
        break;
      case _ParseAction.oscStart:
        _sendEvent(VTAction.oscStart);
        break;
      case _ParseAction.print:
        _sendEvent(VTAction.print, byte);
        break;

      // Actions to handle internally:
      case _ParseAction.ignore:
        // do nothing
        break;

      case _ParseAction.clear:
        _clear();
        break;

      case _ParseAction.collect:
        _intermediateBytes.add(byte);
        break;

      case _ParseAction.param:
        if (byte == ';'.codeUnitAt(0)) {
          // go to next param
          // note that if param string starts with ';' then we jump to 2nd param
          _params.add(0);
          _currentParam++;
        } else if (_params.length <= _MAX_PARAMS) {
          // the character is a digit, and we haven't reached MAX_PARAMS
          _params[_currentParam] *= 10;
          _params[_currentParam] += (byte - '0'.codeUnitAt(0));
        }
        break;
    }
  }

  void _clear() {
    _intermediateBytes.clear();
    _params.clear();
    _params.add(0);
    _currentParam = 0;
  }

  Future<void> close() async {
    await _anywhereSubscription?.cancel();
    await _eventController.close();
  }
}
