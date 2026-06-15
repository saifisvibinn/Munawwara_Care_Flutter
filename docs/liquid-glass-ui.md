# Liquid Glass UI

Munawwara Care uses a Flutter approximation of Apple’s **Liquid Glass** material on primary dashboard tabs. This follows the same design intent described in Apple’s adoption guide:

[Adopting Liquid Glass — Apple Developer Documentation](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass)

## Package

- [`cupertino_liquid_glass`](https://pub.dev/packages/cupertino_liquid_glass) — real `BackdropFilter`, light/dark `LiquidGlassThemeData`, edge lighting, and noise grain.

## Shared widgets

All live under `lib/core/widgets/glass/` (barrel: `app_glass.dart`):

| Widget | Role |
|--------|------|
| `AppGlassTheme` | Blur sigma, corner radii, nav scroll padding |
| `AppScrollGlassEdge` | Blurred top/bottom scroll-edge bands (`BackdropFilter` + tint) |
| `AppScrollFadeOverlay` | Wraps scroll/map content with top + bottom glass edges |
| `AppGlassSurface` | Single glass shell (`enableGlass` fallback) |
| `AppGlassCard` | Dashboard cards with optional watermark |
| `AppGlassIconButton` | 44pt header / toolbar circles |
| `AppGlassSearchField` | Moderator search + filter slot |
| `AppGlassPopupMenuAnchor` | Map/toolbar contextual menus (overlay blur, source-anchored) |
| `AppDashboardBackground` | Soft gradient mesh so blur reads over content |

Bottom navigation uses `AppLiquidGlassBottomBar` in `lib/core/widgets/app_liquid_glass_bottom_bar.dart` (custom glass shell + subtle selected pill; not the package's sliding selector).

## Apple HIG principles we apply

From [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass):

1. **Functional layer vs content** — Glass is reserved for navigation chrome (tab bar, headers, FABs, primary cards). Lists, form fields, and chat bubbles stay solid so content stays legible.
2. **Avoid overuse** — One glass layer per visual block; no nested glass-on-glass (e.g. hub outer shell only, flat inner tiles). Context menus use one glass shell with solid rows inside.
3. **Scroll separation** — Tab roots use `AppGlassTheme.bottomNavScrollPadding` (~72.h + safe area) so scroll content clears the floating bar. Top/bottom edges use `AppScrollFadeOverlay` → `AppScrollGlassEdge` (real blur over live content, not a solid fog gradient).
4. **Concentric radii** — 26.r surfaces aligned with the floating tab bar; popovers use `cardRadius` (24.r).
5. **Popovers** — `AppGlassPopupMenuAnchor` inserts into the overlay so blur samples live content; menu anchors to trigger per Apple's popover guidance (see Menus and toolbars / Windows and modals in the adoption guide).
6. **Accessibility / performance** — Pass `enableGlass: false` on `AppGlassSurface` or `AppScrollFadeOverlay` for reduced-transparency QA. On iOS maps, use `AppPlatformMap(iosNativeScrollEdges: true)` instead of a Flutter overlay (avoids `recreating_view` crashes).

## Scaffold requirement

Both pilgrim and moderator dashboards set `Scaffold.extendBody: true` so the floating glass tab bar overlays scroll content.

## Exceptions

| Area | Treatment |
|------|-----------|
| **Map tab** | Map stays full-bleed; on iOS, native `UIVisualEffectView` edge bands inside MapKit (`iosNativeScrollEdges`). Other screens use iOS-tuned `BackdropFilter` in `AppScrollGlassEdge`. |
| **Announcements / chat** | Glass on header and filter chrome; message bubbles remain solid |
| **Deep sub-screens** | Out of scope unless they reuse shared glass components |

## Tab coverage

**Pilgrim:** Home, Map (chrome), Muslim hub, Announcements inbox.

**Moderator:** Groups, Provisioning, Reminders, Profile.

## Verification checklist

- Glass blur visible when scrolling behind cards / nav and on map tab edges
- No SOS hub clipping on large iPhones (dynamic hub sizing on Home)
- All tabs navigable; badges unchanged
- Test light/dark mode and reduced motion / transparency settings where possible
