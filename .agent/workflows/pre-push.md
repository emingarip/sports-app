---
description: How to push code and merge branches safely
---

# Pre-Push & Merge Workflow

When you are asked to push code, merge branches, or finalize a feature, you MUST follow these steps to ensure the application remains stable and CI/CD pipelines do not break.

1. **Run Static Analysis:**
   Always run `flutter analyze` to check for syntax errors, missing imports, or deprecated API usage.
   If there are errors (not just info/warnings that are acceptable), fix them before proceeding.

2. **Run Automated Tests:**
   Always run `flutter test` locally to ensure no widget tests or unit tests are broken by your UI or architecture changes.
   If any test fails, STOP and fix the test or the code. Do not push failing code.

3. **Verify Build:**
   If the changes are significant, consider running `flutter build web` or `flutter build apk` to ensure the compilation succeeds.

4. **Commit and Push:**
   Once all the above steps pass successfully:
   ```bash
   git add .
   git commit -m "Your descriptive message"
   git push origin <branch-name>
   ```

5. **Merge (If applicable):**
   If you need to merge to `master`, check out `master`, pull the latest changes, merge the feature branch, and push.

Make sure and double check this checklist every time you are about to push or merge!
