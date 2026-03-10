import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../features/shared/models/message_model.dart';
import '../../features/shared/providers/message_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AudioPlaybackMixin
//
// Eliminates copy-paste of AudioPlayer + FlutterTts boilerplate across
// GroupInboxScreen, GroupMessagesScreen (and formerly IndividualMessagesScreen).
//
// Usage:
//   class _MyScreenState extends ConsumerState<MyScreen>
//       with AudioPlaybackMixin<MyScreen> {
//
//     @override void initState() {
//       super.initState();
//       initAudioListeners();   // <-- sets up player/TTS callbacks
//       ...
//     }
//
//     @override void dispose() {
//       disposeAudio();          // <-- stops & disposes player/TTS
//       super.dispose();
//     }
//   }
// ─────────────────────────────────────────────────────────────────────────────

mixin AudioPlaybackMixin<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  // ── Shared state ───────────────────────────────────────────────────────────
  final audioPlayer = AudioPlayer();
  final tts = FlutterTts();

  String? playingId; // message id, or '_preview' for local recording preview
  Duration audioPosition = Duration.zero;
  Duration audioDuration = Duration.zero;

  String? ttsPlayingId;
  bool ttsSpeaking = false;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Call from initState to wire up audio and TTS event listeners.
  void initAudioListeners() {
    audioPlayer.onPositionChanged.listen((p) {
      if (mounted) setState(() => audioPosition = p);
    });
    audioPlayer.onDurationChanged.listen((d) {
      if (mounted) setState(() => audioDuration = d);
    });
    audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          playingId = null;
          audioPosition = Duration.zero;
        });
      }
    });

    tts.setCompletionHandler(() {
      if (mounted) {
        setState(() {
          ttsSpeaking = false;
          ttsPlayingId = null;
        });
      }
    });
    tts.setErrorHandler((_) {
      if (mounted) {
        setState(() {
          ttsSpeaking = false;
          ttsPlayingId = null;
        });
      }
    });
  }

  /// Call from dispose to stop and release audio/TTS resources.
  void disposeAudio() {
    audioPlayer.dispose();
    tts.stop();
  }

  // ── Playback helpers ───────────────────────────────────────────────────────

  /// Toggle playback of a voice message. If already playing that message,
  /// pause; otherwise stop any TTS that's running and start playing.
  Future<void> toggleVoice(GroupMessage msg) async {
    if (msg.mediaUrl == null) return;
    if (playingId == msg.id) {
      await audioPlayer.pause();
      setState(() => playingId = null);
      return;
    }
    if (ttsPlayingId != null) {
      await tts.stop();
      setState(() {
        ttsSpeaking = false;
        ttsPlayingId = null;
      });
    }
    setState(() {
      playingId = msg.id;
      audioPosition = Duration.zero;
    });
    final url = ref.read(messageProvider.notifier).buildUploadUrl(msg.mediaUrl!);
    await audioPlayer.play(UrlSource(url));
  }

  /// Toggle TTS playback of a text/TTS message.
  Future<void> toggleTts(GroupMessage msg) async {
    final text = msg.originalText ?? msg.content ?? '';
    if (ttsPlayingId == msg.id && ttsSpeaking) {
      await tts.stop();
      setState(() {
        ttsSpeaking = false;
        ttsPlayingId = null;
      });
      return;
    }
    if (playingId != null) {
      await audioPlayer.stop();
      setState(() {
        playingId = null;
        audioPosition = Duration.zero;
      });
    }
    await tts.stop();
    setState(() {
      ttsPlayingId = msg.id;
      ttsSpeaking = true;
    });
    await tts.speak(text);
  }
}
