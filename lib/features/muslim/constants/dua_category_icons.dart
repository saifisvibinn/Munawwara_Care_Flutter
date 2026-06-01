import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Material Symbols icon per UmmahAPI du'aa category id.
IconData duaCategoryIcon(String categoryId) {
  return switch (categoryId) {
    'hajj' => Symbols.mosque,
    'travel' => Symbols.flight,
    'masjid' => Symbols.mosque,
    'morning' => Symbols.light_mode,
    'evening' => Symbols.nights_stay,
    'protection' => Symbols.shield,
    'distress' => Symbols.self_improvement,
    'wudu' => Symbols.water_drop,
    'prayer' => Symbols.folded_hands,
    'after_prayer' => Symbols.volunteer_activism,
    'sleep' => Symbols.bedtime,
    'food' => Symbols.restaurant,
    'home' => Symbols.home,
    'forgiveness' => Symbols.favorite,
    'illness' => Symbols.healing,
    'weather' => Symbols.thunderstorm,
    'knowledge' => Symbols.menu_book,
    'parents' => Symbols.family_restroom,
    'guidance' => Symbols.explore,
    'gratitude' => Symbols.volunteer_activism,
    'dhikr' => Symbols.repeat,
    'marriage' => Symbols.favorite,
    'grief' => Symbols.sentiment_sad,
    'children' => Symbols.child_care,
    'business' => Symbols.work,
    'night_prayer' => Symbols.dark_mode,
    _ => Symbols.menu_book,
  };
}

/// Trip-relevant categories shown in the "For Hajj & Umrah" section.
const journeyDuaCategoryIds = [
  'hajj',
  'travel',
  'masjid',
  'protection',
  'distress',
  'morning',
  'evening',
];
