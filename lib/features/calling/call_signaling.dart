import '../../core/services/api_service.dart';
import '../../core/services/socket_service.dart';
import '../../core/utils/app_logger.dart';

/// Socket + HTTP fallbacks for voice-call signaling (kept out of [CallNotifier]
/// so the notifier stays focused on state + Agora).
class CallSignaling {
  CallSignaling._();

  static final Map<String, Map<String, dynamic>> _pendingEmitPayloads = {};
  static final Map<String, void Function()> _pendingEmitCallbacks = {};

  /// Emit when the socket is up; coalesce one pending payload per [event] so
  /// rapid cancel/recall does not flush a burst of stale offers on reconnect.
  static void emitWhenConnected(String event, Map<String, dynamic> payload) {
    if (SocketService.isConnected) {
      _clearPendingEmit(event);
      SocketService.emit(event, payload);
      AppLogger.w(
        '[CallSignaling] Emitted "$event" (connected) payload=$payload',
      );
      return;
    }

    AppLogger.w(
      '[CallSignaling] Socket not connected, queueing "$event" '
      'payload=$payload',
    );
    _pendingEmitPayloads[event] = payload;
    if (_pendingEmitCallbacks.containsKey(event)) {
      return;
    }

    void sendOnce() {
      final pending = _pendingEmitPayloads.remove(event);
      _pendingEmitCallbacks.remove(event);
      SocketService.offConnected(sendOnce);
      if (pending != null) {
        SocketService.emit(event, pending);
        AppLogger.i(
          '[CallSignaling] Queued "$event" emit sent after reconnect',
        );
      }
    }

    _pendingEmitCallbacks[event] = sendOnce;
    SocketService.onConnected(sendOnce);
  }

  static void _clearPendingEmit(String event) {
    _pendingEmitPayloads.remove(event);
    final cb = _pendingEmitCallbacks.remove(event);
    if (cb != null) {
      SocketService.offConnected(cb);
    }
  }

  /// Drop queued signaling for a new outgoing attempt (cancel/recall spam).
  static void clearPendingOutgoingEmits() {
    for (final event in [
      'call-offer',
      'call-offer-group',
      'call-cancel',
      'group-call-cancel',
    ]) {
      _clearPendingEmit(event);
    }
  }

  /// HTTP fallback when socket is not up (cold start / background).
  static Future<void> notifyAnswerHttp(
    String callerId,
    String? answererId,
  ) async {
    try {
      await ApiService.dio.post(
        '/call-history/answer',
        data: {'callerId': callerId, 'answererId': answererId ?? ''},
      );
      AppLogger.i('[CallSignaling] HTTP call-answer → $callerId');
    } catch (e) {
      AppLogger.e('[CallSignaling] HTTP call-answer failed: $e');
      rethrow;
    }
  }

  static Future<void> notifyDeclineHttp(
    String callerId,
    String? declinerId, {
    String? callRecordId,
    bool noAnswer = false,
  }) async {
    await ApiService.dio.post(
      '/call-history/decline',
      data: {
        'callerId': callerId,
        'declinerId': declinerId ?? '',
        if (callRecordId != null && callRecordId.isNotEmpty)
          'callRecordId': callRecordId,
        if (noAnswer) 'noAnswer': true,
      },
    );
    AppLogger.i('[CallSignaling] HTTP call-decline → $callerId');
  }

  static Future<void> notifyCancelHttp(
    String callerId, {
    String? receiverId,
    String? callRecordId,
  }) async {
    final data = <String, dynamic>{
      'callerId': callerId,
      if (receiverId != null && receiverId.isNotEmpty) 'receiverId': receiverId,
      if (callRecordId != null && callRecordId.isNotEmpty)
        'callRecordId': callRecordId,
    };
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await ApiService.dio.post('/call-history/cancel', data: data);
        AppLogger.i(
          '[CallSignaling] HTTP call-cancel OK caller=$callerId '
          'receiver=${receiverId ?? "ALL_RINGING"} '
          'record=${callRecordId ?? ""}',
        );
        return;
      } catch (e) {
        lastError = e;
        AppLogger.e(
          '[CallSignaling] HTTP call-cancel attempt ${attempt + 1} failed: $e',
        );
        if (attempt < 2) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
      }
    }
    AppLogger.e('[CallSignaling] HTTP call-cancel gave up: $lastError');
  }

  /// Places outgoing 1:1 call on the server.
  ///
  /// [preferHttpOnly] — pilgrim SOS callback: always REST (socket may be ghost).
  /// Otherwise socket when connected, REST when not.
  static Future<String?> placeOutgoingOffer({
    required String remoteUserId,
    required String channelName,
    bool preferHttpOnly = false,
  }) async {
    Future<String?> offerViaHttp() async {
      try {
        final resp = await ApiService.dio.post(
          '/call-history/offer',
          data: {
            'to': remoteUserId,
            'channelName': channelName,
          },
        );
        final recordId = resp.data != null && resp.data is Map
            ? resp.data['callRecordId']?.toString()
            : null;
        AppLogger.i(
          '[CallSignaling] HTTP call-offer OK → $remoteUserId ($channelName) recordId=$recordId',
        );
        return recordId ?? "http_success";
      } catch (e) {
        AppLogger.e('[CallSignaling] HTTP call-offer failed: $e');
        return null;
      }
    }

    if (preferHttpOnly) {
      return offerViaHttp();
    }
    if (!SocketService.isConnected) {
      return offerViaHttp();
    }
    emitWhenConnected('call-offer', {
      'to': remoteUserId,
      'channelName': channelName,
    });
    return "socket";
  }

  static Future<void> notifyGroupCancelHttp(
    String callerId, {
    String? callRecordId,
  }) async {
    try {
      await ApiService.dio.post(
        '/call-history/cancel',
        data: {
          'callerId': callerId,
          'groupCancel': true,
          if (callRecordId != null && callRecordId.isNotEmpty)
            'callRecordId': callRecordId,
        },
      );
      AppLogger.i('[CallSignaling] HTTP group-call-cancel');
    } catch (e) {
      AppLogger.e('[CallSignaling] HTTP group-call-cancel failed: $e');
    }
  }
}
