import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:flutter_munawwara/core/utils/app_logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SocketService – static singleton wrapping the Socket.io connection.
// Call SocketService.connect(...) once after login; all other classes can
// then call SocketService.emit / .on / .off directly.
//
// Safety notes:
//  • on() stores handlers in _pendingListeners (keyed by event name).
//    When connect() creates a new socket it re-applies them, so call order
//    between on() and connect() does not matter.
//  • Reserved engine events (connect, disconnect, reconnect, error, etc.)
//    are handled internally.  External code should use onConnected() instead
//    of on('connect', ...) to avoid clobbering the register-user handshake.
//  • ACK-bearing events (call-offer) are dispatched via onAny so the ack
//    callback is always extracted from the payload list socket.io passes.
// ─────────────────────────────────────────────────────────────────────────────

/// Handler for server events that require an acknowledgement (e.g. call-offer).
typedef SocketAckHandler = void Function(
  dynamic data,
  void Function([dynamic response])? ack,
);

class SocketService {
  static io.Socket? _socket;
  static String? _connectedUserId;
  static String? _lastServerUrl;
  static String? _lastRole;
  static bool _onAnyDispatcherInstalled = false;
  static bool _reconnectScheduled = false;

  /// Custom-event listeners (NOT for reserved socket.io events).
  static final Map<String, void Function(dynamic)> _pendingListeners = {};

  /// Events where the server expects an ACK (socket_io_client appends ack last).
  static final Map<String, SocketAckHandler> _pendingAckListeners = {};

  /// Callbacks that fire every time the socket connects / reconnects.
  /// Use [onConnected] / [offConnected] to manage these.
  static final List<void Function()> _onConnectCallbacks = [];

  /// Reserved engine events that must not go through [on]/[off].
  static const _reserved = {
    'connect',
    'disconnect',
    'reconnect',
    'error',
    'connect_error',
    'connect_timeout',
  };

  // ── Connect ──────────────────────────────────────────────────────────────────
  static void connect({
    required String serverUrl,
    required String userId,
    required String role,
  }) {
    if (_socket != null && _socket!.connected && _connectedUserId == userId) {
      AppLogger.d(
        '[SocketService] Already connected as $userId – re-applying listeners',
      );
      _applyPendingListeners();
      return;
    }

    _socket?.dispose();
    _socket = null;
    _onAnyDispatcherInstalled = false;
    _connectedUserId = userId;
    _lastServerUrl = serverUrl.endsWith('/')
        ? serverUrl.substring(0, serverUrl.length - 1)
        : serverUrl;
    _lastRole = role;

    final cleanUrl = _lastServerUrl!;

    AppLogger.w(
      '[SocketService] Connecting to $cleanUrl as $userId ($role)',
    );

    _socket = io.io(
      cleanUrl,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .setReconnectionDelay(2000)
          .setReconnectionAttempts(20)
          .enableReconnection()
          .build(),
    );

    _socket!.onConnect((_) {
      _reconnectScheduled = false;
      AppLogger.w(
        '[SocketService] Connected socketId=${_socket?.id} url=$cleanUrl '
        'userId=$userId role=$role',
      );
      _socket!.emit('register-user', {'userId': userId, 'role': role});
      for (final cb in List.of(_onConnectCallbacks)) {
        try {
          cb();
        } catch (e) {
          AppLogger.d('[SocketService] onConnected callback error: $e');
        }
      }
    });

    _socket!.onDisconnect((reason) {
      AppLogger.d('[SocketService] Disconnected: $reason');
      _scheduleReconnectAfterServerEviction(reason?.toString());
    });

    _socket!.onConnectError((err) {
      AppLogger.w('[SocketService] Connection error ($cleanUrl): $err');
    });

    _socket!.onError((err) {
      AppLogger.w('[SocketService] Socket error ($cleanUrl): $err');
    });

    _applyPendingListeners();
  }

  /// Server ACK-timeout eviction uses `namespace disconnect`, which disables
  /// socket.io auto-reconnect. Open a fresh socket so the next call can ring.
  static void _scheduleReconnectAfterServerEviction(String? reason) {
    if (reason != 'io server disconnect') return;
    final userId = _connectedUserId;
    final url = _lastServerUrl;
    final role = _lastRole;
    if (userId == null || url == null || role == null) return;
    if (_reconnectScheduled) return;
    _reconnectScheduled = true;
    AppLogger.w(
      '[SocketService] Server evicted socket — scheduling reconnect for $userId',
    );
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      _reconnectScheduled = false;
      if (_connectedUserId != userId) return;
      if (_socket?.connected == true) return;
      connect(serverUrl: url, userId: userId, role: role);
    });
  }

  // ── Emit ──────────────────────────────────────────────────────────────────
  static void emit(String event, dynamic data) {
    _socket?.emit(event, data);
  }

  // ── Custom-event listen / unlisten ────────────────────────────────────────
  static void on(String event, void Function(dynamic) handler) {
    if (_reserved.contains(event)) {
      AppLogger.d(
        '[SocketService] ⚠ "$event" is reserved – use onConnected() instead',
      );
      return;
    }
    _pendingAckListeners.remove(event);
    _pendingListeners[event] = handler;
    if (_socket != null) {
      _socket!.off(event);
      _socket!.on(event, handler);
    }
  }

  /// Register a handler that must ACK the server immediately on receipt.
  static void onWithAck(String event, SocketAckHandler handler) {
    if (_reserved.contains(event)) {
      AppLogger.d(
        '[SocketService] ⚠ "$event" is reserved – use onConnected() instead',
      );
      return;
    }
    _pendingListeners.remove(event);
    _pendingAckListeners[event] = handler;
    if (_socket != null) {
      _socket!.off(event);
      _ensureOnAnyDispatcher();
    }
  }

  static void off(String event) {
    if (_reserved.contains(event)) return;
    _pendingListeners.remove(event);
    _pendingAckListeners.remove(event);
    _socket?.off(event);
  }

  static void onConnected(void Function() callback) {
    if (!_onConnectCallbacks.contains(callback)) {
      _onConnectCallbacks.add(callback);
    }
  }

  static void offConnected(void Function() callback) {
    _onConnectCallbacks.remove(callback);
  }

  static bool get isConnected => _socket?.connected ?? false;
  static String? get connectedUserId => _connectedUserId;

  static void disconnect() {
    _socket?.dispose();
    _socket = null;
    _connectedUserId = null;
    _lastServerUrl = null;
    _lastRole = null;
    _onAnyDispatcherInstalled = false;
    _reconnectScheduled = false;
  }

  static void _applyPendingListeners() {
    if (_socket == null) return;
    final ackEvents = _pendingAckListeners.keys.toSet();
    for (final entry in _pendingListeners.entries) {
      if (ackEvents.contains(entry.key)) continue;
      _socket!.off(entry.key);
      _socket!.on(entry.key, entry.value);
    }
    for (final event in ackEvents) {
      _socket!.off(event);
    }
    _ensureOnAnyDispatcher();
  }

  /// ACK events are routed through [onAny] — socket.io passes `[payload, ackFn]`
  /// as the data argument, which is more reliable than per-event `.on` wrappers.
  static void _ensureOnAnyDispatcher() {
    if (_socket == null || _onAnyDispatcherInstalled) return;
    _onAnyDispatcherInstalled = true;
    _socket!.onAny((String event, dynamic data) {
      final handler = _pendingAckListeners[event];
      if (handler == null) return;

      final parsed = _splitPayloadAndAck(data);
      if (parsed.ack != null) {
        _invokeAck(parsed.ack!);
        AppLogger.i('[SocketService] ACK sent for "$event"');
      }

      handler(
        parsed.payload,
        parsed.ack == null
            ? null
            : ([response]) => _invokeAck(parsed.ack!, response),
      );
    });
  }

  static ({dynamic payload, Function? ack}) _splitPayloadAndAck(dynamic incoming) {
    dynamic payload = incoming;
    Function? ack;

    if (incoming is List && incoming.isNotEmpty) {
      final list = List<dynamic>.from(incoming);
      if (list.last is Function) {
        ack = list.removeLast();
      }
      if (list.length == 1) {
        payload = list.first;
      } else if (list.isEmpty) {
        payload = null;
      } else if (list.length == 2 &&
          list.first is String &&
          list[1] is Map) {
        payload = list[1];
      } else {
        payload = list.length == 1 ? list.first : list;
      }
    }

    return (payload: payload, ack: ack);
  }

  static void _invokeAck(Function ack, [dynamic response]) {
    try {
      ack(response);
    } catch (_) {
      try {
        ack();
      } catch (e) {
        AppLogger.w('[SocketService] ack invoke failed: $e');
      }
    }
  }
}
