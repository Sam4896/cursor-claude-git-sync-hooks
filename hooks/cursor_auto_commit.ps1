$ErrorActionPreference = "SilentlyContinue"

# --- tiny logger (writes outside repos) ---
$logDir = Join-Path $env:USERPROFILE ".cursor\hooks"
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
    "$env:ProgramFiles\Git\cmd\git.exe",
    "$env:ProgramFiles\Git\bin\git.exe",
    "${env:ProgramFiles(x86)}\Git\cmd\git.exe"
  ) | Where-Object { $_ -and (Test-Path $_) }
  if ($candidates.Count -gt 0) { return $candidates[0] }
  return $null
}
$git = GetGit
if (-not $git) { Log "SKIP: git.exe not found"; exit 0 }

# --- read agent-written files from known location (~/.cursor/) ---
$stateDir = Join-Path $env:USERPROFILE ".cursor"
$msgFile   = Join-Path $stateDir "cursor_commit_msg"
$filesFile = Join-Path $stateDir "cursor_changed_files"

Log "Checking for state files in: $stateDir"
Log "  cursor_commit_msg exists:    $(Test-Path $msgFile)"
Log "  cursor_changed_files exists: $(Test-Path $filesFile)"

if (-not (Test-Path $filesFile)) { Log "No cursor_changed_files — nothing to commit"; exit 0 }

# --- derive repo root from the first absolute path in the files list ---
$files = @((Get-Content $filesFile -Raw) -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
Remove-Item $filesFile -Force
if (-not $files) { Log "cursor_changed_files is empty — nothing to commit"; exit 0 }

$firstFile = $files[0]
$parentDir = Split-Path $firstFile -Parent
Log "Deriving repo root from: '$parentDir'"
$gitTop = (& $git -C "$parentDir" rev-parse --show-toplevel 2>$null) -replace '/', '\'
Log "Repo root derived from changed files: '$gitTop'"
if (-not $gitTop -or -not (Test-Path (Join-Path $gitTop ".git"))) {
  Log "ERROR: could not derive valid repo root from '$firstFile'"; exit 0
}

Set-Location $gitTop
$gitDir = (& $git rev-parse --absolute-git-dir 2>$null).Trim()

# --- wait for index.lock ---
$lock = Join-Path $gitDir "index.lock"
$t = 0
while ((Test-Path $lock) -and $t -lt 8) { Start-Sleep -Milliseconds 500; $t += 0.5 }
if (Test-Path $lock) { Remove-Item $lock -Force }

# --- commit message ---
$msg = ''
if (Test-Path $msgFile) {
  $msg = (Get-Content $msgFile -Raw).Trim()
  Remove-Item $msgFile -Force
  $msg = ($msg -replace '```|<[^>]+>', '' -replace '\s+', ' ').Trim()
  Log "Commit message: '$msg'"
}
if (-not $msg -or $msg.Length -lt 3) {
  $msg = "auto-commit $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
  Log "Using timestamp fallback: '$msg'"
}
if ($msg.Length -gt 300) { $msg = $msg.Substring(0, 300).Trim() }

# --- stage only agent-touched files ---
& $git reset HEAD 2>&1 | Out-Null
foreach ($f in $files) {
  Log "Staging: $f"
  & $git add -- $f.Trim() 2>&1 | Out-Null
}

# --- commit ---
Log "Committing: 'Cursor: $msg'"
& $git commit -m "Cursor: $msg" --quiet 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
  $head = & $git rev-parse HEAD
  & $git rev-parse HEAD | Set-Content (Join-Path $gitDir "cursor_last_commit") -NoNewline
  Log "[OK] COMMIT SUCCESS: HEAD=$head"
} else {
  Log "[FAIL] COMMIT ERROR: exit=$LASTEXITCODE"
}

exit 0
