---
name: Sacred Path Utility
colors:
  surface: '#f7f9fb'
  surface-dim: '#d8dadc'
  surface-bright: '#f7f9fb'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f2f4f6'
  surface-container: '#eceef0'
  surface-container-high: '#e6e8ea'
  surface-container-highest: '#e0e3e5'
  on-surface: '#191c1e'
  on-surface-variant: '#42493e'
  inverse-surface: '#2d3133'
  inverse-on-surface: '#eff1f3'
  outline: '#72796e'
  outline-variant: '#c2c9bb'
  surface-tint: '#3b6934'
  primary: '#154212'
  on-primary: '#ffffff'
  primary-container: '#2d5a27'
  on-primary-container: '#9dd090'
  inverse-primary: '#a1d494'
  secondary: '#904d00'
  on-secondary: '#ffffff'
  secondary-container: '#fe932c'
  on-secondary-container: '#663500'
  tertiary: '#00328b'
  on-tertiary: '#ffffff'
  tertiary-container: '#0046bc'
  on-tertiary-container: '#aec1ff'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#bcf0ae'
  primary-fixed-dim: '#a1d494'
  on-primary-fixed: '#002201'
  on-primary-fixed-variant: '#23501e'
  secondary-fixed: '#ffdcc3'
  secondary-fixed-dim: '#ffb77d'
  on-secondary-fixed: '#2f1500'
  on-secondary-fixed-variant: '#6e3900'
  tertiary-fixed: '#dbe1ff'
  tertiary-fixed-dim: '#b4c5ff'
  on-tertiary-fixed: '#00174b'
  on-tertiary-fixed-variant: '#003ea8'
  background: '#f7f9fb'
  on-background: '#191c1e'
  surface-variant: '#e0e3e5'
typography:
  headline-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.02em
  headline-lg-mobile:
    fontFamily: Plus Jakarta Sans
    fontSize: 24px
    fontWeight: '700'
    lineHeight: 32px
    letterSpacing: -0.01em
  headline-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 28px
  body-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 18px
    fontWeight: '400'
    lineHeight: 28px
  body-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  label-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 14px
    fontWeight: '600'
    lineHeight: 20px
    letterSpacing: 0.01em
  label-sm:
    fontFamily: Plus Jakarta Sans
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
    letterSpacing: 0.05em
  countdown-num:
    fontFamily: Plus Jakarta Sans
    fontSize: 14px
    fontWeight: '700'
    lineHeight: 14px
    letterSpacing: 0.02em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  base: 8px
  xs: 4px
  sm: 12px
  md: 24px
  lg: 40px
  container-margin: 20px
  gutter: 16px
---

## Brand & Style
The brand personality is serene, purposeful, and spiritually grounded. It aims to evoke a sense of "digital tranquility"—providing utility without distraction. The target audience seeks a companion for their daily spiritual obligations that feels both contemporary and deeply rooted in tradition.

The design style is **Minimalist-Modern with Subtle Ornamentation**. It utilizes heavy whitespace and high-quality typography to ensure clarity, while integrating low-opacity Islamic geometric patterns to provide cultural texture. The aesthetic avoids the heavy "gold-and-green" clichés, opting instead for a sophisticated, airy interface that feels like a premium sanctuary.

## Colors
The palette is rooted in a soft neutral base to maximize legibility and calm. 

- **Primary (Green):** A deep, forest-toned green used for active states and primary actions, representing growth and life.
- **Secondary (Amber):** Used for spiritual highlights, such as sunrise or sun-path related notifications.
- **Tertiary (Blue) & Quaternary (Purple):** Reserved for educational content and community features.
- **Faint Tints:** These are high-luminance, low-saturation versions of the core colors. They are used exclusively as background fills for category cards to provide subtle visual differentiation without competing with content.

## Typography
The typography uses **Plus Jakarta Sans** across all levels to maintain a friendly and optimistic character. 

- **Headlines:** Use tighter letter-spacing and bold weights to provide clear section anchors.
- **Body Text:** Standard weights with generous line-height ensure long-form spiritual texts are readable.
- **Countdown Labels:** Specifically designed for the "countdown pills," using a bold weight and uppercase styling to instill a gentle sense of awareness for upcoming prayer times.

## Layout & Spacing
The design system utilizes a **Fluid Grid** model with an 8px base unit. 

- **Mobile:** 4-column grid with 20px side margins and 16px gutters.
- **Desktop:** 12-column grid centered in a max-width container of 1200px.
- **Rhythm:** Vertical rhythm is strictly enforced in 8px increments. Cards and sections are separated by `lg` (40px) spacing to allow the background geometric patterns to "breathe" between content blocks.

## Elevation & Depth
This design system employs **Tonal Layering** combined with **Low-Contrast Outlines**. 

- **Surface Depth:** The primary background is the neutral base. Category cards sit on top using the Faint Tints. 
- **Shadows:** Avoid heavy dropshadows. Instead, use a single 1px stroke (10% opacity of the primary color) to define card boundaries.
- **Patterns:** Subtle Islamic geometric patterns (8-point stars or interconnected hexagons) are applied as background watermarks at 3-5% opacity. These patterns should appear behind the main content containers, never inside a card where text resides.

## Shapes
Following the "Round Eight" philosophy, the design system uses a consistent 8px (0.5rem) radius for standard components.

- **Standard Elements:** Buttons, Input fields, and Small Cards use `rounded` (8px).
- **Large Containers:** Main prayer time dashboard cards use `rounded-lg` (16px).
- **Pills:** Countdown elements and status tags use a fully rounded (pill) shape to contrast against the structured grid.

## Components
- **Category Cards:** Large, breathable containers using `faint_tints`. They should feature a localized geometric pattern in the bottom-right corner at 10% opacity for subtle flair.
- **Prayer Time Highlights:** The "Current Prayer" card uses the `primary_color` (Green) as a solid fill with white text to create a high-contrast focal point.
- **Countdown Pills:** Small, floating elements within the prayer list. They use a secondary background (Amber for soon-to-expire, Primary for distant) with `countdown-num` typography. They must have a subtle "glow" (2px blur) to draw the eye.
- **Input Fields:** Minimalist design with 1px borders. Focus states use the `primary_color` for the border and a 4px soft glow.
- **Lists:** Prayer time rows use horizontal dividers (1px, 5% opacity) with the "Next Prayer" row slightly scaled (1.02x) and highlighted with a faint tint.