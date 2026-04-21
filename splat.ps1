#Requires -Version 5.1
<#
.SYNOPSIS
    quicksplat — Turn a single video into a 3D Gaussian Splat (.ply) on Windows.

.DESCRIPTION
    Wraps splat.sh via WSL2. The actual pipeline (ffmpeg, COLMAP, 3DGRUT)
    runs inside WSL2 — this script handles path conversion and passes all
    flags through.

.PARAMETER Video
    Path to the input video file (mp4, mov, avi, mkv, m4v).

.PARAMETER Iters
    Training iterations. Default: 30000.

.PARAMETER Preview
    Run only 7k iterations for a quick quality check.

.PARAMETER Fps
    Override auto frame extraction FPS.

.PARAMETER Model
    3DGRUT training config. Default: colmap_3dgut.
    Options: colmap_3dgut | colmap_3dgrt | colmap_3dgut_mcmc | colmap_3dgrt_mcmc

.PARAMETER OutputDir
    Where to save output.ply. Default: current directory.

.PARAMETER SkipColmap
    Skip COLMAP and reuse existing workspace/colmap/ (resume after crash).

.EXAMPLE
    .\splat.ps1 myvideo.mp4
    .\splat.ps1 myvideo.mp4 -Iters 7000
    .\splat.ps1 myvideo.mp4 -Preview
    .\splat.ps1 myvideo.mp4 -Fps 3 -Iters 30000
#>

param(
    [Parameter(Position=0)]
    [string]$Video,

    [int]$Iters = 30000,
    [switch]$Preview,
    [int]$Fps = 0,
    [string]$Model = "colmap_3dgut",
    [string]$OutputDir = "",
    [switch]$SkipColmap
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── WSL2 check ────────────────────────────────────────────────────────────────
function Test-WSL {
    try {
        $result = wsl --status 2>&1
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

if (-not (Test-WSL)) {
    Write-Error @"
WSL2 is not installed or not running.

To install WSL2:
  1. Open PowerShell as Administrator
  2. Run: wsl --install
  3. Restart your computer
  4. Open Ubuntu from the Start menu and finish setup
  5. Then run install/setup_linux.sh inside the Ubuntu terminal

More info: https://learn.microsoft.com/en-us/windows/wsl/install
"@
    exit 1
}

# ── Convert Windows path to WSL path ─────────────────────────────────────────
function ConvertTo-WslPath([string]$winPath) {
    if ([string]::IsNullOrEmpty($winPath)) { return "" }
    $abs = (Resolve-Path -ErrorAction SilentlyContinue $winPath)?.Path
    if (-not $abs) { $abs = $winPath }
    $abs = $abs -replace "\\", "/"
    if ($abs -match "^([A-Za-z]):(.*)") {
        return "/mnt/" + $Matches[1].ToLower() + $Matches[2]
    }
    return $abs
}

# ── Locate splat.sh inside WSL ────────────────────────────────────────────────
$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$splatShWin = Join-Path $scriptDir "splat.sh"

if (-not (Test-Path $splatShWin)) {
    Write-Error "Cannot find splat.sh next to this script at: $splatShWin"
    exit 1
}

$splatShWsl = ConvertTo-WslPath $splatShWin

# ── Build argument list ───────────────────────────────────────────────────────
$args_list = @()

if (-not [string]::IsNullOrEmpty($Video)) {
    $videoWsl = ConvertTo-WslPath $Video
    $args_list += $videoWsl
}

if ($Preview) {
    $args_list += "--preview"
} else {
    $args_list += "--iters"; $args_list += $Iters
}

if ($Fps -gt 0)    { $args_list += "--fps";    $args_list += $Fps }
if ($Model)        { $args_list += "--model";  $args_list += $Model }
if ($SkipColmap)   { $args_list += "--skip-colmap" }

if (-not [string]::IsNullOrEmpty($OutputDir)) {
    $args_list += "--output-dir"
    $args_list += ConvertTo-WslPath $OutputDir
}

# ── Run in WSL ────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  quicksplat — launching pipeline in WSL2" -ForegroundColor Cyan
Write-Host "  Script : $splatShWsl" -ForegroundColor Cyan
Write-Host "  Args   : $($args_list -join ' ')" -ForegroundColor Cyan
Write-Host ""

$wslCmd = "bash `"$splatShWsl`" $($args_list -join ' ')"
wsl bash -c $wslCmd

if ($LASTEXITCODE -ne 0) {
    Write-Error "Pipeline failed. Check pipeline.log in the current directory."
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "  Done! Check the current folder for output.ply" -ForegroundColor Green
Write-Host "  View at: https://supersplat.playcanvas.com (drag and drop)" -ForegroundColor Green
