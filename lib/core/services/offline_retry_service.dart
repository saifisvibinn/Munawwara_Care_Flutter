import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'api_service.dart';
import 'app_data_cache.dart';
import 'secure_session_store.dart';
import 'socket_service.dart';
import '../../features/shared/providers/message_provider.dart';
import '../../features/shared/models/message_model.dart';
import '../../features/pilgrim/providers/pilgrim_provider.dart';
import '../utils/app_logger.dart';

class PendingAction {
  final String id;
  final String type; // 'send_message' | 'send_individual_message'
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  PendingAction({
    required this.id,
    required this.type,
    required this.payload,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'payload': payload,
        'createdAt': createdAt.toIso8601String(),
      };

  factory PendingAction.fromJson(Map<String, dynamic> json) => PendingAction(
        id: json['id']?.toString() ?? const Uuid().v4(),
        type: json['type']?.toString() ?? '',
        payload: Map<String, dynamic>.from(json['payload'] ?? {}),
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now(),
      );
}

class OfflineRetryService {
  final Ref _ref;
  bool _isProcessing = false;

  OfflineRetryService(this._ref) {
    // Automatically trigger queue processing on socket reconnection
    SocketService.onConnected(_onSocketConnected);
  }

  void dispose() {
    SocketService.offConnected(_onSocketConnected);
  }

  void _onSocketConnected() {
    AppLogger.d('[OfflineRetryService] Socket connected, processing queue...');
    processQueue();
  }

  Future<String?> _getUserId() async => await SecureSessionStore.getUserId();

  /// Loads the pending actions queue for the current logged-in user.
  Future<List<PendingAction>> loadQueue() async {
    final uid = await _getUserId();
    if (uid == null || uid.isEmpty) return [];

    try {
      final raw = await AppDataCache.readData(uid, AppDataCache.pendingActionsFile);
      if (raw == null) return [];

      if (raw is List) {
        return raw
            .map((item) => PendingAction.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
      }
    } catch (e) {
      AppLogger.w('[OfflineRetryService] Error loading queue: $e');
    }
    return [];
  }

  /// Writes the pending actions queue back to local cache.
  Future<void> _saveQueue(List<PendingAction> queue) async {
    final uid = await _getUserId();
    if (uid == null || uid.isEmpty) return;

    try {
      final list = queue.map((e) => e.toJson()).toList();
      await AppDataCache.write(uid, AppDataCache.pendingActionsFile, list);
    } catch (e) {
      AppLogger.w('[OfflineRetryService] Error saving queue: $e');
    }
  }

  /// Appends a new action to the queue.
  Future<void> enqueueAction({
    required String type,
    required Map<String, dynamic> payload,
    String? actionId,
  }) async {
    final queue = await loadQueue();
    final id = actionId ?? const Uuid().v4();
    final action = PendingAction(
      id: id,
      type: type,
      payload: payload,
      createdAt: DateTime.now(),
    );

    // Prevent duplicate actions with same ID
    if (queue.any((element) => element.id == id)) return;

    queue.add(action);
    await _saveQueue(queue);
    AppLogger.d('[OfflineRetryService] Enqueued offline action: $type ($id)');

    // Attempt processing in case connection is immediately available
    processQueue();
  }

  /// Removes an action from the queue.
  Future<void> dequeueAction(String actionId) async {
    final queue = await loadQueue();
    queue.removeWhere((item) => item.id == actionId);
    await _saveQueue(queue);
  }

  /// Attempts to cancel a pending trigger_sos action in the queue.
  /// Returns true if it was found and removed.
  Future<bool> cancelPendingSos(String? tempSosId) async {
    if (tempSosId == null || tempSosId.isEmpty) return false;
    final queue = await loadQueue();
    final initialLength = queue.length;
    queue.removeWhere((item) => item.type == 'trigger_sos' && item.payload['temp_sos_id'] == tempSosId);
    if (queue.length < initialLength) {
      await _saveQueue(queue);
      AppLogger.d('[OfflineRetryService] Cancelled pending SOS trigger locally: $tempSosId');
      return true;
    }
    return false;
  }

  /// Iterates and processes the pending actions queue sequentially.
  Future<void> processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final queue = await loadQueue();
      if (queue.isEmpty) {
        _isProcessing = false;
        return;
      }

      AppLogger.w('[OfflineRetryService] Starting queue flush: ${queue.length} items');

      final failedActions = <String>{};

      for (final action in List<PendingAction>.from(queue)) {
        // If we failed this action type recently or are offline, skip the rest of the queue
        if (failedActions.contains(action.type)) {
          AppLogger.d('[OfflineRetryService] Skipping action due to previous failure of type ${action.type}');
          continue;
        }

        final success = await _dispatchAction(action);
        if (success) {
          await dequeueAction(action.id);
          AppLogger.d('[OfflineRetryService] Successfully processed and dequeued action ${action.id}');
        } else {
          // Flag this action type to stop subsequent items of this type from executing in this cycle
          failedActions.add(action.type);
          AppLogger.w('[OfflineRetryService] Action ${action.id} failed. Postponing queue processing.');
        }
      }
    } catch (e) {
      AppLogger.e('[OfflineRetryService] Critical error processing queue', e);
    } finally {
      _isProcessing = false;
    }
  }

  /// Sends the actual network request for a given PendingAction.
  Future<bool> _dispatchAction(PendingAction action) async {
    final payload = action.payload;

    try {
      if (action.type == 'send_message') {
        final String groupId = payload['group_id']?.toString() ?? '';
        final String type = payload['type']?.toString() ?? 'text';
        final String content = payload['content']?.toString() ?? '';
        final bool isUrgent = payload['is_urgent'] == true;
        final String? clientMessageId = payload['client_message_id']?.toString();
        final String? replyTo = payload['reply_to']?.toString();

        dynamic requestData;
        Options options = Options(
          receiveTimeout: const Duration(seconds: 90),
        );

        if (type == 'voice') {
          final String filePath = payload['file_path']?.toString() ?? '';
          final int duration = int.tryParse(payload['duration']?.toString() ?? '0') ?? 0;

          requestData = FormData.fromMap({
            'group_id': groupId,
            'type': 'voice',
            'is_urgent': isUrgent.toString(),
            'duration': duration.toString(),
            if (replyTo != null && replyTo.isNotEmpty) 'reply_to': replyTo,
            'client_message_id': ?clientMessageId,
            'file': await MultipartFile.fromFile(
              filePath,
              filename: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
            ),
          });
        } else {
          requestData = {
            'group_id': groupId,
            'type': type,
            'content': content,
            if (type == 'tts') 'original_text': content,
            'is_urgent': isUrgent,
            if (replyTo != null && replyTo.isNotEmpty) 'reply_to': replyTo,
            'client_message_id': ?clientMessageId,
          };
        }

        final response = await ApiService.dio.post(
          '/messages',
          data: requestData,
          options: options,
        );

        final returnedMsg = GroupMessage.fromJson(response.data['data'] as Map<String, dynamic>);
        
        // Notify MessageNotifier of successful background send
        _ref.read(messageProvider.notifier).onQueuedMessageSent(clientMessageId ?? action.id, returnedMsg);
        return true;
      } else if (action.type == 'send_individual_message') {
        final String groupId = payload['group_id']?.toString() ?? '';
        final String recipientId = payload['recipient_id']?.toString() ?? '';
        final String type = payload['type']?.toString() ?? 'text';
        final String content = payload['content']?.toString() ?? '';
        final bool isUrgent = payload['is_urgent'] == true;
        final String? clientMessageId = payload['client_message_id']?.toString();
        final String? replyTo = payload['reply_to']?.toString();

        dynamic requestData;
        Options options = Options(
          receiveTimeout: const Duration(seconds: 90),
        );

        if (type == 'voice') {
          final String filePath = payload['file_path']?.toString() ?? '';
          final int duration = int.tryParse(payload['duration']?.toString() ?? '0') ?? 0;

          requestData = FormData.fromMap({
            'group_id': groupId,
            'recipient_id': recipientId,
            'type': 'voice',
            'is_urgent': isUrgent.toString(),
            'duration': duration.toString(),
            if (replyTo != null && replyTo.isNotEmpty) 'reply_to': replyTo,
            'client_message_id': ?clientMessageId,
            'file': await MultipartFile.fromFile(
              filePath,
              filename: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
            ),
          });
        } else {
          requestData = {
            'group_id': groupId,
            'recipient_id': recipientId,
            'type': type,
            'content': content,
            if (type == 'tts') 'original_text': content,
            'is_urgent': isUrgent,
            if (replyTo != null && replyTo.isNotEmpty) 'reply_to': replyTo,
            'client_message_id': ?clientMessageId,
          };
        }

        final response = await ApiService.dio.post(
          '/messages/individual',
          data: requestData,
          options: options,
        );

        final returnedMsg = GroupMessage.fromJson(response.data['data'] as Map<String, dynamic>);
        
        // Notify MessageNotifier of successful background send
        _ref.read(messageProvider.notifier).onQueuedMessageSent(clientMessageId ?? action.id, returnedMsg);
        return true;
      } else if (action.type == 'trigger_sos') {
        final String tempSosId = payload['temp_sos_id']?.toString() ?? action.id;
        AppLogger.d('[OfflineRetryService] Processing offline SOS trigger: $tempSosId');
        try {
          final response = await ApiService.dio.post('/pilgrim/sos');
          final body = response.data as Map<String, dynamic>?;
          final realSosId = body?['sos_id']?.toString() ??
              body?['data']?['sos_id']?.toString();
          if (realSosId != null) {
            _ref.read(pilgrimProvider.notifier).updateActiveSosId(realSosId);
          }
          return true;
        } on DioException catch (e) {
          if (e.response?.statusCode == 409) {
            try {
              final profileRes = await ApiService.dio.get('/pilgrim/profile');
              final profileData = profileRes.data as Map<String, dynamic>?;
              final realSosId = profileData?['active_sos_id']?.toString();
              if (realSosId != null && realSosId.isNotEmpty) {
                _ref.read(pilgrimProvider.notifier).updateActiveSosId(realSosId);
              }
              return true;
            } catch (_) {
              return false;
            }
          }
          if (ApiService.isOfflineFailure(e)) return false;
          return true;
        } catch (_) {
          return false;
        }
      } else if (action.type == 'cancel_sos') {
        final String? sosId = payload['sos_id']?.toString();
        try {
          final requestPayload = <String, dynamic>{};
          if (sosId != null && sosId.isNotEmpty) {
            requestPayload['sos_id'] = sosId;
          }
          await ApiService.dio.post('/pilgrim/sos/cancel', data: requestPayload);
          return true;
        } on DioException catch (e) {
          if (ApiService.isOfflineFailure(e)) return false;
          return true;
        } catch (_) {
          return false;
        }
      } else if (action.type == 'update_location') {
        final double? lat = double.tryParse(payload['latitude']?.toString() ?? '');
        final double? lng = double.tryParse(payload['longitude']?.toString() ?? '');
        final int? batteryPercent = int.tryParse(payload['battery_percent']?.toString() ?? '');
        if (lat == null || lng == null) return true;
        try {
          await ApiService.dio.put(
            '/pilgrim/location',
            data: {
              'latitude': lat,
              'longitude': lng,
              'battery_percent': ?batteryPercent,
            },
          );
          return true;
        } on DioException catch (e) {
          if (ApiService.isOfflineFailure(e)) return false;
          return true;
        } catch (_) {
          return false;
        }
      }
    } on DioException catch (e) {
      if (ApiService.isOfflineFailure(e)) {
        AppLogger.d('[OfflineRetryService] Offline failure when dispatching action ${action.id}');
        return false;
      }

      // If it's a server/validation error (e.g. 400, 403, 404), keeping the action
      // in the queue will block all future messages. We should discard it and log the error.
      AppLogger.w('[OfflineRetryService] Non-recoverable error for action ${action.id} (${e.response?.statusCode}): ${e.message}');
      
      final clientMessageId = payload['client_message_id']?.toString() ?? action.id;
      _ref.read(messageProvider.notifier).onQueuedMessageFailed(clientMessageId);
      return true; // Return true so it gets removed from the queue
    } catch (e) {
      AppLogger.e('[OfflineRetryService] Unknown error dispatching action ${action.id}', e);
      return false;
    }

    return false;
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final offlineRetryServiceProvider = Provider<OfflineRetryService>((ref) {
  final service = OfflineRetryService(ref);
  ref.onDispose(() => service.dispose());
  return service;
});
