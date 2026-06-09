import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../data/dua_i18n_repository.dart';
import '../models/muslim_models.dart';
import '../services/ummah_api_service.dart';
import '../../../core/services/app_data_cache.dart';
import '../../../core/services/secure_session_store.dart';

final ummahDioProvider = Provider<Dio>((ref) {
  final apiKey = dotenv.env['UMMAH_API_KEY']?.trim() ?? '';
  return Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: {
        'Accept': 'application/json',
        if (apiKey.isNotEmpty) 'X-API-Key': apiKey,
      },
    ),
  );
});

final ummahApiServiceProvider = Provider<UmmahApiService>((ref) {
  return UmmahApiService(ref.watch(ummahDioProvider));
});

/// Loads [assets/muslim/dua_i18n.json] for localized du'a/azkār titles and sources.
final duaI18nReadyProvider = FutureProvider<void>((ref) async {
  await DuaI18nRepository.load();
});

/// Device coordinates for UmmahAPI calls (Mecca fallback when GPS unavailable).
final muslimLocationProvider =
    FutureProvider<(double lat, double lng)>((ref) async {
  const fallbackLat = 21.4225;
  const fallbackLng = 39.8262;

  final enabled = await Geolocator.isLocationServiceEnabled();
  if (!enabled) return (fallbackLat, fallbackLng);

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    return (fallbackLat, fallbackLng);
  }

  try {
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 8),
      ),
    );
    return (pos.latitude, pos.longitude);
  } catch (_) {
    final last = await Geolocator.getLastKnownPosition();
    if (last != null) return (last.latitude, last.longitude);
    return (fallbackLat, fallbackLng);
  }
});

class PrayerBundle {
  const PrayerBundle({
    required this.prayerTimes,
    required this.hijri,
  });

  final PrayerTimesData prayerTimes;
  final TodayHijriData hijri;
}

final prayerBundleProvider = FutureProvider<PrayerBundle>((ref) async {
  final api = ref.watch(ummahApiServiceProvider);
  final (lat, lng) = await ref.watch(muslimLocationProvider.future);
  final results = await Future.wait([
    api.fetchPrayerTimes(lat: lat, lng: lng),
    api.fetchTodayHijri(),
  ]);
  return PrayerBundle(
    prayerTimes: results[0] as PrayerTimesData,
    hijri: results[1] as TodayHijriData,
  );
});

/// Live countdown derived from [PrayerBundle].
final prayerCountdownProvider =
    NotifierProvider<PrayerCountdownNotifier, int?>(PrayerCountdownNotifier.new);

class PrayerCountdownNotifier extends Notifier<int?> {
  Timer? _timer;

  @override
  int? build() {
    ref.onDispose(() => _timer?.cancel());
    final bundle = ref.watch(prayerBundleProvider);
    bundle.whenData(_syncFromBundle);
    ref.listen(prayerBundleProvider, (prev, next) {
      next.whenData(_syncFromBundle);
    });
    return null;
  }

  void _syncFromBundle(PrayerBundle bundle) {
    _timer?.cancel();
    state = bundle.prayerTimes.currentStatus.minutesUntilNext;
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      final current = state;
      if (current == null) return;
      if (current <= 0) {
        ref.invalidate(prayerBundleProvider);
        return;
      }
      state = current - 1;
    });
  }
}

enum AzkarPeriod { morning, evening }

final azkarPeriodProvider =
    NotifierProvider<AzkarPeriodNotifier, AzkarPeriod>(AzkarPeriodNotifier.new);

class AzkarPeriodNotifier extends Notifier<AzkarPeriod> {
  @override
  AzkarPeriod build() => AzkarPeriod.morning;

  void setPeriod(AzkarPeriod period) => state = period;
}

final azkarDuasProvider = FutureProvider<List<DuaItem>>((ref) async {
  final period = ref.watch(azkarPeriodProvider);
  final category = period == AzkarPeriod.morning ? 'morning' : 'evening';
  return ref.watch(ummahApiServiceProvider).fetchDuasByCategory(category);
});

const priorityDuaCategoryIds = [
  'hajj',
  'travel',
  'morning',
  'evening',
  'masjid',
  'protection',
  'distress',
];

final duaCategoriesProvider = FutureProvider<List<DuaCategory>>((ref) async {
  final all = await ref.watch(ummahApiServiceProvider).fetchDuaCategories();
  final priority = <DuaCategory>[];
  final rest = <DuaCategory>[];
  for (final cat in all) {
    if (priorityDuaCategoryIds.contains(cat.id)) {
      priority.add(cat);
    } else {
      rest.add(cat);
    }
  }
  priority.sort((a, b) => priorityDuaCategoryIds
      .indexOf(a.id)
      .compareTo(priorityDuaCategoryIds.indexOf(b.id)));
  return [...priority, ...rest];
});

final duaCategoryItemsProvider =
    FutureProvider.family<List<DuaItem>, String>((ref, categoryId) {
  return ref.watch(ummahApiServiceProvider).fetchDuasByCategory(categoryId);
});


final asmaUlHusnaProvider = FutureProvider<List<AsmaName>>((ref) async {
  final uid = await SecureSessionStore.getUserId() ?? 'global';
  try {
    final cachedData = await AppDataCache.readData(uid, AppDataCache.asmaUlHusnaFile);
    if (cachedData is List) {
      final cachedList = cachedData
          .whereType<Map<String, dynamic>>()
          .map(AsmaName.fromJson)
          .toList();
      if (cachedList.isNotEmpty) {
        return cachedList;
      }
    }
  } catch (_) {}

  final names = await ref.read(ummahApiServiceProvider).fetchAsmaUlHusna();
  await AppDataCache.write(
    uid,
    AppDataCache.asmaUlHusnaFile,
    names.map((e) => e.toJson()).toList(),
  );
  return names;
});

final asmaSearchQueryProvider =
    NotifierProvider<AsmaSearchQueryNotifier, String>(AsmaSearchQueryNotifier.new);

class AsmaSearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String value) => state = value;
}

final asmaSearchResultsProvider = FutureProvider<List<AsmaName>>((ref) async {
  final query = ref.watch(asmaSearchQueryProvider).trim().toLowerCase();
  final allNames = await ref.watch(asmaUlHusnaProvider.future);
  if (query.isEmpty) {
    return allNames;
  }
  return allNames.where((name) {
    final translit = name.transliteration.toLowerCase();
    final meaning = name.meaning.toLowerCase();
    final arabic = name.nameArabic.toLowerCase();
    return translit.contains(query) ||
        meaning.contains(query) ||
        arabic.contains(query);
  }).toList();
});

/// Per-card tap counters for azkar / du'aa (keyed by dua id + category).
final duaTapCounterProvider =
    NotifierProvider<DuaTapCounterNotifier, Map<String, int>>(DuaTapCounterNotifier.new);

class DuaTapCounterNotifier extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() => {};

  String _key(DuaItem item) => '${item.category}_${item.id}';

  int remaining(DuaItem item) {
    final key = _key(item);
    return state[key] ?? item.repeat;
  }

  void tap(DuaItem item) {
    final key = _key(item);
    final current = state[key] ?? item.repeat;
    if (current <= 0) return;
    state = {...state, key: current - 1};
  }

  void reset(DuaItem item) {
    final key = _key(item);
    final next = Map<String, int>.from(state)..remove(key);
    state = next;
  }
}
