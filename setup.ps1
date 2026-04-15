#Requires -Version 7.0
<#
.SYNOPSIS
    Windows development environment bootstrap — mirrors init.sh for Linux.
.DESCRIPTION
    Installs Scoop, all development tools, fonts, Catppuccin theme, and
    symlinks dotfiles. Idempotent: safe to run multiple times.
.PARAMETER DryRun
    Print what would be done without making any changes.
.NOTES
    Run as a regular user (Scoop does not require admin).
    The Developer Mode step triggers a UAC prompt to write one registry key.
#>
param(
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = $PSScriptRoot

# ─── Helpers ───────────────────────────────────────────────────────────────────
function Step  { param($m) Write-Host "`n==> $m" -ForegroundColor Cyan }
function Done  { param($m) Write-Host "    $m"   -ForegroundColor Green }
function Skip  { param($m) Write-Host "    (skip) $m"     -ForegroundColor DarkGray }
function Warn  { param($m) Write-Host "    (warn) $m"     -ForegroundColor Yellow }
function Would { param($m) Write-Host "    (dry-run) $m"  -ForegroundColor Magenta }

function Test-DeveloperMode {
    $key = Get-ItemProperty `
        -Path  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' `
        -ErrorAction SilentlyContinue
    return $key -and $key.AllowDevelopmentWithoutDevLicense -eq 1
}

function New-Symlink {
    param([string]$Path, [string]$Target, [string]$MigrateTo = '')
    if (Test-Path $Path) {
        if ((Get-Item $Path).LinkType -eq 'SymbolicLink') {
            Skip "Already symlinked: $Path"
            return
        }
        if ($MigrateTo) {
            if ($DryRun) {
                Would "Move existing $Path -> $MigrateTo, then symlink $Path -> $Target"
                return
            }
            Move-Item -Path $Path -Destination $MigrateTo
            Done "Migrated existing file to $MigrateTo"
        } else {
            Warn "$Path exists but is not a symlink — skipping. Rename it to proceed."
            return
        }
    }
    if ($DryRun) {
        Would "New-Item -ItemType SymbolicLink -Path $Path -Target $Target"
        return
    }
    $parent = Split-Path $Path -Parent
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    New-Item -ItemType SymbolicLink -Path $Path -Target $Target | Out-Null
    Done "Linked: $Path -> $Target"
}

if ($DryRun) {
    Write-Host "`n[DRY RUN] No changes will be made.`n" -ForegroundColor Magenta
}

# ─── Scoop ─────────────────────────────────────────────────────────────────────
Step "Scoop"
if (Get-Command scoop -ErrorAction SilentlyContinue) {
    Skip "Already installed"
} elseif ($DryRun) {
    Would "Install Scoop (Invoke-RestMethod https://get.scoop.sh | Invoke-Expression)"
} else {
    $ErrorActionPreference = 'Continue'
    Invoke-RestMethod -Uri 'https://get.scoop.sh' | Invoke-Expression
    $ErrorActionPreference = 'Stop'
    Done "Installed"
}

# ─── Scoop buckets ─────────────────────────────────────────────────────────────
Step "Scoop buckets"
foreach ($bucket in @('main', 'extras', 'nerd-fonts')) {
    if ($DryRun) {
        Would "scoop bucket add $bucket"
    } else {
        $out = scoop bucket add $bucket 2>&1
        if ($out -match 'already') { Skip $bucket } else { Done "Added: $bucket" }
    }
}

# ─── Scoop packages ────────────────────────────────────────────────────────────
# Map scoop package name -> binary to check with Get-Command.
# Empty string = no binary check (e.g. fonts); fall through to scoop's own idempotency.
Step "Scoop packages"

$packages = [ordered]@{
    # Shell / prompt
    'starship'         = 'starship'
    'zoxide'           = 'zoxide'
    # Modern replacements (also covered by aliases in profile.ps1)
    'eza'              = 'eza'
    'bat'              = 'bat'
    'fd'               = 'fd'
    'ripgrep'          = 'rg'
    'fzf'              = 'fzf'
    # Unix coreutils gap-filler (ln, touch, wc, head, tail, xargs, etc.)
    'uutils-coreutils' = 'touch'
    # Editors / multiplexers
    'neovim'           = 'nvim'
    'zellij'           = 'zellij'
    # System monitoring
    'bottom'           = 'btm'
    # Nerd Font — no binary, scoop handles idempotency
    'JetBrainsMono-NF' = ''
}

foreach ($pkg in $packages.Keys) {
    $bin = $packages[$pkg]
    if ($bin -and (Get-Command $bin -ErrorAction SilentlyContinue)) {
        Skip "$pkg ($bin already on PATH)"
    } elseif ($DryRun) {
        Would "scoop install $pkg"
    } else {
        $out = scoop install $pkg 2>&1 | Out-String
        if ($out -match 'ERROR') {
            Warn "Failed to install $pkg — check output above"
        } else {
            Done "Installed: $pkg"
        }
    }
}

# ─── winget fallback ───────────────────────────────────────────────────────────
# For packages not available in Scoop, add them here.
Step "winget (fallback packages)"
if (Get-Command winget -ErrorAction SilentlyContinue) {
    $wingetPackages = @(
        # 'Publisher.PackageId'  # comment explaining why not in Scoop
    )
    if ($wingetPackages.Count -eq 0) {
        Skip "No winget-only packages configured"
    } else {
        foreach ($id in $wingetPackages) {
            if ($DryRun) {
                Would "winget install --id $id"
            } else {
                winget install --id $id --silent --accept-source-agreements --accept-package-agreements
                Done "Installed via winget: $id"
            }
        }
    }
} else {
    Skip "winget not available"
}

# ─── PSFzf module ──────────────────────────────────────────────────────────────
Step "PSFzf (PowerShell fzf integration)"
if (Get-Module -ListAvailable -Name PSFzf) {
    Skip "Already installed"
} elseif ($DryRun) {
    Would "Install-Module -Name PSFzf -Force -Scope CurrentUser"
} else {
    Install-Module -Name PSFzf -Force -Scope CurrentUser
    Done "Installed"
}

# ─── Catppuccin for Windows Terminal ───────────────────────────────────────────
# Uses the Fragment API (Windows Terminal 1.11+): drop JSON into the Fragments
# directory and Windows Terminal auto-discovers it — no settings.json editing.
# The repo ships bare JSON objects (not pre-wrapped), so we download mocha.json
# (color scheme) and mochaTheme.json (tab/window chrome) and compose them here.
Step "Catppuccin theme (Windows Terminal)"
$fragmentDir  = "$env:LOCALAPPDATA\Microsoft\Windows Terminal\Fragments\Catppuccin"
$fragmentFile = "$fragmentDir\catppuccin-mocha.json"
if (Test-Path $fragmentFile) {
    Skip "Already installed"
} elseif ($DryRun) {
    Would "Fetch mocha.json + mochaTheme.json, compose fragment -> $fragmentFile"
} else {
    New-Item -ItemType Directory -Path $fragmentDir -Force | Out-Null
    $base = 'https://raw.githubusercontent.com/catppuccin/windows-terminal/main'
    $scheme = (Invoke-WebRequest -Uri "$base/mocha.json"      -UseBasicParsing).Content | ConvertFrom-Json
    $theme  = (Invoke-WebRequest -Uri "$base/mochaTheme.json" -UseBasicParsing).Content | ConvertFrom-Json
    @{ schemes = @($scheme); themes = @($theme) } | ConvertTo-Json -Depth 10 | Set-Content $fragmentFile
    Done "Installed — restart Windows Terminal, then set Catppuccin Mocha as your color scheme"
}

# ─── Developer Mode ────────────────────────────────────────────────────────────
# Required for creating symlinks as a normal user. Triggers a UAC prompt.
Step "Developer Mode"
if (Test-DeveloperMode) {
    Skip "Already enabled"
} elseif ($DryRun) {
    Would "Enable Developer Mode (AllowDevelopmentWithoutDevLicense=1 in HKLM — triggers UAC)"
} else {
    $regCmd = @'
$path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
Set-ItemProperty -Path $path -Name AllowDevelopmentWithoutDevLicense -Value 1 -Type DWord
Set-ItemProperty -Path $path -Name AllowAllTrustedApps               -Value 1 -Type DWord
'@
    Start-Process pwsh -Verb RunAs -ArgumentList "-NoProfile -Command $regCmd" -Wait
    if (Test-DeveloperMode) {
        Done "Developer Mode enabled"
    } else {
        Warn "Could not confirm Developer Mode — symlinks may fail. Enable manually: Settings > Privacy & Security > For developers"
    }
}

# ─── Dotfile symlinks ──────────────────────────────────────────────────────────
Step "Dotfile symlinks"
New-Symlink -Path $PROFILE -Target "$RepoRoot\profile.ps1" -MigrateTo (Join-Path $HOME 'profile.local.ps1')
New-Symlink -Path "$env:LOCALAPPDATA\nvim\init.lua" -Target "$RepoRoot\init.lua"

# ─── Done ──────────────────────────────────────────────────────────────────────
if ($DryRun) {
    Write-Host "`n[DRY RUN] Complete. No changes were made.`n" -ForegroundColor Magenta
} else {
    Write-Host "`nDone! Open a new PowerShell 7 terminal to load the profile.`n" -ForegroundColor Green
}
