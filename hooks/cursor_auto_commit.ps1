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

# Walk up from CWD to find git repo root
$gitTop = $null
$searchDir = $PWD.Path
$depth = 0
while (-not $gitTop -and $depth -lt 10) {
  if (Test-Path (Join-Path $searchDir ".git")) {
    $gitTop = $searchDir
    break
  }
  $parent = Split-Path $searchDir -Parent
  if ($parent -eq $searchDir) { break }
  $searchDir = $parent
  $depth++
}

Log "git repo search from $PWD | found at: '$gitTop' (depth=$depth)"
if (-not $gitTop) { Log "ERROR: git repo not found in parent directories"; exit 0 }

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
