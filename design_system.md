# Design System Specification: The Dynamic Bento

## 1. Overview & Creative North Star
**Creative North Star: "The Kinetic Curator"**

This design system rejects the "static list" mentality of traditional sports apps. Instead, it treats the screen as a curated gallery of high-energy data. By utilizing a "Bento Box" aesthetic, we organize complex statistics, live scores, and editorial content into a modular, high-impact grid that feels both organized and urgent.

To move beyond a generic template, we utilize **Intentional Asymmetry**. Not every card is a square; we use the Spacing Scale to create "hero" modules that span multiple columns, paired with "micro" modules for rapid-fire data. This creates a rhythmic visual pace—a "pulse"—that mirrors the excitement of a live sporting event.

---

### 2. Colors & Surface Philosophy
The palette is rooted in a sophisticated "Ice & Iron" base, punctuated by "Digital Gold" to drive action.

*   **Primary (#6c5a00) & Primary Fixed (#ffd709):** Our "Energy Tokens." Reserved exclusively for winning moments, active states, and primary CTAs.
*   **Surface Hierarchy (The No-Line Rule):** 
    *   **Prohibited:** 1px solid borders for sectioning. 
    *   **The Method:** Boundaries are defined strictly through background shifts. Use `surface_container_lowest` (#ffffff) for high-priority interactive cards sitting on a `surface` (#f3f7fb) background.
*   **The Glass & Gradient Rule:** For floating headers or navigation bars, use `surface_container_low` at 80% opacity with a `24px` backdrop-blur. This "frosted glass" effect ensures the energetic background content bleeds through, maintaining a sense of depth.
*   **Signature Textures:** Apply a subtle linear gradient from `primary_fixed` (#ffd709) to `primary` (#6c5a00) on hero action buttons to provide a "metallic" premium sheen that flat colors cannot replicate.

---

### 3. Typography: Editorial Authority
We use a dual-typeface system to balance "Big Stage" energy with "High-Density" data readability.

*   **Display & Headlines (Lexend):** A geometric, wide-aperture sans-serif. Used for scores, player names, and bold editorial headers. It conveys stability and modernism.
    *   *Scale Example:* `display-lg` (3.5rem) is reserved for the final score of a championship game.
*   **Body & Labels (Inter):** A high-legibility workhorse. Used for play-by-play commentary, statistical breakdowns, and UI labels. 
    *   *Scale Example:* `label-md` (0.75rem) in `on_surface_variant` is used for "time-elapsed" indicators.

---

### 4. Elevation & Depth
In this system, depth is a result of **Tonal Layering**, not structural shadows.

*   **The Layering Principle:** To lift a card, do not reach for a shadow first. Instead, move up the tier: Place a `surface_container_lowest` card on a `surface_container` background.
*   **Ambient Shadows:** If a card must "float" (e.g., a modal or a primary action button), use an ultra-diffused shadow:
    *   *Blur:* 32px | *Spread:* -4px | *Color:* `on_surface` at 6% opacity.
*   **The Ghost Border Fallback:** For accessibility in high-glare environments (e.g., outdoor stadium use), use a "Ghost Border": `outline_variant` (#a9aeb1) at **15% opacity**.
*   **Bento Radii:** Consistency is non-negotiable. 
    *   **Cards:** `xl` (3rem / 48px) for large hero containers.
    *   **Modules:** `lg` (2rem / 32px) for standard bento cells.
    *   **Buttons:** `full` (9999px) for a high-performance, aerodynamic feel.

---

### 5. Key Components

#### The Bento Card (Primary Container)
*   **Style:** No borders. Background: `surface_container_lowest`. 
*   **Spacing:** Internal padding must follow `6` (2rem). 
*   **Layout:** Content should be "anchored" to the corners to emphasize the box shape.

#### Action Buttons
*   **Primary:** Background: `primary_fixed`. Text: `on_primary_fixed`. Shape: `full`.
*   **Tertiary (Ghost):** No background. Text: `primary`. Used for "See All" or "View Stats" to keep the UI from becoming cluttered.

#### Interaction Chips
*   **Filter Chips:** Use `surface_container_high`. When active, transition to `primary_fixed` with a subtle `2.5` (0.85rem) bounce animation.

#### Data Lists
*   **Rule:** Forbid divider lines.
*   **Structure:** Separate list items using `1.5` (0.5rem) of vertical white space or by alternating backgrounds between `surface` and `surface_container_low`.

#### Sports-Specific Components
*   **Live Pulse Indicator:** A `tertiary_container` (#ff9474) soft-glow circle that breathes (opacity animation 40% -> 100%) to indicate a live game.
*   **Stat-Bar:** A dual-tone horizontal bar using `primary` and `surface_variant` to show ball possession or win probability.

---

### 6. Do’s and Don’ts

**Do:**
*   **Do** use asymmetrical grid spans (e.g., one card spanning 2 columns, the next spanning 1) to create a premium, editorial "magazine" feel.
*   **Do** use `lexend` for any numerical data. Numbers are the stars of a sports app; they should feel heavy and authoritative.
*   **Do** leverage `surface_bright` for the main background to keep the app feeling "fresh" and "daylight-ready."

**Don’t:**
*   **Don’t** use pure black (#000000). Use `on_surface` (#2a2f32) to keep the contrast high but the vibe sophisticated.
*   **Don’t** use a border-radius smaller than `md` (1.5rem) for any container. Sharp corners break the "soft-premium" aesthetic.
*   **Don’t** use standard "Drop Shadows." If a card doesn't feel separated enough, adjust the `surface_container` tier instead.

---

## 7. Token Values mapped to Flutter AppTheme

### Colors
- `primary`: `#6c5a00`
- `primaryContainer`: `#ffd709`
- `onPrimaryContainer`: `#5b4b00`
- `secondary`: `#5c5b5b`
- `secondaryContainer`: `#e5e2e1`
- `background`: `#f3f7fb`
- `surface`: `#f3f7fb`
- `surfaceContainerLowest`: `#ffffff`
- `surfaceContainerLow`: `#ecf1f6`
- `surfaceContainer`: `#e3e9ee`
- `surfaceContainerHigh`: `#dde3e8`
- `surfaceContainerHighest`: `#d7dee3`
- `error`: `#b02500`
- `errorContainer`: `#f95630`
- `textHigh` (`on_surface`): `#2a2f32`
- `textMedium` (`on_surface_variant`): `#575c60`
- `textLow` (`outline`): `#73777b`

### Typography
- Headlines: `Lexend`
- Body/Labels: `Inter`

### Shapes
- Card Radius: `48px` (xl)
- Module Radius: `32px` (lg)
- Border Radius (Buttons): `9999px` (full)
