import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

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

class SocketService {
  static io.Socket? _socket;
  static String? _connectedUserId;

  /// Custom-event listeners (NOT for reserved socket.io events).
  static final Map<String, void Function(dynamic)> _pendingListeners = {};

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
      debugPrint(
        '[SocketService] Already connected as $userId – re-applying listeners',
      );
      _applyPendingListeners();
      return;
    }

    _socket?.dispose();
    _socket = null;
    _connectedUserId = userId;

    debugPrint('[SocketService] Connecting to $serverUrl as $userId ($role)');

    _socket = io.io(
      serverUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setReconnectionDelay(2000)
          .setReconnectionAttempts(20)
          .enableReconnection()
          .build(),
    );

    // ── Internal lifecycle handlers (set AFTER creating, BEFORE applying
    //    pending listeners so that off() in _apply never removes these). ──

    _socket!.onConnect((_) {
      debugPrint(
        '[SocketService] ✓ Connected (${_socket?.id}) – registering as $userId',
      );
      _socket!.emit('register-user', {'userId': userId, 'role': role});
      // Fire external connect callbacks
      for (final cb in _onConnectCallbacks) {
        try {
          cb();
        } catch (e) {
          debugPrint('[SocketService] onConnected callback error: $e');
        }
      }
    });

    _socket!.onDisconnect((_) {
      debugPrint('[SocketService] Disconnected');
    });

    _socket!.onConnectError((err) {
      debugPrint('[SocketService] Connection error: $err');
    });

    _socket!.onError((err) {
      debugPrint('[SocketService] Socket error: $err');
    });

    _socket!.on('reconnect', (_) {
      debugPrint('[SocketService] Reconnected – re-registering as $userId');
      _socket!.emit('register-user', {'userId': userId, 'role': role});
      for (final cb in _onConnectCallbacks) {
        try {
          cb();
        } catch (e) {
          debugPrint('[SocketService] onConnected callback error: $e');
        }
      }
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
      debugPrint(
        '[SocketService] ⚠ "$event" is reserved – use onConnected() instead',
      );
      return; // silently ignore to avoid breaking the internal handshake
    }
    _pendingListeners[event] = handler;
    if (_socket != null) {
      _socket!.off(event);
      _socket!.on(event, handler);
      debugPrint('[SocketService] Listener registered: $event');
    }
  }

  static void off(String event) {
    if (_reserved.contains(event)) return;
    _pendingListeners.remove(event);
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
    for (final entry in _pendingListeners.entries) {
      _socket!.off(entry.key);
      _socket!.on(entry.key, entry.value);
      debugPrint('[SocketService] Applied pending listener: ${entry.key}');
    }
  }
}
