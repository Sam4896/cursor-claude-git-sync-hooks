# Cursor + Claude Code Git Sync Hooks

Automatic git commit hooks for **Cursor** and **Claude Code** that intelligently stage and commit only agent-modified files. No more manual commits, no accidental manual changes swept into agent commits.

## Features

- **Agent-specific hooks** — Each AI tracks its own changed files separately
- **Haiku fallback** — Uses cheap Claude Haiku model to generate commit messages if agent doesn't provide one
- **No file collisions** — Agents write `cursor_changed_files` and `claude_changed_files` independently
- **Logging** — Full hook execution logs for debugging (`~/.claude/hooks/` and `~/.cursor/hooks/`)
- **Workspace awareness** — Cursor hook finds repo via workspace marker file set by Claude Code

## How It Works

### Architecture

1. **Agent writes metadata** (before session stops):
   - `.git/cursor_commit_msg` or `.git/claude_commit_msg` — commit message
   - `.git/cursor_changed_files` or `.git/claude_changed_files` — list of files to commit (one per line)

2. **Hook executes on stop event**:
   - Reads commit message and changed files list
   - Stages only the listed files with `git add`
   - Commits with agent-prefixed message (`Cursor: ...` or `Claude Code: ...`)
   - Falls back to Haiku model if message missing

3. **Workspace coordination**:
   - Claude Code Stop hook writes `~/.claude/workspace_marker` (path to repo root)
   - Cursor hook reads marker to find the repo
   - Both hooks store `.git/cursor_last_commit` and `.git/claude_last_commit` for change tracking

## Installation

### Prerequisites

- **Claude Code CLI**: `claude` command available on PATH ([install](https://github.com/anthropics/claude-code))
- **Git**: Installed and on PATH
- **Windows PowerShell**: v5.1+ (built-in on Windows 10+)

### Setup Steps

#### 1. Copy Hook Files

```powershell
# Create hook directories
New-Item -ItemType Directory -Path "$env:USERPROFILE\.claude\hooks" -Force
New-Item -ItemType Directory -Path "$env:USERPROFILE\.cursor\hooks" -Force

# Copy hooks from repo
Copy-Item hooks\claude_auto_commit.ps1 "$env:USERPROFILE\.claude\hooks\"
Copy-Item hooks\cursor_auto_commit.ps1 "$env:USERPROFILE\.cursor\hooks\"
```

#### 2. Configure Cursor Hook

Copy `config/hooks.json` to `~/.cursor/hooks.json`:

```powershell
Copy-Item config\hooks.json "$env:USERPROFILE\.cursor\"
```

#### 3. Configure Claude Code

Copy `config/settings.json` to your project's `.claude/settings.json` (enables workspace marker on stop):

```powershell
Copy-Item config\settings.json .claude\
```

#### 4. Add Claude Code Rules

Copy `config/CLAUDE.md` to `~/.claude/CLAUDE.md` (global instructions):

```powershell
Copy-Item config\CLAUDE.md "$env:USERPROFILE\.claude\"
```

#### 5. Add Cursor Rules

Copy `rules/global_sync.mdc` to `~/.cursor/rules/global_sync.mdc`:

```powershell
Copy-Item rules\global_sync.mdc "$env:USERPROFILE\.cursor\rules\"
```

### Verify Installation

Check that hooks are executable and logs show up:

```powershell
# Logs should appear here when hooks fire
Get-Content "$env:USERPROFILE\.claude\hooks\claude_auto_commit.log" -Tail 20
Get-Content "$env:USERPROFILE\.cursor\hooks\cursor_auto_commit.log" -Tail 20
```

## Usage

### For Claude Code

At the end of your session (when you press Stop), do this:

```
Write both to the correct `.git/` paths in your repo:

1. Commit message:
   Add-Content -Path ".git/claude_commit_msg" -Value "your summary here" -NoNewline

2. List of changed files:
   @"
path/to/file1.md
path/to/file2.py
"@ | Set-Content ".git/claude_changed_files"
```

If you forget, the hook will:
1. Try to generate a message with Haiku model
2. Fall back to timestamp-based message

### For Cursor

After you finish editing in Cursor, the composer bot should write:

```powershell
# 1. Commit message
Set-Content .git\cursor_commit_msg "your summary here" -NoNewline

# 2. Files changed
@"
path/to/file1.ts
path/to/file2.json
"@ | Set-Content .git\cursor_changed_files
```

When Cursor stops, the hook automatically:
1. Reads the message and files
2. Stages only those files
3. Commits with `Cursor:` prefix

## Troubleshooting

### Hook Not Firing

**Check logs:**
```powershell
# Claude Code hook
Get-Content "$env:USERPROFILE\.claude\hooks\claude_auto_commit.log" -Tail 50

# Cursor hook
Get-Content "$env:USERPROFILE\.cursor\hooks\cursor_auto_commit.log" -Tail 50
```

**Common issues:**
- Git not on PATH → Hook logs will show "git.exe not found"
- Workspace marker not set → Cursor hook exits early. Requires Claude Code session to stop first
- No changed files → Hook skips commit (nothing to commit)

### Message Not Being Read

Check logs for:
```
Message file exists: True
Found pre-written message (absolute): XXX chars
```

If False, verify agent wrote to the correct `.git/` path (must be absolute path to repo's `.git/`, not HOME's `.git/`).

### Files Not Staged Correctly

Check logs for:
```
Found cursor_changed_files (absolute): N files
Staging: path/to/file
```

If files list not found, verify agent wrote `.git/cursor_changed_files` with proper relative paths.

## Architecture Details

### Message Priority

1. Try to read pre-written message from `.git/{agent}_commit_msg`
2. If missing, call `claude --model haiku` to generate one
3. If that fails, use timestamp: `auto-commit 2026-03-18 15:30`

### File Staging

1. Check for `.git/{agent}_changed_files` with explicit file list
2. If present, reset HEAD and `git add` only those files
3. If missing, fall back to `git add -u` (tracked files only, safer)

### Commit Prefix

- Claude Code commits: `Claude Code: message`
- Cursor commits: `Cursor: message`

This makes it easy to see which agent made each change in git log.

## File Structure

```
~/.claude/
  ├── hooks/
  │   ├── claude_auto_commit.ps1        (Stop hook script)
  │   ├── claude_auto_commit.log        (Log file, auto-created)
  │   └── CLAUDE.md                     (Agent instructions)
  └── workspace_marker                  (Repo path, auto-created)

~/.cursor/
  ├── hooks/
  │   ├── cursor_auto_commit.ps1        (Stop hook script)
  │   └── cursor_auto_commit.log        (Log file, auto-created)
  ├── hooks.json                        (Hook config)
  └── rules/
      └── global_sync.mdc               (Agent rules)

[repo]/.git/
  ├── claude_commit_msg                 (Claude writes this)
  ├── claude_changed_files              (Claude writes this)
  ├── claude_last_commit                (Hook writes this)
  ├── cursor_commit_msg                 (Cursor writes this)
  ├── cursor_changed_files              (Cursor writes this)
  └── cursor_last_commit                (Hook writes this)

[repo]/.claude/
  └── settings.json                     (Claude workspace hook config)
```

## Tips

- **Don't manually stage files** before session stop — let the agent list what it changed
- **Keep commit messages under 72 chars** — git convention for diffs
- **Use imperative mood** — "add feature" not "added feature"
- **Check logs early** — logs have timestamps and detailed debug info
- **One agent per session** — if both Claude Code and Cursor touch same file, last commit wins

## License

MIT

## Contributing

These hooks are designed for the AutoPhD research orchestration system but can be used standalone. Feedback and improvements welcome.
