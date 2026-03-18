# Global Rules

## Session Start (Git Repos)
At the start of every session in a git repo, silently run:
1. If `.git/claude_last_commit` exists: `git log $(cat .git/claude_last_commit)..HEAD --oneline`
2. If `.git/cursor_last_commit` exists and differs: note Cursor made changes, review briefly
3. Fallback (no bookmarks): `git log --oneline -10`

## Before Stopping
If you modified files this session, write BOTH:
1. **Commit message** to `.git/claude_commit_msg` (one-line summary, imperative mood)
2. **Workspace marker** to `~/.claude/workspace_marker` (your workspace root directory)

Example:
```
write "add retry logic to experiment agent" to `.git/claude_commit_msg`
write the current working directory to `~/.claude/workspace_marker`
```

The Stop hook uses these to commit changes. Cursor also reads the workspace marker to find your repo.
If you forget, the hook auto-generates the commit message but won't have the workspace path.

## Do NOT
- Do NOT append session notes or changelogs to any project `CLAUDE.md` or similar files.
  The git log is the change record — the commit message written above is sufficient.
