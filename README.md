# Cursor + Claude Code Git Sync Hooks

Automatic git commit hooks for **Cursor** and **Claude Code** that stage and commit only agent-modified files. No more manual commits, no accidental manual changes swept into agent commits.

## Features

- **Agent-specific hooks** — Each AI tracks its own changed files separately
- **Agent-written messages** — Agents must provide their own commit message (no AI fallback calls)
- **No file collisions** — Agents write `cursor_changed_files` and `claude_changed_files` independently
- **CWD-based repo detection** — Both hooks walk up from working directory to find the repo (works for any project)
- **Logging** — Full hook execution logs for debugging (`~/.claude/hooks/` and `~/.cursor/hooks/`)

## How It Works

### Architecture

1. **Agent writes metadata** (before session stops):
   - `.git/cursor_commit_msg` or `.git/claude_commit_msg` — commit message
   - `.git/cursor_changed_files` or `.git/claude_changed_files` — list of files to commit (one per line)

2. **Hook executes on stop event**:
   - Walks up from CWD to find the git repo root
   - Reads commit message and changed files list
   - Stages only the listed files with `git add`
   - Commits with agent-prefixed message (`Cursor: ...` or `Claude Code: ...`)
   - Falls back to timestamp if no message was written

3. **Last commit tracking**:
   - Both hooks store `.git/cursor_last_commit` and `.git/claude_last_commit`
   - Agents read these at session start to see what changed since last run

## Installation

### Prerequisites

- **Git**: Installed and on PATH
- **Windows PowerShell**: v5.1+ (built-in on Windows 10+)

### Setup Steps

#### 1. Copy Hook Files

```powershell
New-Item -ItemType Directory -Path "$env:USERPROFILE\.claude\hooks" -Force
New-Item -ItemType Directory -Path "$env:USERPROFILE\.cursor\hooks" -Force

Copy-Item hooks\claude_auto_commit.ps1 "$env:USERPROFILE\.claude\hooks\"
Copy-Item hooks\cursor_auto_commit.ps1 "$env:USERPROFILE\.cursor\hooks\"
```

#### 2. Configure Cursor Hook

```powershell
Copy-Item config\hooks.json "$env:USERPROFILE\.cursor\"
```

#### 3. Configure Claude Code

```powershell
Copy-Item config\settings.json .claude\
```

#### 4. Add Agent Rules

```powershell
Copy-Item config\CLAUDE.md "$env:USERPROFILE\.claude\"
Copy-Item rules\global_sync.mdc "$env:USERPROFILE\.cursor\rules\"
```

### Verify Installation

```powershell
Get-Content "$env:USERPROFILE\.claude\hooks\claude_auto_commit.log" -Tail 20
Get-Content "$env:USERPROFILE\.cursor\hooks\cursor_auto_commit.log" -Tail 20
```

## Usage

### For Claude Code

Before stopping, write both temp files to the repo's `.git/` directory:

```
1. Commit message → .git/claude_commit_msg
2. Changed files  → .git/claude_changed_files  (one path per line)
```

If no message is written, the hook falls back to a timestamp: `auto-commit 2026-03-18 15:30`.

### For Cursor

Before stopping, the Cursor agent writes:

```powershell
Set-Content .git\cursor_commit_msg "your summary here" -NoNewline

@"
path/to/file1.ts
path/to/file2.json
"@ | Set-Content .git\cursor_changed_files
```

## Troubleshooting

**Hook not firing?** Check logs — common causes:
- Git not on PATH → logs "git.exe not found"
- Hook CWD not inside a git repo → logs "git repo not found in parent directories"
- No changed files → hook skips silently

**Message not read?** Check logs for `Message file exists: True`. If False, the agent didn't write the file before stopping — check your agent's global rules.

## Architecture Details

### Message Priority

1. Read pre-written message from `.git/{agent}_commit_msg`
2. If missing, use timestamp: `auto-commit 2026-03-18 15:30`

Agents are responsible for writing their own commit messages.

### File Staging

1. Check for `.git/{agent}_changed_files` with explicit file list
2. If present, reset HEAD and `git add` only those files
3. If missing (Claude hook only), fall back to `git add -u` (tracked files only)

### Commit Prefix

- Claude Code commits: `Claude Code: message`
- Cursor commits: `Cursor: message`

### Repo Detection

Both hooks walk up from `$PWD` to find the nearest `.git` directory — no configuration needed when switching between repos.

## File Structure

```
~/.claude/hooks/
  ├── claude_auto_commit.ps1     (Stop hook script)
  └── claude_auto_commit.log     (auto-created)

~/.cursor/
  ├── hooks/
  │   ├── cursor_auto_commit.ps1 (Stop hook script)
  │   └── cursor_auto_commit.log (auto-created)
  └── hooks.json                 (Hook config)

[repo]/.git/
  ├── claude_commit_msg          (Claude writes before stopping)
  ├── claude_changed_files       (Claude writes before stopping)
  ├── claude_last_commit         (Hook writes after commit)
  ├── cursor_commit_msg          (Cursor writes before stopping)
  ├── cursor_changed_files       (Cursor writes before stopping)
  └── cursor_last_commit         (Hook writes after commit)
```

## License

MIT
