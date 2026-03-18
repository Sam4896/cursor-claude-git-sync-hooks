$ErrorActionPreference = "SilentlyContinue"

# --- tiny logger (writes outside repos) ---
$logDir = Join-Path $env:USERPROFILE ".cursor\\hooks"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$logFile = Join-Path $logDir "cursor_auto_commit.log"
function Log($m) {
  try { Add-Content -LiteralPath $logFile -Value ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $m) } catch {}
}
Log "[HOOK INVOKED] CWD=$PWD"

# --- find git.exe even if PATH is missing ---
function GetGit() {
  $cmd = Get-Command git -ErrorAction SilentlyContinue
  if ($cmd -and $cmd.Source) { return $cmd.Source }
  $candidates = @(
    "$env:ProgramFiles\\Git\\cmd\\git.exe",
    "$env:ProgramFiles\\Git\\bin\\git.exe",
    "${env:ProgramFiles(x86)}\\Git\\cmd\\git.exe",
    "${env:ProgramFiles(x86)}\\Git\\bin\\git.exe"
  ) | Where-Object { $_ -and (Test-Path $_) }
  if ($candidates.Count -gt 0) { return $candidates[0] }
  return $null
}
$git = GetGit
if (-not $git) { Log "SKIP: git.exe not found. CWD=$PWD PATH=$env:PATH"; exit 0 }

# Try to find workspace root via marker file (set by Claude Code)
# If not available, search up from home directory for recent git repos
$markerFile = Join-Path $env:USERPROFILE ".claude\workspace_marker"
$gitTop = $null

# Try 1: Check marker file (set by Claude Code Stop hook)
if (Test-Path $markerFile) {
  $gitTop = (Get-Content $markerFile -Raw).Trim()
  if (Test-Path (Join-Path $gitTop ".git")) {
    Log "Workspace from marker file: $gitTop"
  } else {
    $gitTop = $null
  }
}

# Try 2: Search for most recent .cursor directory (indicates active workspace)
if (-not $gitTop) {
  $cursorDirs = Get-ChildItem -Path $env:USERPROFILE -Directory -Name ".cursor" -ErrorAction SilentlyContinue
  if ($cursorDirs) {
    # Find git repos near .cursor by searching up 1-2 levels
    $testDir = Split-Path $env:USERPROFILE -Parent
    for ($i = 0; $i -lt 5; $i++) {
      if (Test-Path (Join-Path $testDir ".git")) {
        $gitTop = $testDir
        Log "Found git repo by searching near home: $gitTop"
        break
      }
      $testDir = Split-Path $testDir -Parent
      if ($testDir -eq (Split-Path $testDir -Parent)) { break }
    }
  }
}

if (-not $gitTop) {
  Log "WARNING: Could not find workspace. Marker: $markerFile | Waiting for Claude Code to set it..."
  exit 0
}

$root = $gitTop.Replace('/', '\')
Set-Location $root
Log "HOOK STARTED: root=$root"

$status = & $git status --porcelain 2>$null
Log "Git status: $(($status | Measure-Object -Line).Lines) changes"
if (-not $status) { Log "NO CHANGES - exiting"; exit 0 }

$gitDir = (& $git rev-parse --absolute-git-dir 2>$null).Trim()
if (-not $gitDir) { exit 0 }

# Debug: Check what files exist in .git for our hooks
$msgFile = Join-Path $gitDir "cursor_commit_msg"
$filesFile = Join-Path $gitDir "cursor_changed_files"
Log "Looking in: $gitDir"
Log "Message file exists: $(Test-Path $msgFile)"
Log "Changed files exist: $(Test-Path $filesFile)"

# Wait up to 8s for index.lock from a concurrent git process
$lock = Join-Path $gitDir "index.lock"
$t = 0
while ((Test-Path $lock) -and $t -lt 8) { Start-Sleep -Milliseconds 500; $t += 0.5 }
if (Test-Path $lock) { Remove-Item $lock -Force }

# Get commit message left by the Cursor agent
# Try absolute path first, then relative path as fallback
$msgFile = Join-Path $gitDir "cursor_commit_msg"
$msgFileRel = ".git\cursor_commit_msg"
Log "Checking for pre-written message at: $msgFile (or $msgFileRel)"
$msg = ''
if (Test-Path $msgFile) {
  $msg = (Get-Content $msgFile -Raw).Trim()
  Log "Found pre-written message (absolute): $(($msg).Length) chars"
  Remove-Item $msgFile -Force
  $msg = ($msg -replace '```|<[^>]+>', '' -replace '\s+', ' ').Trim()
  Log "Cleaned message: '$msg'"
} elseif (Test-Path $msgFileRel) {
  $msg = (Get-Content $msgFileRel -Raw).Trim()
  Log "Found pre-written message (relative): $(($msg).Length) chars"
  Remove-Item $msgFileRel -Force
  $msg = ($msg -replace '```|<[^>]+>', '' -replace '\s+', ' ').Trim()
  Log "Cleaned message: '$msg'"
}

# No message → call claude CLI with Haiku model and 10s timeout
if (-not $msg) {
  Log "No message found, will try to generate one"
  $summary = (& $git status --short 2>$null) -join ", "
  if ($summary) {
    Log "Calling claude with Haiku model for: $summary"
    try {
      $claudeOutput = & claude -p "Write a single-line git commit message, max 72 chars, imperative mood, no backticks, no prefix. Changed: $summary" --model haiku 2>&1
      $msg = ($claudeOutput -replace '```|<[^>]+>', '' -replace '\s+', ' ').Trim()
      Log "Claude response: '$msg'"
    } catch {
      Log "Claude call failed: $_"
    }
  }
}

# Final fallback: timestamp
if (-not $msg -or $msg.Length -lt 3) { $msg = "auto-commit $(Get-Date -Format 'yyyy-MM-dd HH:mm')"; Log "Using timestamp fallback: '$msg'" }
if ($msg.Length -gt 300) { $msg = $msg.Substring(0, 300).Trim() }

# Stage ONLY the files the agent touched (from cursor_changed_files list)
$filesFile = Join-Path $gitDir "cursor_changed_files"
$filesFileRel = ".git\cursor_changed_files"
Log "Checking for file list at: $filesFile (or $filesFileRel)"
$filesFound = $false

if (Test-Path $filesFile) {
  $files = Get-Content $filesFile | Where-Object { $_.Trim() -ne '' }
  Log "Found cursor_changed_files (absolute): $($files.Count) files"
  Remove-Item $filesFile -Force
  & $git reset HEAD 2>&1 | Out-Null
  foreach ($f in $files) {
    Log "Staging: $f"
    & $git add -- $f.Trim() 2>&1 | Out-Null
  }
  $filesFound = $true
} elseif (Test-Path $filesFileRel) {
  $files = Get-Content $filesFileRel | Where-Object { $_.Trim() -ne '' }
  Log "Found cursor_changed_files (relative): $($($files).Count) files"
  Remove-Item $filesFileRel -Force
  & $git reset HEAD 2>&1 | Out-Null
  foreach ($f in $files) {
    Log "Staging: $f"
    & $git add -- $f.Trim() 2>&1 | Out-Null
  }
  $filesFound = $true
}

if (-not $filesFound) {
  Log "WARNING: No cursor_changed_files found - nothing staged for commit"
}

Log "Committing with message: 'Cursor: $msg'"
& $git commit -m "Cursor: $msg" --quiet 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
  $head = & $git rev-parse HEAD
  & $git rev-parse HEAD | Set-Content (Join-Path $gitDir "cursor_last_commit") -NoNewline
  Log "[OK] COMMIT SUCCESS: '$msg' | HEAD=$head"
} else {
  Log "[FAIL] COMMIT ERROR: exit=$LASTEXITCODE | msg='$msg'"
}

exit 0
