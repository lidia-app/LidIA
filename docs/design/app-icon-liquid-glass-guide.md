# LidIA App Icon — Liquid Glass Layer Guide

## Current Icon Analysis

The current icon has three visual elements that map naturally to layers:

1. **Background**: Blue-to-purple gradient (bottom-left to top-right)
2. **Middle**: Three horizontal lines (audio level indicator / equalizer motif)
3. **Foreground**: Pink/coral waveform sine wave

## Layer Decomposition

### Layer 1: Background
- Solid blue-purple gradient fill
- No transparency — this is the base
- Should be a simple rounded rectangle or fill
- The system will apply the rounded-rect mask automatically

### Layer 2: Middle (Body)
- Three horizontal white lines, semi-transparent (~60% opacity)
- These represent the "audio" aspect of the app
- Keep them as solid filled shapes (not thin strokes)
- Apple recommends "solid, filled, overlapping semi-transparent shapes"

### Layer 3: Foreground
- The pink/coral waveform
- Convert from outline/stroke to a **solid filled shape**
- Apple: "Consider a simplified design comprised of solid, filled shapes"
- The waveform should be a thick, filled path — not a thin line
- This layer gets the most depth/parallax from the system

## Design Principles (from Apple)

1. **Solid filled shapes** — no thin outlines or strokes
2. **Overlapping semi-transparent layers** — creates depth
3. **Let the system handle effects** — don't add shadows, reflections, or blur
4. **Keep elements centered** — avoid clipping at edges
5. **Simplified design** — fewer elements with more impact

## Steps

1. Open current icon in Figma/Sketch/Illustrator
2. Separate into 3 layers (background, lines, waveform)
3. Convert waveform from stroke to filled shape
4. Make horizontal lines thicker and semi-transparent
5. Export each layer as 1024x1024 PNG with transparency (except background)
6. Open **Icon Composer** (Xcode 26 → Developer Tools, or Apple Design Resources)
7. Drag layers into Background, Body, Foreground slots
8. Preview all variants: Default, Dark, Clear (Light), Clear (Dark), Tinted (Light), Tinted (Dark)
9. Adjust opacity/positioning until the system effects look good
10. Export the composed icon asset catalog
11. Replace `Sources/LidIA/Resources/Assets.xcassets/AppIcon.appiconset/`

## Appearance Variants

Apple requires 6 variants:
- **Default** (light) — standard appearance
- **Dark** — system dark mode
- **Clear (light)** — transparent/glass on light wallpaper
- **Clear (dark)** — transparent/glass on dark wallpaper
- **Tinted (light)** — monochrome tinted on light
- **Tinted (dark)** — monochrome tinted on dark

Icon Composer handles generating these from your layers automatically.

## Notes

- The `.icns` file at `Sources/LidIA/Resources/AppIcon.icns` should also be regenerated
- `run.sh` copies the `.icns` file into the app bundle
- Test the icon in both Dock and menu bar after replacing
