# Installation & Setup Guide

## Quick Start (5 minutes)

### 1. Install Prerequisites

Ensure you have:
- **Claude Code CLI**: https://github.com/anthropics/claude-code
  ```powershell
  claude --version  # Should show version
  ```
- **Git**: Installed and on PATH
  ```powershell
  git --version  # Should show version
  ```

### 2. Copy Files to Your System

Use PowerShell to copy files to the correct locations:

```powershell
$repo = "C:\path\to\cursor-claude-git-sync-hooks"  # Adjust to where you cloned/downloaded repo

# Create directories
New-Item -ItemType Directory -Path "$env:USERPROFILE\.claude\hooks" -Force | Out-Null
New-Item -ItemType Directory -Path "$env:USERPROFILE\.cursor\hooks" -Force | Out-Null
New-Item -ItemType Directory -Path "$env:USERPROFILE\.cursor\rules" -Force | Out-Null

# Copy hook scripts
Copy-Item "$repo\hooks\claude_auto_commit.ps1" "$env:USERPROFILE\.claude\hooks\"
Copy-Item "$repo\hooks\cursor_auto_commit.ps1" "$env:USERPROFILE\.cursor\hooks\"

# Copy configuration
Copy-Item "$repo\config\hooks.json" "$env:USERPROFILE\.cursor\"
Copy-Item "$repo\config\CLAUDE.md" "$env:USERPROFILE\.claude\"
Copy-Item "$repo\rules\global_sync.mdc" "$env:USERPROFILE\.cursor\rules\"

Write-Host "Files copied successfully!"
```

### 3. Configure Claude Code for Your Project

For each project using these hooks, copy `settings.json` to its `.claude/` directory and **edit the Stop hook path**:

```powershell
$projectRoot = "C:\path\to\your\project"
Copy-Item "$repo\config\settings.json" "$projectRoot\.claude\"

# Now open $projectRoot\.claude\settings.json and update the path in the command to your project root
# Find this line and change the path to YOUR project:
# "command": "powershell -Command \"@\\\"YOUR_PROJECT_PATH\\\\@\\\" | Set-Content..."
```

**Example settings.json for a project at `C:\code\my-research\`:**

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "powershell -Command \"@\\\"C:\\code\\my-research\\\\@\\\" | Set-Content \\\"$env:USERPROFILE\\\\.claude\\workspace_marker\\\" -NoNewline\"",
            "timeout": 5,
            "async": true
          }
        ]
      }
    ]
  }
}
```

Key point: The path in `@\\\"...\\\\@\\\"` must be your project root (where `.git/` is).

### 4. Verify Installation

Check that files are in place:

```powershell
# Check hook directories
Get-Item "$env:USERPROFILE\.claude\hooks\claude_auto_commit.ps1"
Get-Item "$env:USERPROFILE\.cursor\hooks\cursor_auto_commit.ps1"

# Check config files
Get-Item "$env:USERPROFILE\.cursor\hooks.json"
Get-Item "$env:USERPROFILE\.claude\CLAUDE.md"
Get-Item "$env:USERPROFILE\.cursor\rules\global_sync.mdc"

Write-Host "All files installed!"
```

## Per-Project Setup

For each project where you want to use these hooks:

1. Copy `config/settings.json` to `[project]/.claude/settings.json`
2. Edit the Stop hook to point to your project root (the folder containing `.git/`)

Example for project at `D:\research\my-exp\`:

```powershell
$project = "D:\research\my-exp"
Copy-Item "config\settings.json" "$project\.claude\"

# Edit $project\.claude\settings.json:
# Change path in command from the example to: D:\\research\\my-exp\\
```

## Hook Path Customization

### Claude Code Hook

The Claude Code hook automatically:
1. Searches up from current directory for `.git/`
2. Reads `~/.claude/workspace_marker` set by Claude's Stop hook

No additional configuration needed.

### Cursor Hook

The Cursor hook is configured in `~/.cursor/hooks.json`:

```json
{
  "version": 1,
  "hooks": {
    "stop": [
      {
        "command": "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"C:\\Users\\YOUR_USERNAME\\.cursor\\hooks\\cursor_auto_commit.ps1\"",
        "timeout": 30
      }
    ]
  }
}
```

If your username is different, update the path. Otherwise, no changes needed.

## Testing the Setup

### Test Claude Code Hook

1. Make changes to a test file in a git repo
2. In Claude Code, write to `.git/claude_commit_msg`:
   ```
   write "test commit" to ".git/claude_commit_msg"
   write @"
test_file.md
@" to ".git/claude_changed_files"
   ```
3. Press Stop
4. Check logs:
   ```powershell
   Get-Content "$env:USERPROFILE\.claude\hooks\claude_auto_commit.log" -Tail 30
   ```
5. Verify commit was created:
   ```powershell
   git log --oneline -5
   ```

### Test Cursor Hook

1. Make changes to a test file in a git repo
2. Have Cursor composer write:
   ```powershell
   Set-Content .git\cursor_commit_msg "test cursor commit" -NoNewline
   @"
   cursor_test.ts
   @" | Set-Content .git\cursor_changed_files
   ```
3. Stop Cursor
4. Check logs:
   ```powershell
   Get-Content "$env:USERPROFILE\.cursor\hooks\cursor_auto_commit.log" -Tail 30
   ```

## Troubleshooting

### Hooks Not Firing

**Check Cursor hook configuration:**
```powershell
$cursorConfigPath = "$env:USERPROFILE\.cursor\hooks.json"
if (Test-Path $cursorConfigPath) {
  Get-Content $cursorConfigPath
} else {
  Write-Host "ERROR: hooks.json not found at $cursorConfigPath"
}
```

**Check Claude Code settings:**
```powershell
Get-Content ".claude\settings.json"  # From your project root
```

### Git Not Found

If logs show "git.exe not found", ensure Git is installed:
```powershell
# Try direct paths
Test-Path "C:\Program Files\Git\bin\git.exe"
Test-Path "C:\Program Files (x86)\Git\bin\git.exe"
```

### Workspace Marker Not Being Set

Claude Code Stop hook must run first in a fresh session. This sets `~/.claude/workspace_marker` so Cursor hook can find the repo.

If Cursor hook logs show "Could not find workspace", run a Claude Code session first.

### Message or Files Not Being Found

Check logs for:
```
Message file exists: True
Changed files exist: True
```

If False:
- Claude Code: Verify you wrote to `.git/claude_commit_msg` (full repo path, not home)
- Cursor: Verify you wrote to `.git/cursor_commit_msg` (full repo path)

## Advanced: Custom Commit Message Generation

Both hooks call claude CLI as fallback:
```powershell
claude -p "Write a git commit message..." --model haiku
```

To customize the fallback prompt, edit the hook files at lines ~115-120 (Claude) or ~110-115 (Cursor).

## Uninstalling

To remove hooks:
```powershell
# Remove hook files
Remove-Item "$env:USERPROFILE\.claude\hooks\claude_auto_commit.ps1"
Remove-Item "$env:USERPROFILE\.cursor\hooks\cursor_auto_commit.ps1"

# Remove config
Remove-Item "$env:USERPROFILE\.cursor\hooks.json"

# Remove workspace marker
Remove-Item "$env:USERPROFILE\.claude\workspace_marker" -ErrorAction SilentlyContinue

# Remove from projects (optional)
Get-ChildItem -Path . -Name ".claude\settings.json" -Recurse | Remove-Item
```

## Support

See README.md for architecture and troubleshooting details.
