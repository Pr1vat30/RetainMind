---
name: Aether AI
colors:
  surface: '#121416'
  surface-dim: '#121416'
  surface-bright: '#38393c'
  surface-container-lowest: '#0c0e10'
  surface-container-low: '#1a1c1e'
  surface-container: '#1e2022'
  surface-container-high: '#282a2c'
  surface-container-highest: '#333537'
  on-surface: '#e2e2e5'
  on-surface-variant: '#bdc8d1'
  inverse-surface: '#e2e2e5'
  inverse-on-surface: '#2f3133'
  outline: '#87929a'
  outline-variant: '#3e484f'
  surface-tint: '#7bd0ff'
  primary: '#8ed5ff'
  on-primary: '#00354a'
  primary-container: '#38bdf8'
  on-primary-container: '#004965'
  inverse-primary: '#00668a'
  secondary: '#54d8e8'
  on-secondary: '#00363c'
  secondary-container: '#02aebe'
  on-secondary-container: '#003b42'
  tertiary: '#98d3ff'
  on-tertiary: '#00344d'
  tertiary-container: '#43bbff'
  on-tertiary-container: '#00486a'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#c4e7ff'
  primary-fixed-dim: '#7bd0ff'
  on-primary-fixed: '#001e2c'
  on-primary-fixed-variant: '#004c69'
  secondary-fixed: '#91f1ff'
  secondary-fixed-dim: '#54d8e8'
  on-secondary-fixed: '#001f23'
  on-secondary-fixed-variant: '#004f57'
  tertiary-fixed: '#c9e6ff'
  tertiary-fixed-dim: '#89ceff'
  on-tertiary-fixed: '#001e2f'
  on-tertiary-fixed-variant: '#004c6e'
  background: '#121416'
  on-background: '#e2e2e5'
  surface-variant: '#333537'
typography:
  headline-xl:
    fontFamily: Plus Jakarta Sans
    fontSize: 36px
    fontWeight: '700'
    lineHeight: 44px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 28px
    fontWeight: '700'
    lineHeight: 36px
    letterSpacing: -0.015em
  headline-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 22px
    fontWeight: '600'
    lineHeight: 28px
    letterSpacing: -0.01em
  headline-sm:
    fontFamily: Plus Jakarta Sans
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 24px
  body-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  body-sm:
    fontFamily: Plus Jakarta Sans
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
  label-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 14px
    fontWeight: '600'
    lineHeight: 20px
  label-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 12px
    fontWeight: '600'
    lineHeight: 16px
    letterSpacing: 0.01em
  label-sm:
    fontFamily: Plus Jakarta Sans
    fontSize: 10px
    fontWeight: '600'
    lineHeight: 14px
    letterSpacing: 0.02em
rounded:
  sm: 0.5rem
  DEFAULT: 1rem
  md: 1.5rem
  lg: 2rem
  xl: 3rem
  full: 9999px
spacing:
  gutter: 1rem
  gutter-sm: 0.75rem
  gutter-lg: 1.25rem
  margin: 1.25rem
  margin-mobile: 1.25rem
  margin-tablet: 2rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2rem
---

## Brand & Style

This design system embodies an ultra-minimal, approachable, and warm modern AI assistant experience. Crafted with deep dark matte surfaces, calm tonal hierarchy, and luminous cyan/electric sky-blue accents, the interface removes cognitive friction while introducing delight. 

The emotional signature balances:
- **Intelligent warmth:** Modern conversational AI made deeply accessible and playful rather than cold or intimidating.
- **Distraction-free clarity:** Extreme whitespace, crisp hierarchy, and deliberate constraint in typography and layout.
- **Atmospheric tactile depth:** Gentle luminescence, layered charcoal tiers, and circular/pill-shaped touch points inspired by high-end mobile consumer electronics.

The design movement blends **Tactile Modern Dark Minimalist** with selective **Ethereal Glow** elements (cyan energetic focal centers, soft inner highlights, and ambient light rings).

## Colors

The palette is anchored by deep matte obsidian and charcoal layers, illuminated by bright electric cyan and sky blue accents.

### Color Tokens & Semantic Roles
- **Canvas Base (`#111315`):** Ultra-matte dark background creating an intimate screen canvas with zero glare.
- **Surface Elevation 1 (`#181A1E`):** Secondary app chrome, navigation capsules, and secondary dialog wrappers.
- **Surface Elevation 2 (`#20242A`):** Interactive cards, feature tiles, and segmented containers.
- **Surface Elevation 3 (`#2A2F37`):** Elevated control wells, active indicator backdrops, and active pill chips.
- **Primary Accent (`#38BDF8`):** Radiant sky cyan for primary actions, active navigation anchors, and focal visual motifs.
- **Secondary Accent (`#67E8F9`):** Bright ice cyan for high-energy glowing cores, status pings, and highlight halos.
- **Tertiary Accent (`#0EA5E9`):** Saturated deep cyan for gradient stops, pressed states, and prominent hero badges.
- **Text & Foreground:**
  - `text-primary`: `#F8FAFC` (pure readability, 98% opacity)
  - `text-secondary`: `#94A3B8` (contextual descriptions, secondary meta)
  - `text-tertiary`: `#64748B` (subtle captions, empty states, passive labels)
- **Status & Feedback:**
  - `success`: `#34D399`
  - `warning`: `#FBBF24`
  - `danger`: `#F87171`

## Typography

The typography leverages **Plus Jakarta Sans** across all roles to achieve a clean, friendly geometric balance with soft apertures and high legibility on dark backdrops.

### Rules & Hierarchy
- Headlines are tightly tracked (`-0.02em` to `-0.01em`) to create compact, modern headers without harsh brutality.
- Body text remains open, set in neutral slate tones (`#94A3B8`) with ample line height to reduce visual tension.
- Action buttons and tags employ semi-bold and bold weights (`600`/`700`) to stand out decisively against dark surfaces.

## Layout & Spacing

A mobile-first fluid layout model utilizing strict 4px and 8px base increments.

### Grid & Margins
- **Canvas Margins:** Mobile viewport edges maintain an intentional `1.25rem` (20px) safe padding, keeping controls away from physical bezel edges.
- **Card Grids:** 2-column modular grids use a `0.75rem` (12px) gutter for grouped dashboard tiles, expanding to single-column flex-stacks for conversation ribbons and prompts.
- **Pill & Floating Bars:** Bottom navigation bars and input pills float `1rem` above the device home indicator, suspended in central capsules.

## Elevation & Depth

Visual hierarchy is constructed through tonal surface staging, ultra-subtle borders, and targeted cyan luminescence.

### Elevation Hierarchy
1. **Base Surface (0dp):** Raw background `#111315`.
2. **Layer 1 - Embedded Cards (1dp):** `#1E2024` with a hairline ghost stroke (`rgba(255, 255, 255, 0.05)`). No heavy drop shadows.
3. **Layer 2 - Floating Controls & Nav Bars (2dp):** `#23262B` elevated with deep ambient blur: `0px 12px 32px rgba(0, 0, 0, 0.45)` and hairline upper border `rgba(255, 255, 255, 0.08)`.
4. **Active Hero & Glow Nodes (3dp):** Pulsing AI nodes and active voice triggers use radial diffused bloom:
   - Primary Bloom: `0px 0px 36px rgba(56, 189, 248, 0.35)`
   - Inner Flare: `0px 0px 12px rgba(103, 232, 249, 0.5)`

## Shapes

The shape philosophy is soft, welcoming, and hyper-rounded. High curvature removes visual hostility and mirrors friendly product hardware.

### Radius Token Scale
- **Pill / Circular (`9999px`):** All action buttons, filter tags, interactive audio triggers, tab capsules, and header chips.
- **Extra Large Cards (`rounded-xl` / 28px - 32px):** Hero banners, featured promotion cards, and conversation panels.
- **Standard Cards (`rounded-lg` / 20px - 24px):** Feature tiles, selection modules, and input blocks.
- **Micro Elements (`12px`):** Icon badges, avatar frames, and nested tools.

## Components

### Buttons & Interactive Touchpoints
- **Primary Pill Button:** Solid `#38BDF8` background with dark charcoal typography (`#0F172A`, bold `600`), 48px to 56px height, rounded-full geometry. Hover/active states subtly shift toward `#67E8F9`.
- **Secondary / Ghost Pill:** Dark container (`#23262B`), light text (`#F8FAFC`), with `1px` subtle outline (`rgba(255, 255, 255, 0.08)`).
- **Voice / Orbit Mic Button:** Multi-ring concentric structure. Center circular button (`#38BDF8` or elevated `#2A2F37` with cyan mic glyph) surrounded by a semi-translucent backdrop tier (`rgba(56, 189, 248, 0.12)`).

### Chips & Filter Tags
- Fully rounded pills (`padding: 8px 18px`).
- **Active State:** Cyan surface (`#38BDF8`) with dark foreground text.
- **Inactive State:** Low-contrast neutral container (`#1E2024`) with neutral secondary text (`#94A3B8`).

### Feature & Prompt Cards
- Styled with surface `#1E2024` or `#23262B`.
- Integrated with rounded-xl corners (20px to 24px).
- Optional vibrant gradient backdrops (e.g., Sky Cyan `#38BDF8` into Deep Teal `#0284C7`) reserved exclusively for highlight cards such as subscription or model updates.

### Input Fields & Speech Ribbons
- Matte pill wrappers with an inset microphone icon or prompt placeholder.
- Hairline focus ring in glowing cyan (`rgba(56, 189, 248, 0.4)`).
- Typography defaults to clean 14px/16px body copy in `#F8FAFC`.

### Floating Navigation Capsule
- Compact detached floating bar (`#181A1E` at 90% opacity with `backdrop-filter: blur(16px)`).
- Encloses 3 to 4 pill and circular touch targets with subtle iconography and gentle tactile press feedback.