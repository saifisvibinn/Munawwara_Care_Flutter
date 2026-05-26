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
// ─────────────────────────────────────────────────────────────────────────────

/// Handler for server events that require an acknowledgement (e.g. call-offer).
typedef SocketAckHandler = void Function(
  dynamic data,
  void Function([dynamic response])? ack,
);

class SocketService {
  static io.Socket? _socket;
  static String? _connectedUserId;

  /// Custom-event listeners (NOT for reserved socket.io events).
  static final Map<String, void Function(dynamic)> _pendingListeners = {};

  /// Events where the server expects an ACK (socket_io_client appends ack last).
  static final Map<String, SocketAckHandler> _pendingAckListeners = {};

  /// Callbacks that fire every time the socket connects / reconnects.
  /// Use [onConnected] / [offConnected] to manage these.
  static final List<void Function()> _onConnectCallbacks = [];

  /// Callbacks that fire every time the socket disconnects.
  /// Use [onDisconnected] / [offDisconnected] to manage these.
  static final List<void Function()> _onDisconnectCallbacks = [];

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
    _connectedUserId = userId;

    // Clean URL: remove trailing slashes if present
    final cleanUrl = serverUrl.endsWith('/') 
        ? serverUrl.substring(0, serverUrl.length - 1) 
        : serverUrl;

    AppLogger.w(
      '[SocketService] Connecting to $cleanUrl as $userId ($role)',
    );

    _socket = io.io(
      cleanUrl,
      io.OptionBuilder()
          // Try websocket first; polling helps some proxies / Cloud setups.
          .setTransports(['websocket', 'polling'])
          .setReconnectionDelay(2000)
          .setReconnectionAttempts(20)
          .enableReconnection()
          .build(),
    );

    // ── Internal lifecycle handlers (set AFTER creating, BEFORE applying
    //    pending listeners so that off() in _apply never removes these). ──

    _socket!.onConnect((_) {
      AppLogger.w(
        '[SocketService] Connected socketId=${_socket?.id} url=$cleanUrl '
        'userId=$userId role=$role',
      );
      _socket!.emit('register-user', {'userId': userId, 'role': role});
      // Fire external connect callbacks (iterate a copy so callbacks can
      // safely remove themselves via offConnected() without crashing)
      for (final cb in List.of(_onConnectCallbacks)) {
        try {
          cb();
        } catch (e) {
          AppLogger.d('[SocketService] onConnected callback error: $e');
        }
      }
    });

    _socket!.onDisconnect((_) {
      AppLogger.d('[SocketService] Disconnected');
      for (final cb in List.of(_onDisconnectCallbacks)) {
        try {
          cb();
        } catch (e) {
          AppLogger.d('[SocketService] onDisconnected callback error: $e');
        }
      }
    });

    _socket!.onConnectError((err) {
      AppLogger.w('[SocketService] Connection error ($cleanUrl): $err');
    });

    _socket!.onError((err) {
      AppLogger.w('[SocketService] Socket error ($cleanUrl): $err');
    });

    // Apply custom-event listeners that were registered before connect().
    _applyPendingListeners();
  }

  // ── Emit ──────────────────────────────────────────────────────────────────
  static void emit(String event, dynamic data) {
    _socket?.emit(event, data);
  }

  // ── Custom-event listen / unlisten ────────────────────────────────────────
  /// Register a handler for a **custom** event (not connect/disconnect/etc.).
  static void on(String event, void Function(dynamic) handler) {
    if (_reserved.contains(event)) {
      AppLogger.d(
        '[SocketService] ⚠ "$event" is reserved – use onConnected() instead',
      );
      return; // silently ignore to avoid breaking the internal handshake
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
      _socket!.on(event, _wrapAckHandler(handler));
    }
  }

  static void off(String event) {
    if (_reserved.contains(event)) return;
    _pendingListeners.remove(event);
    _pendingAckListeners.remove(event);
    _socket?.off(event);
  }

  // ── Connect / reconnect callbacks ─────────────────────────────────────────
  /// Register a callback that fires every time the socket (re-)connects,
  /// **after** the register-user handshake has been sent.
  static void onConnected(void Function() callback) {
    if (!_onConnectCallbacks.contains(callback)) {
      _onConnectCallbacks.add(callback);
    }
  }

  /// Remove a previously registered connect callback.
  static void offConnected(void Function() callback) {
    _onConnectCallbacks.remove(callback);
  }

  /// Register a callback that fires every time the socket disconnects.
  static void onDisconnected(void Function() callback) {
    if (!_onDisconnectCallbacks.contains(callback)) {
      _onDisconnectCallbacks.add(callback);
    }
  }

  /// Remove a previously registered disconnect callback.
  static void offDisconnected(void Function() callback) {
    _onDisconnectCallbacks.remove(callback);
  }

  // ── State ─────────────────────────────────────────────────────────────────
  static bool get isConnected => _socket?.connected ?? false;
  static String? get connectedUserId => _connectedUserId;

  // ── Disconnect ────────────────────────────────────────────────────────────
  static void disconnect() {
    _socket?.dispose();
    _socket = null;
    _connectedUserId = null;
  }

  // ── Internal ──────────────────────────────────────────────────────────────
  static void _applyPendingListeners() {
    if (_socket == null) return;
    final ackEvents = _pendingAckListeners.keys.toSet();
    for (final entry in _pendingListeners.entries) {
      if (ackEvents.contains(entry.key)) continue;
      _socket!.off(entry.key);
      _socket!.on(entry.key, entry.value);
    }
    for (final entry in _pendingAckListeners.entries) {
      _socket!.off(entry.key);
      _socket!.on(entry.key, _wrapAckHandler(entry.value));
    }
  }

  static void Function(dynamic, [dynamic]) _wrapAckHandler(
    SocketAckHandler handler,
  ) {
    return (dynamic arg1, [dynamic arg2]) {
      dynamic data = arg1;
      void Function([dynamic])? ack;

      if (arg2 is Function) {
        ack = arg2 as void Function([dynamic]);
      } else if (arg1 is List && arg1.isNotEmpty && arg1.last is Function) {
        final list = List<dynamic>.from(arg1);
        ack = list.removeLast() as void Function([dynamic]);
        data = list.length == 1 ? list.first : list;
      }

      handler(data, ack);
    };
  }
}
