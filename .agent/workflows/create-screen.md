---
description: Guidelines for creating new screens and UI components
---

# Create Screen Workflow

When asked to build a new screen, page, or complex UI widget for the SportsApp, ALWAYS adhere to the following architectural guidelines:

## 1. Do NOT manually inject CustomBottomNav
The application uses a persistent AppShell pattern via `MainLayout` and an `IndexedStack`.
- If the new screen is a main tab, it should be registered in the `IndexedStack` inside `MainLayout`.
- If the new screen is a sub-page (like a details page), the user will navigate to it normally (e.g., `Navigator.push`), and it will render ON TOP of the bottom nav or hide the bottom nav depending on the intended user experience.
- NEVER put `CustomBottomNav` as the `bottomNavigationBar` inside the new screen's `Scaffold`.

## 2. Strict Theme Adherence (Dark Mode Ready)
- NEVER use hardcoded colors like `Colors.white`, `Colors.black`, or raw hex codes (e.g., `Color(0xFF...)`).
- ALWAYS extract colors from `context.colors` (the `AppTheme.AppColors` extension). Examples:
  - Backgrounds: `context.colors.background` or `context.colors.surfaceContainerHighest`
  - Text: `context.colors.textHigh`, `context.colors.textMedium`, `context.colors.textLow`
  - Accents: `context.colors.primaryContainer`, `context.colors.onPrimaryContainer`
- ALWAYS use `Theme.of(context).textTheme` for fonts instead of hardcoding `TextStyle` family properties.

## 3. Extract Strings and Constants
- Use consistent padding and margins (factors of 4, usually `8.0`, `16.0`, `24.0`).
- Ensure the UI is responsive. For lists and scrollable content, use `CustomScrollView` and `Sliver` widgets when appropriate.
