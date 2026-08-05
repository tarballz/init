#!/usr/bin/env bash
# macOS-only setup: system `defaults` + per-account glue (SSH keychain, gh, OrbStack).
# Sourced by init.sh on Darwin, but also runnable standalone:  bash macos.sh [--dry-run]
# Idempotent — `defaults write` overwrites in place; every account step is guarded.

# ── Standalone bootstrap (skipped when sourced from init.sh, which already set these) ──
if ! declare -f log >/dev/null 2>&1; then
  set -euo pipefail
  GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; NC='\033[0m'
  log()  { echo -e "${GREEN}[+]${NC} $1"; }
  warn() { echo -e "${YELLOW}[!]${NC} $1"; }
  step() { echo -e "\n${BLUE}===>${NC} $1"; }
  would(){ echo -e "${MAGENTA}[dry-run]${NC} $1"; }
  ok()   { command -v "$1" &>/dev/null; }
  DRY_RUN=false
  for arg in "${@:-}"; do [ "$arg" = "--dry-run" ] && DRY_RUN=true; done
fi

if [ "$(uname -s)" != "Darwin" ]; then
  warn "macos.sh is macOS-only — skipping"
  return 0 2>/dev/null || exit 0
fi

# run CMD...  — execute unless in dry-run, in which case just print it
run() {
  if [ "${DRY_RUN:-false}" = true ]; then would "$*"; else "$@"; fi
}

# ── System defaults ───────────────────────────────────────────────────────────
# Opinionated but reversible: every one of these can be flipped with `defaults write`
# back to its old value, or deleted with `defaults delete <domain> <key>`.
step "macOS system defaults"

# Finder
run defaults write NSGlobalDomain AppleShowAllExtensions -bool true
run defaults write com.apple.finder AppleShowAllFiles -bool true
run defaults write com.apple.finder ShowPathbar -bool true
run defaults write com.apple.finder ShowStatusBar -bool true
run defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"   # list view
run defaults write com.apple.finder _FXShowPosixPathInTitle -bool true
run defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"   # search current folder
run defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
run defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true

# Keyboard / text — the important one: enable key-repeat in every app (vim, editors).
run defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
run defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
run defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
run defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
run defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
run defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false

# Trackpad — disable the "Look up & data detectors" popup (force-click + three-finger tap).
run defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerTapGesture -int 0
run defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerTapGesture -int 0
run defaults write NSGlobalDomain com.apple.trackpad.forceClick -bool false

# Screenshots into ~/Screenshots instead of littering the Desktop.
run mkdir -p "$HOME/Screenshots"
run defaults write com.apple.screencapture location "$HOME/Screenshots"
run defaults write com.apple.screencapture disable-shadow -bool true

# Save/print panels expanded; default new documents to disk, not iCloud.
run defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
run defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true
run defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
run defaults write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false

if [ "${DRY_RUN:-false}" = true ]; then
  would "killall Finder Dock SystemUIServer"
else
  killall Finder Dock SystemUIServer 2>/dev/null || true
  log "System defaults applied (some changes need a logout/login to fully take effect)"
fi

# ── Account glue ──────────────────────────────────────────────────────────────
step "SSH key → keychain"
if [ -f "$HOME/.ssh/id_ed25519" ]; then
  run ssh-add --apple-use-keychain "$HOME/.ssh/id_ed25519"
else
  warn "No ~/.ssh/id_ed25519 — generate one with: ssh-keygen -t ed25519 -C \"$USER@$(hostname -s)\""
fi

step "GitHub CLI"
if ok gh; then
  if gh auth status >/dev/null 2>&1; then
    log "gh already authenticated"
    # Register the key as a SIGNING key (separate from the auth key). Harmless if present.
    if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
      run gh ssh-key add "$HOME/.ssh/id_ed25519.pub" --type signing --title "$(hostname -s) signing"
    fi
  else
    warn "gh is not logged in — run:  gh auth login"
    warn "Then re-run this script to register the SSH signing key."
  fi
else
  warn "gh not installed (expected via Homebrew: brew install gh)"
fi

step "OrbStack (docker/orb CLI)"
if ok docker; then
  log "docker already on PATH"
elif [ -d "/Applications/OrbStack.app" ]; then
  run open -a OrbStack
  warn "OrbStack launched — accept its prompt to install the CLI, then: docker run --rm hello-world"
else
  warn "OrbStack not installed (expected via Homebrew: brew install --cask orbstack)"
fi
