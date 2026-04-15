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
    Symlinking requires Developer Mode or an elevated shell.
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

function New-Symlink {
    param([string]$Path, [string]$Target)
    if (Test-Path $Path) {
        if ((Get-Item $Path).LinkType -eq 'SymbolicLink') {
            Skip "Already symlinked: $Path"
        } else {
            Warn "$Path exists but is not a symlink — skipping. Rename it to proceed."
        }
        return
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
Step "Scoop packages"

$packages = @(
    # Shell / prompt
    'starship'
    'zoxide'
    # Modern replacements (also covered by aliases in profile.ps1)
    'eza'
    'bat'
    'fd'
    'ripgrep'
    'fzf'
    # Unix coreutils gap-filler (ln, touch, wc, head, tail, xargs, etc.)
    'uutils-coreutils'
    # Editors / multiplexers
    'neovim'
    'zellij'
    # System monitoring
    'bottom'
    # Nerd Font (nerd-fonts bucket)
    'JetBrainsMono-NF'
)

if ($DryRun) {
    # Use scoop list to distinguish already-installed packages if scoop is available
    $installedPkgs = if (Get-Command scoop -ErrorAction SilentlyContinue) {
        (scoop list 2>$null).Name
    } else { @() }
    foreach ($pkg in $packages) {
        if ($installedPkgs -contains $pkg) { Skip $pkg }
        else { Would "scoop install $pkg" }
    }
} else {
    foreach ($pkg in $packages) {
        $out = scoop install $pkg 2>&1 | Out-String
        if ($out -match "'$pkg' \($([regex]::Escape($pkg))\) is already installed") {
            Skip $pkg
        } elseif ($out -match 'ERROR') {
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
Step "Catppuccin theme (Windows Terminal)"
$fragmentDir  = "$env:LOCALAPPDATA\Microsoft\Windows Terminal\Fragments\Catppuccin"
$fragmentFile = "$fragmentDir\catppuccin.json"
if (Test-Path $fragmentFile) {
    Skip "Already installed"
} elseif ($DryRun) {
    Would "Download catppuccin.json -> $fragmentFile"
} else {
    New-Item -ItemType Directory -Path $fragmentDir -Force | Out-Null
    $url = 'https://raw.githubusercontent.com/catppuccin/windows-terminal/main/catppuccin.json'
    Invoke-WebRequest -Uri $url -OutFile $fragmentFile -UseBasicParsing
    Done "Installed — restart Windows Terminal, then set Catppuccin Mocha as your color scheme"
}

# ─── Dotfile symlinks ──────────────────────────────────────────────────────────
# Requires Developer Mode (Settings > Privacy & Security > For developers) or
# an elevated (admin) shell to create symlinks on Windows.
Step "Dotfile symlinks"
New-Symlink -Path $PROFILE                          -Target "$RepoRoot\profile.ps1"
New-Symlink -Path "$env:LOCALAPPDATA\nvim\init.lua" -Target "$RepoRoot\init.lua"

# ─── Done ──────────────────────────────────────────────────────────────────────
if ($DryRun) {
    Write-Host "`n[DRY RUN] Complete. No changes were made.`n" -ForegroundColor Magenta
} else {
    Write-Host "`nDone! Open a new PowerShell 7 terminal to load the profile.`n" -ForegroundColor Green
}
