---
description: Guidelines for Riverpod state management and providers
---

# Riverpod State Workflow

When adding new global state, data sources, or managing local component states that need to be shared, ALWAYS follow these rules:

## 1. Use Riverpod Annotations
- The project relies on `riverpod_annotation` (`@riverpod`). Do NOT use the legacy syntax (`StateProvider`, `StateNotifierProvider`, etc.) unless absolutely necessary.
- Write your provider logic as a `class` extending `_$ClassName` using `@riverpod` or as a simple function annotated with `@riverpod` if it's read-only state.

## 2. Execute Code Generation
If you create or modify a file containing `@riverpod` annotations (e.g., `lib/providers/example_provider.dart`):
1. **Always** ensure you have the `part 'example_provider.g.dart';` directive at the top.
2. **CRITICAL:** Run the build runner to generate the `.g.dart` file before testing or pushing code.

```bash
dart run build_runner build -d
```
// turbo-all

## 3. Best Practices
- Keep providers focused and single-purpose. 
- Avoid monolithic state objects if possible.
- Use `ref.watch` inside `build()` loops and `ref.read` inside callbacks (like `onPressed`).
