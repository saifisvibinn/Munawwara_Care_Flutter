import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/socket_service.dart';

class ConnectivityNotifier extends Notifier<bool> {
  @override
  bool build() {
    SocketService.onConnected(_onConnected);
    SocketService.onDisconnected(_onDisconnected);
    ref.onDispose(() {
      SocketService.offConnected(_onConnected);
      SocketService.offDisconnected(_onDisconnected);
    });
    return SocketService.isConnected;
  }

  void _onConnected() => state = true;
  void _onDisconnected() => state = false;
}

final connectivityProvider = NotifierProvider<ConnectivityNotifier, bool>(
  ConnectivityNotifier.new,
);
