---
allowed-tools: Bash(git add:*), Bash(git status:*), Bash(git commit:*), Bash(git diff:*), Bash(git log:*), Bash(git push:*)
description: Commit all changes and push to remote
---

# Commit and Push

## Context

- Current git status: !`git status`
- Staged and unstaged changes: !`git diff HEAD`
- Recent commits (for style): !`git log --oneline -5`

## Your task

Based on the above context:

1. If there are no changes, say so and stop
2. Stage all changes with `git add -A`
3. Create a descriptive commit message:
   - Keep it concise (1-2 sentences)
   - Focus on "why" not "what"
   - End with: `Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>`
4. Commit the changes
5. Push to origin

## Rules

- Never use `git commit --amend`
- Never force push
- Use HEREDOC for commit message to preserve formatting
