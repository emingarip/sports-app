---
description: Branching policy for features and bug fixes
---

# Git Branching Policy

This workflow defines the rules for creating new features and fixing bugs in the repository.

1. **NEVER Commmit Directly to Master:**
   Unless explicitly instructed otherwise by the user for trivial changes, you MUST NOT commit new features or bug fixes directly to the `master` or `main` branch.

2. **Always Create a New Branch:**
   Before writing any code for a new feature or a bug fix, you MUST create and checkout a new branch.

3. **Branch Naming Convention:**
   - For new features, use the `feature/` prefix. Example: `git checkout -b feature/dynamic-theme`
   - For bug fixes, use the `fix/` or `bugfix/` prefix. Example: `git checkout -b fix/login-crash`
   - Use kebab-case for the branch name description.

4. **Workflow Execution:**
   - When a user asks you to implement a new feature (e.g., "Add a settings page"), your very first step should be creating the branch `feature/settings-page`.
   - When a user asks you to fix an issue (e.g., "Fix the button overflow"), your very first step should be creating the branch `fix/button-overflow`.

By following this workflow, we ensure that the main codebase remains stable and all changes are isolated until they are ready to be merged.
