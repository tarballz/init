#!/usr/bin/env bash
# Fresh system bootstrap script
# Installs: zsh, uv, ruff, pyright, starship, zellij, claude, neovim, bottom,
#           bat, zoxide, fzf, eza, fd, ripgrep, zsh-autosuggestions,
#           zsh-syntax-highlighting, FiraCode Nerd Font, tree-sitter CLI
# Symlinks: ~/.zshrc -> <repo>/zshrc, ~/.config/nvim/init.lua -> <repo>/init.lua
# Catppuccin mocha theme for: starship, zellij, bottom, bat, zsh-syntax-highlighting
#   (neovim catppuccin is handled by init.lua via lazy.nvim)
# Usage: ./init.sh [--dry-run]
#
# Each install/config step below runs through run_step, which catches that
# step's failure (network blip, rate-limited API, missing package, ...),
# warns, and moves on to the rest of the bootstrap instead of aborting the
# whole run. Failed steps are summarized at the end; re-running init.sh
# retries only what didn't succeed (everything else reports "already
# installed"/"already present" and is a no-op). Environment prerequisites
# (unsupported OS/architecture, no package manager) still hard-exit — nothing
# downstream can proceed sensibly without those.
#
# Note on how step functions are written: calling a step function through
# `if ! step_fn; then ...` (which is what run_step does) puts bash's errexit
# (-e) in "being tested" mode for that ENTIRE call — including everything the
# function does, and even a nested `set -e` inside it can't turn that back on
# (this is a real, well-documented bash quirk, not a mistake below). So step
# functions don't rely on implicit -e to stop at a failed command; each risky
# command (network calls, package installs, sudo writes) is explicitly
# followed by `|| return 1` so a failure stops that step immediately without
# silently continuing as if it had succeeded.
set -euo pipefail

CATPPUCCIN_FLAVOR="mocha"

# ── Flags ─────────────────────────────────────────────────────────────────────
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

# ── Colors ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; RED='\033[0;31m'
MAGENTA='\033[0;35m'; NC='\033[0m'
log()   { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
err()   { echo -e "${RED}[✗]${NC} $1" >&2; }
step()  { echo -e "\n${BLUE}===>${NC} $1"; }
would() { echo -e "${MAGENTA}[dry-run]${NC} $1"; }
ok()    { command -v "$1" &>/dev/null; }

# Runs a step function; a failure inside is caught here (rather than
# aborting the whole script) and recorded so the final summary can tell you
# what to retry.
FAILED_STEPS=()
run_step() {
  local name="$1"; shift
  if ! "$@"; then
    warn "$name failed — skipping (re-run init.sh later to retry just this step)"
    FAILED_STEPS+=("$name")
  fi
}

if [ "$DRY_RUN" = true ]; then
  echo -e "\n${MAGENTA}[DRY RUN] No changes will be made.${NC}\n"
fi

# ── Terminal type (terminfo) ────────────────────────────────────────────────
# A fresh box's terminfo database rarely covers newer/niche terminal emulators
# (Ghostty, Kitty, ...) — SSH forwards $TERM from the client, but the matching
# terminfo entry only exists if this machine's ncurses database happens to
# ship it. Without it, zsh's line editor loses track of cursor position:
# characters land in the wrong place, backspace looks broken, etc. The fix has
# to run FROM the client (it already has the correct entry installed), so this
# only detects the problem and prints the one-liner to fix it.
step "Terminal type (terminfo)"
if [ -z "${TERM:-}" ]; then
  warn "\$TERM is unset — skipping terminfo check"
elif infocmp "$TERM" >/dev/null 2>&1; then
  log "terminfo entry for TERM=$TERM found"
else
  if command -v hostname >/dev/null 2>&1 && hostname -I >/dev/null 2>&1; then
    TARGET_ADDR="$(hostname -I | awk '{print $1}')"
  else
    TARGET_ADDR="$(hostname 2>/dev/null || echo "<this-host>")"
  fi
  warn "No terminfo entry for TERM=$TERM on this machine — zsh's line editor may lose track of the cursor (garbled typing, broken backspace)."
  warn "Fix from your LOCAL machine (the one already displaying this terminal correctly):"
  warn "  infocmp -x $TERM | ssh $(whoami)@$TARGET_ADDR -- tic -x -"
fi

# ── Operating system ──────────────────────────────────────────────────────────
case "$(uname -s)" in
  Linux)  IS_MAC=false ;;
  Darwin) IS_MAC=true  ;;
  *) err "Unsupported OS: $(uname -s) (supported: Linux, macOS)"; exit 1 ;;
esac

# Portable in-place sed (BSD sed on macOS needs an explicit empty backup suffix).
sed_i() { if [ "$IS_MAC" = true ]; then sed -i '' "$@"; else sed -i "$@"; fi; }

# ── Architecture ──────────────────────────────────────────────────────────────
# ARCH_MUSL / NVIM_ARCH / TS_ARCH / EZA_ARCH only feed the Linux release-tarball
# URLs; on macOS every tool comes from Homebrew, so these values go unused there.
# eza publishes no aarch64 musl build (only x86_64), so it gets its own variable
# pinned to the aarch64 gnu asset instead of reusing ARCH_MUSL.
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)        ARCH_MUSL="x86_64-unknown-linux-musl"  ; NVIM_ARCH="x86_64" ; TS_ARCH="x64"   ; EZA_ARCH="x86_64-unknown-linux-musl"  ;;
  aarch64|arm64) ARCH_MUSL="aarch64-unknown-linux-musl" ; NVIM_ARCH="arm64"  ; TS_ARCH="arm64" ; EZA_ARCH="aarch64-unknown-linux-gnu" ;;
  *) err "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# ── Package manager ───────────────────────────────────────────────────────────
if [ "$IS_MAC" = true ]; then
  if ! ok brew; then
    err "Homebrew not found. Install it from https://brew.sh, then re-run."; exit 1
  fi
  PKG_UPDATE="brew update"
  PKG_INSTALL="brew install"
elif ok apt-get; then
  PKG_UPDATE="sudo apt-get update -qq"
  PKG_INSTALL="sudo apt-get install -y"
elif ok dnf; then
  PKG_UPDATE="sudo dnf check-update -q || true"
  PKG_INSTALL="sudo dnf install -y"
elif ok pacman; then
  PKG_UPDATE="sudo pacman -Sy --noconfirm"
  PKG_INSTALL="sudo pacman -S --noconfirm"
else
  err "No supported package manager found (apt/dnf/pacman)"; exit 1
fi

# ── Helpers ───────────────────────────────────────────────────────────────────
latest_gh_tag() {
  curl -fsSL "https://api.github.com/repos/$1/releases/latest" \
    | grep '"tag_name"' | head -1 | cut -d'"' -f4
}

install_binary_from_tar() {
  # $1=url  $2=binary-name  $3=dest (default /usr/local/bin)
  local url="$1" bin="$2" dest="${3:-/usr/local/bin}"
  if [ "$DRY_RUN" = true ]; then
    would "Download and install $bin from $url -> $dest/$bin"
    return
  fi
  local tmp found
  tmp=$(mktemp -d) || return 1
  curl -fsSL "$url" | tar -xz -C "$tmp" || { rm -rf "$tmp"; return 1; }
  found="$(find "$tmp" -name "$bin" -type f | head -1)"
  if [ -z "$found" ]; then
    err "Downloaded archive from $url did not contain a '$bin' binary"
    rm -rf "$tmp"
    return 1
  fi
  sudo install -m 755 "$found" "$dest/$bin" || { rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"
}

link_dotfile() {
  # $1=source (in repo)  $2=target (in $HOME / .config)
  local src="$1" dest="$2"
  if [ "$DRY_RUN" = true ]; then
    if [ -L "$dest" ]; then
      log "(skip) Symlink already exists: $dest -> $(readlink "$dest")"
    elif [ -e "$dest" ]; then
      would "Backup $dest -> ${dest}.backup.TIMESTAMP, then ln -s $src $dest"
    else
      would "ln -s $src $dest"
    fi
    return
  fi
  mkdir -p "$(dirname "$dest")" || return 1
  if [ -L "$dest" ]; then
    ln -sfn "$src" "$dest" || return 1
    log "Symlink refreshed: $dest -> $src"
  elif [ -e "$dest" ]; then
    local backup="${dest}.backup.$(date +%Y%m%d-%H%M%S)"
    mv "$dest" "$backup" || return 1
    ln -s "$src" "$dest" || return 1
    warn "Existing $dest backed up to $backup"
    log "Linked $src -> $dest"
  else
    ln -s "$src" "$dest" || return 1
    log "Linked $src -> $dest"
  fi
}

# ── Update package lists ──────────────────────────────────────────────────────
step_pkg_update() {
  if [ "$DRY_RUN" = true ]; then
    would "$PKG_UPDATE"
  else
    $PKG_UPDATE || return 1
  fi
}
step "Updating package lists"
run_step "Updating package lists" step_pkg_update

# ── Base build tools & git ────────────────────────────────────────────────────
step_base_deps() {
  if [ "$IS_MAC" = true ]; then
    # git, curl, make and clang (the C compiler for treesitter) ship with the
    # Xcode Command Line Tools, which are also a prerequisite for Homebrew itself.
    if ! xcode-select -p >/dev/null 2>&1; then
      if [ "$DRY_RUN" = true ]; then
        would "xcode-select --install"
      else
        warn "Xcode Command Line Tools not found — launching the installer"
        xcode-select --install || true
        err "Finish the Command Line Tools install dialog, then re-run this script"
        return 1
      fi
    fi
    if [ "$DRY_RUN" = true ]; then
      would "$PKG_INSTALL git curl wget unzip"
    else
      $PKG_INSTALL git curl wget unzip || return 1
      log "Base dependencies ready"
    fi
  elif [ "$DRY_RUN" = true ]; then
    if ok apt-get || ok dnf; then
      would "$PKG_INSTALL git curl wget unzip gcc make"
    elif ok pacman; then
      would "$PKG_INSTALL git curl wget unzip base-devel"
    fi
  else
    if ok apt-get; then
      $PKG_INSTALL git curl wget unzip gcc make || return 1
    elif ok dnf; then
      $PKG_INSTALL git curl wget unzip gcc make || return 1
    elif ok pacman; then
      $PKG_INSTALL git curl wget unzip base-devel || return 1
    fi
    log "Base dependencies ready"
  fi
}
step "Base build dependencies"
run_step "Base build dependencies" step_base_deps

# ── zsh ───────────────────────────────────────────────────────────────────────
step_zsh() {
  if ! ok zsh; then
    if [ "$DRY_RUN" = true ]; then
      would "$PKG_INSTALL zsh"
    else
      $PKG_INSTALL zsh || return 1
      log "zsh installed"
    fi
  else
    log "zsh already installed: $(zsh --version)"
  fi

  if [ "$SHELL" != "$(command -v zsh)" ]; then
    if [ "$DRY_RUN" = true ]; then
      would "chsh -s $(command -v zsh)"
    else
      log "Setting zsh as default shell (you may be prompted for your password)"
      chsh -s "$(command -v zsh)" || return 1
      warn "Log out and back in for the shell change to take effect"
    fi
  else
    log "zsh is already the default shell"
  fi
}
step "zsh"
run_step "zsh" step_zsh

# $HOME/.local/bin is where uv, uv-tool-installed CLIs (ruff, pyright), and a
# few other steps below land their binaries. Export it before the first `ok`
# check that depends on it — a bare `bash init.sh` over SSH runs non-login, so
# nothing has put it on PATH yet. Without this, `ok uv` below would report a
# false negative on every re-run and reinstall uv (and, since ~/.zshrc is a
# symlink into this repo by the time "Shell config" has run once, each
# reinstall's installer script would append its shell-env sourcing line
# straight into the tracked zshrc).
export PATH="$HOME/.local/bin:$PATH"

# ── uv ────────────────────────────────────────────────────────────────────────
step_uv() {
  if ! ok uv; then
    if [ "$DRY_RUN" = true ]; then
      would "curl -LsSf https://astral.sh/uv/install.sh | sh"
    else
      curl -LsSf https://astral.sh/uv/install.sh | sh || return 1
      log "uv installed"
    fi
  else
    log "uv already installed: $(uv --version)"
  fi
}
step "uv"
run_step "uv" step_uv

# ── ruff (via uv tool) ────────────────────────────────────────────────────────
step_ruff() {
  if ! ok ruff; then
    if [ "$DRY_RUN" = true ]; then
      would "uv tool install ruff"
    else
      uv tool install ruff || return 1
      log "ruff installed"
    fi
  else
    log "ruff already installed: $(ruff --version)"
  fi
}
step "ruff"
run_step "ruff" step_ruff

# ── pyright (via uv tool) ─────────────────────────────────────────────────────
step_pyright() {
  if ! ok pyright; then
    if [ "$DRY_RUN" = true ]; then
      would "uv tool install pyright"
    else
      uv tool install pyright || return 1
      log "pyright installed"
    fi
  else
    log "pyright already installed: $(pyright --version)"
  fi
}
step "pyright"
run_step "pyright" step_pyright

# ── starship ──────────────────────────────────────────────────────────────────
step_starship() {
  if ! ok starship; then
    if [ "$DRY_RUN" = true ]; then
      would "curl -fsSL https://starship.rs/install.sh | sh -s -- --yes"
    else
      curl -fsSL https://starship.rs/install.sh | sh -s -- --yes || return 1
      log "starship installed"
    fi
  else
    log "starship already installed: $(starship --version | head -1)"
  fi
}
step "starship"
run_step "starship" step_starship

# ── Claude Code ───────────────────────────────────────────────────────────────
step_claude() {
  if ! ok claude; then
    if [ "$DRY_RUN" = true ]; then
      would "curl -fsSL https://claude.ai/install.sh | bash"
    else
      curl -fsSL https://claude.ai/install.sh | bash || return 1
      log "Claude Code installed"
    fi
  else
    log "Claude Code already installed: $(claude --version 2>/dev/null || echo 'unknown version')"
  fi
}
step "Claude Code"
run_step "Claude Code" step_claude

# ── Neovim ────────────────────────────────────────────────────────────────────
step_neovim() {
  if ! ok nvim; then
    if [ "$IS_MAC" = true ]; then
      if [ "$DRY_RUN" = true ]; then
        would "$PKG_INSTALL neovim"
      else
        $PKG_INSTALL neovim || return 1
        log "Neovim installed: $(nvim --version | head -1)"
      fi
    elif [ "$DRY_RUN" = true ]; then
      would "Download and install nvim-linux-${NVIM_ARCH}.tar.gz -> /usr/local/"
    else
      local tmp; tmp=$(mktemp -d) || return 1
      curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${NVIM_ARCH}.tar.gz" \
        | tar -xz -C "$tmp" || { rm -rf "$tmp"; return 1; }
      sudo cp -r "$tmp/nvim-linux-${NVIM_ARCH}/"* /usr/local/ || { rm -rf "$tmp"; return 1; }
      rm -rf "$tmp"
      log "Neovim installed: $(nvim --version | head -1)"
    fi
  else
    log "Neovim already installed: $(nvim --version | head -1)"
  fi
}
step "Neovim"
run_step "Neovim" step_neovim

# ── Zellij ────────────────────────────────────────────────────────────────────
step_zellij() {
  if ! ok zellij; then
    if [ "$IS_MAC" = true ]; then
      if [ "$DRY_RUN" = true ]; then
        would "$PKG_INSTALL zellij"
      else
        $PKG_INSTALL zellij || return 1
        log "Zellij installed: $(zellij --version)"
      fi
    elif [ "$DRY_RUN" = true ]; then
      would "install_binary_from_tar zellij-org/zellij -> zellij-${ARCH_MUSL}.tar.gz"
    else
      local tag; tag=$(latest_gh_tag "zellij-org/zellij") || return 1
      install_binary_from_tar \
        "https://github.com/zellij-org/zellij/releases/download/${tag}/zellij-${ARCH_MUSL}.tar.gz" \
        "zellij" || return 1
      log "Zellij installed: $(zellij --version)"
    fi
  else
    log "Zellij already installed: $(zellij --version)"
  fi
}
step "Zellij"
run_step "Zellij" step_zellij

# ── Bottom (btm) ──────────────────────────────────────────────────────────────
step_bottom() {
  if ! ok btm; then
    if [ "$IS_MAC" = true ]; then
      if [ "$DRY_RUN" = true ]; then
        would "$PKG_INSTALL bottom"
      else
        $PKG_INSTALL bottom || return 1
        log "Bottom installed: $(btm --version)"
      fi
    elif [ "$DRY_RUN" = true ]; then
      would "install_binary_from_tar ClementTsang/bottom -> bottom_${ARCH_MUSL}.tar.gz"
    else
      local tag; tag=$(latest_gh_tag "ClementTsang/bottom") || return 1
      install_binary_from_tar \
        "https://github.com/ClementTsang/bottom/releases/download/${tag}/bottom_${ARCH_MUSL}.tar.gz" \
        "btm" || return 1
      log "Bottom installed: $(btm --version)"
    fi
  else
    log "Bottom already installed: $(btm --version)"
  fi
}
step "Bottom (btm)"
run_step "Bottom (btm)" step_bottom

# ── fd (Telescope file finder) ────────────────────────────────────────────────
step_fd() {
  if ! ok fd; then
    if [ "$IS_MAC" = true ]; then
      if [ "$DRY_RUN" = true ]; then
        would "$PKG_INSTALL fd"
      else
        $PKG_INSTALL fd || return 1
        log "fd installed"
      fi
    elif [ "$DRY_RUN" = true ]; then
      would "$PKG_INSTALL fd-find (+ symlink fdfind -> fd on Debian/Ubuntu)"
    else
      if ok apt-get; then
        $PKG_INSTALL fd-find || return 1
        if ok fdfind && ! ok fd; then
          mkdir -p "$HOME/.local/bin"
          ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
          log "Created symlink: fd -> fdfind"
        fi
      elif ok dnf; then
        $PKG_INSTALL fd-find || return 1
      elif ok pacman; then
        $PKG_INSTALL fd || return 1
      fi
      log "fd installed"
    fi
  else
    log "fd already installed: $(fd --version)"
  fi
}
step "fd"
run_step "fd" step_fd

# ── eza (modern ls replacement) ──────────────────────────────────────────────
step_eza() {
  if ! ok eza; then
    if [ "$IS_MAC" = true ]; then
      if [ "$DRY_RUN" = true ]; then
        would "$PKG_INSTALL eza"
      else
        $PKG_INSTALL eza || return 1
        log "eza installed: $(eza --version | head -1)"
      fi
    elif [ "$DRY_RUN" = true ]; then
      would "install_binary_from_tar eza-community/eza -> eza_${EZA_ARCH}.tar.gz"
    else
      local tag; tag=$(latest_gh_tag "eza-community/eza") || return 1
      install_binary_from_tar \
        "https://github.com/eza-community/eza/releases/download/${tag}/eza_${EZA_ARCH}.tar.gz" \
        "eza" || return 1
      log "eza installed: $(eza --version | head -1)"
    fi
  else
    log "eza already installed: $(eza --version | head -1)"
  fi
}
step "eza"
run_step "eza" step_eza

# ── FiraCode Nerd Font Mono ───────────────────────────────────────────────────
step_firacode() {
  if [ "$IS_MAC" = true ]; then
    # macOS has no fontconfig (fc-list/fc-cache); install via the Homebrew cask,
    # which drops the .ttf files into ~/Library/Fonts.
    if brew list --cask font-fira-code-nerd-font >/dev/null 2>&1; then
      log "FiraCode Nerd Font Mono already installed"
    elif [ "$DRY_RUN" = true ]; then
      would "$PKG_INSTALL --cask font-fira-code-nerd-font"
    else
      $PKG_INSTALL --cask font-fira-code-nerd-font || return 1
      log "FiraCode Nerd Font Mono installed"
    fi
  else
    # fc-list/fc-cache come from the fontconfig package, which isn't installed
    # by default on minimal distros (e.g. Raspberry Pi OS/Debian) — install it
    # first so the fc-cache call below doesn't abort the step.
    if ! ok fc-list; then
      if [ "$DRY_RUN" = true ]; then
        would "$PKG_INSTALL fontconfig"
      else
        $PKG_INSTALL fontconfig || return 1
        log "fontconfig installed"
      fi
    fi

    local font_dir="$HOME/.local/share/fonts"
    if ok fc-list && fc-list | grep -qi "FiraCode Nerd"; then
      log "FiraCode Nerd Font Mono already installed"
    elif [ "$DRY_RUN" = true ]; then
      would "Download FiraCode.zip from nerd-fonts and install *Mono*.ttf -> $font_dir/"
    else
      mkdir -p "$font_dir"
      local tmp; tmp=$(mktemp -d) || return 1
      curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip" \
        -o "$tmp/FiraCode.zip" || { rm -rf "$tmp"; return 1; }
      unzip -q "$tmp/FiraCode.zip" -d "$tmp/FiraCode" || { rm -rf "$tmp"; return 1; }
      cp "$tmp/FiraCode/"*Mono*.ttf "$font_dir/" || { rm -rf "$tmp"; return 1; }
      fc-cache -f "$font_dir" || { rm -rf "$tmp"; return 1; }
      rm -rf "$tmp"
      log "FiraCode Nerd Font Mono installed"
    fi
  fi
}
step "FiraCode Nerd Font Mono"
run_step "FiraCode Nerd Font Mono" step_firacode

# ── tree-sitter CLI (nvim-treesitter parser compilation) ─────────────────────
step_treesitter() {
  if ! ok tree-sitter; then
    if [ "$IS_MAC" = true ]; then
      # The Homebrew `tree-sitter` formula is the library only (and is pulled in
      # as a neovim dependency); the CLI that nvim-treesitter's build hook needs
      # lives in the separate `tree-sitter-cli` formula, which provides `tree-sitter`.
      if [ "$DRY_RUN" = true ]; then
        would "$PKG_INSTALL tree-sitter-cli"
      else
        $PKG_INSTALL tree-sitter-cli || return 1
        log "tree-sitter installed: $(tree-sitter --version)"
      fi
    elif [ "$DRY_RUN" = true ]; then
      would "Download tree-sitter-linux-${TS_ARCH}.gz -> /usr/local/bin/tree-sitter"
    else
      local tag; tag=$(latest_gh_tag "tree-sitter/tree-sitter") || return 1
      curl -fsSL "https://github.com/tree-sitter/tree-sitter/releases/download/${tag}/tree-sitter-linux-${TS_ARCH}.gz" \
        | gunzip -c > /tmp/tree-sitter || return 1
      sudo install -m 755 /tmp/tree-sitter /usr/local/bin/tree-sitter || { rm -f /tmp/tree-sitter; return 1; }
      rm -f /tmp/tree-sitter
      log "tree-sitter installed: $(tree-sitter --version)"
    fi
  else
    log "tree-sitter already installed: $(tree-sitter --version)"
  fi
}
step "tree-sitter"
run_step "tree-sitter" step_treesitter

# ── ripgrep (Telescope live_grep) ─────────────────────────────────────────────
step_ripgrep() {
  if ! ok rg; then
    if [ "$DRY_RUN" = true ]; then
      would "$PKG_INSTALL ripgrep"
    else
      $PKG_INSTALL ripgrep || return 1
      log "ripgrep installed: $(rg --version | head -1)"
    fi
  else
    log "ripgrep already installed: $(rg --version | head -1)"
  fi
}
step "ripgrep"
run_step "ripgrep" step_ripgrep

# ── bat (modern cat with syntax highlighting) ────────────────────────────────
step_bat() {
  if ! ok bat; then
    if [ "$IS_MAC" = true ]; then
      if [ "$DRY_RUN" = true ]; then
        would "$PKG_INSTALL bat"
      else
        $PKG_INSTALL bat || return 1
        log "bat installed"
      fi
    elif [ "$DRY_RUN" = true ]; then
      would "$PKG_INSTALL bat (+ symlink batcat -> bat on Debian/Ubuntu)"
    else
      if ok apt-get; then
        $PKG_INSTALL bat || return 1
        if ok batcat && ! ok bat; then
          mkdir -p "$HOME/.local/bin"
          ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
          log "Created symlink: bat -> batcat"
        fi
      elif ok dnf; then
        $PKG_INSTALL bat || return 1
      elif ok pacman; then
        $PKG_INSTALL bat || return 1
      fi
      log "bat installed"
    fi
  else
    log "bat already installed: $(bat --version)"
  fi
}
step "bat"
run_step "bat" step_bat

# ── zoxide (smarter cd) ──────────────────────────────────────────────────────
step_zoxide() {
  if ! ok zoxide; then
    if [ "$DRY_RUN" = true ]; then
      would "curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh"
    else
      curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh || return 1
      log "zoxide installed"
    fi
  else
    log "zoxide already installed: $(zoxide --version)"
  fi
}
step "zoxide"
run_step "zoxide" step_zoxide

# ── fzf (fuzzy finder) ───────────────────────────────────────────────────────
# zshrc sources ~/.fzf.zsh for key-bindings + completion, a file the git
# installer writes. On macOS fzf comes from Homebrew, so generate that file
# from `fzf --zsh` instead of cloning a redundant second copy under ~/.fzf.
step_fzf() {
  if [ "$IS_MAC" = true ] && ok fzf; then
    if [ "$DRY_RUN" = true ]; then
      would "fzf --zsh > ~/.fzf.zsh (key-bindings + completion for Homebrew fzf)"
    else
      fzf --zsh > "$HOME/.fzf.zsh" || return 1
      log "fzf already installed (Homebrew); wrote ~/.fzf.zsh"
    fi
  elif [ ! -d "$HOME/.fzf" ]; then
    if [ "$DRY_RUN" = true ]; then
      would "git clone --depth=1 https://github.com/junegunn/fzf.git ~/.fzf && ~/.fzf/install"
    else
      git clone --depth=1 https://github.com/junegunn/fzf.git "$HOME/.fzf" || return 1
      "$HOME/.fzf/install" --key-bindings --completion --no-update-rc --no-bash --no-fish || return 1
      log "fzf installed"
    fi
  else
    log "fzf already present at ~/.fzf"
  fi
}
step "fzf"
run_step "fzf" step_fzf

# ── zsh-autosuggestions ──────────────────────────────────────────────────────
step_zsh_autosuggestions() {
  local dir="$HOME/.zsh/zsh-autosuggestions"
  if [ ! -d "$dir" ]; then
    if [ "$DRY_RUN" = true ]; then
      would "git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git $dir"
    else
      mkdir -p "$HOME/.zsh"
      git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git "$dir" || return 1
      log "zsh-autosuggestions cloned"
    fi
  else
    log "zsh-autosuggestions already present"
  fi
}
step "zsh-autosuggestions"
run_step "zsh-autosuggestions" step_zsh_autosuggestions

# ── zsh-history-substring-search ─────────────────────────────────────────────
step_zsh_hss() {
  local dir="$HOME/.zsh/zsh-history-substring-search"
  if [ ! -d "$dir" ]; then
    if [ "$DRY_RUN" = true ]; then
      would "git clone --depth=1 https://github.com/zsh-users/zsh-history-substring-search.git $dir"
    else
      git clone --depth=1 https://github.com/zsh-users/zsh-history-substring-search.git "$dir" || return 1
      log "zsh-history-substring-search cloned"
    fi
  else
    log "zsh-history-substring-search already present"
  fi
}
step "zsh-history-substring-search"
run_step "zsh-history-substring-search" step_zsh_hss

# ══════════════════════════════════════════════════════════════════════════════
# Catppuccin themes (flavor: mocha — matches neovim config)
# ══════════════════════════════════════════════════════════════════════════════
CATPPUCCIN_RAW="https://raw.githubusercontent.com/catppuccin"

# ── Catppuccin: Starship (palette only, no format changes) ───────────────────
step_catppuccin_starship() {
  local config="$HOME/.config/starship.toml"

  if ! grep -q "\[palettes\.catppuccin_${CATPPUCCIN_FLAVOR}\]" "$config" 2>/dev/null; then
    if [ "$DRY_RUN" = true ]; then
      would "Add catppuccin_${CATPPUCCIN_FLAVOR} palette to $config"
    else
      mkdir -p "$HOME/.config"
      touch "$config"
      if ! grep -q "^palette\s*=" "$config"; then
        local tmp; tmp=$(mktemp) || return 1
        echo "palette = \"catppuccin_${CATPPUCCIN_FLAVOR}\"" | cat - "$config" > "$tmp" || { rm -f "$tmp"; return 1; }
        mv "$tmp" "$config" || return 1
        log "Set palette = catppuccin_${CATPPUCCIN_FLAVOR} in starship.toml"
      fi
      cat >> "$config" << 'EOF' || return 1

[palettes.catppuccin_mocha]
rosewater = "#f5e0dc"
flamingo  = "#f2cdcd"
pink      = "#f5c2e7"
mauve     = "#cba6f7"
red       = "#f38ba8"
maroon    = "#eba0ac"
peach     = "#fab387"
yellow    = "#f9e2af"
green     = "#a6e3a1"
teal      = "#94e2d5"
sky       = "#89dceb"
sapphire  = "#74c7ec"
blue      = "#89b4fa"
lavender  = "#b4befe"
text      = "#cdd6f4"
subtext1  = "#bac2de"
subtext0  = "#a6adc8"
overlay2  = "#9399b2"
overlay1  = "#7f849c"
overlay0  = "#6c7086"
surface2  = "#585b70"
surface1  = "#45475a"
surface0  = "#313244"
base      = "#1e1e2e"
mantle    = "#181825"
crust     = "#11111b"
EOF
      log "Catppuccin mocha palette appended to starship.toml"
    fi
  else
    log "Catppuccin starship palette already present"
  fi
}
step "Catppuccin: Starship"
run_step "Catppuccin: Starship" step_catppuccin_starship

# ── Catppuccin: Zellij ────────────────────────────────────────────────────────
# Catppuccin is bundled in Zellij — just activate it in the config.
step_catppuccin_zellij() {
  local config_dir="$HOME/.config/zellij"
  local config="$config_dir/config.kdl"

  if ! grep -q "^theme " "$config" 2>/dev/null; then
    if [ "$DRY_RUN" = true ]; then
      would "Set theme \"catppuccin-${CATPPUCCIN_FLAVOR}\" in $config"
    else
      mkdir -p "$config_dir"
      if [ ! -f "$config" ]; then
        zellij setup --dump-config > "$config" || return 1
        log "Zellij default config written"
      fi
      if grep -q "// theme" "$config" 2>/dev/null; then
        sed_i "s|// theme.*|theme \"catppuccin-${CATPPUCCIN_FLAVOR}\"|" "$config" || return 1
      else
        echo "" >> "$config"
        echo "theme \"catppuccin-${CATPPUCCIN_FLAVOR}\"" >> "$config"
      fi
      log "Catppuccin ${CATPPUCCIN_FLAVOR} theme set in Zellij config"
    fi
  else
    log "Zellij theme already configured"
  fi
}
step "Catppuccin: Zellij"
run_step "Catppuccin: Zellij" step_catppuccin_zellij

# ── Catppuccin: Bottom ────────────────────────────────────────────────────────
step_catppuccin_bottom() {
  local config="$HOME/.config/bottom/bottom.toml"

  if ! grep -q "^\[styles\.cpu\]" "$config" 2>/dev/null; then
    if [ "$DRY_RUN" = true ]; then
      would "Append Catppuccin ${CATPPUCCIN_FLAVOR} theme to $config"
    else
      mkdir -p "$HOME/.config/bottom"
      curl -fsSL "${CATPPUCCIN_RAW}/bottom/main/themes/${CATPPUCCIN_FLAVOR}.toml" \
        >> "$config" || return 1
      log "Catppuccin ${CATPPUCCIN_FLAVOR} theme appended to $config"
    fi
  else
    log "Catppuccin bottom theme already present"
  fi
}
step "Catppuccin: Bottom"
run_step "Catppuccin: Bottom" step_catppuccin_bottom

# ── Catppuccin: bat ──────────────────────────────────────────────────────────
step_catppuccin_bat() {
  if ok bat; then
    local themes_dir; themes_dir="$(bat --config-dir)/themes"
    if [ ! -f "$themes_dir/Catppuccin Mocha.tmTheme" ]; then
      if [ "$DRY_RUN" = true ]; then
        would "Download Catppuccin Mocha.tmTheme -> $themes_dir/ && bat cache --build"
      else
        mkdir -p "$themes_dir"
        curl -fsSL \
          "${CATPPUCCIN_RAW}/bat/main/themes/Catppuccin%20Mocha.tmTheme" \
          -o "$themes_dir/Catppuccin Mocha.tmTheme" || return 1
        bat cache --build >/dev/null || return 1
        log "Catppuccin Mocha bat theme installed"
      fi
    else
      log "Catppuccin bat theme already present"
    fi
  else
    warn "bat not on PATH yet — skipping bat theme (re-run after restarting shell)"
  fi
}
step "Catppuccin: bat"
run_step "Catppuccin: bat" step_catppuccin_bat

# ── Catppuccin: zsh-syntax-highlighting ──────────────────────────────────────
step_catppuccin_zsh_syntax() {
  local plugins_dir="$HOME/.zsh"
  local syntax_hl_dir="$plugins_dir/zsh-syntax-highlighting"
  local catppuccin_dir="$plugins_dir/catppuccin-zsh-syntax-highlighting"
  local catppuccin_file="$catppuccin_dir/catppuccin_${CATPPUCCIN_FLAVOR}-zsh-syntax-highlighting.zsh"

  if [ ! -d "$syntax_hl_dir" ]; then
    if [ "$DRY_RUN" = true ]; then
      would "git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git $syntax_hl_dir"
    else
      mkdir -p "$plugins_dir"
      git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$syntax_hl_dir" || return 1
      log "zsh-syntax-highlighting cloned"
    fi
  else
    log "zsh-syntax-highlighting already present"
  fi

  if [ ! -f "$catppuccin_file" ]; then
    if [ "$DRY_RUN" = true ]; then
      would "Download catppuccin_${CATPPUCCIN_FLAVOR}-zsh-syntax-highlighting.zsh -> $catppuccin_dir/"
    else
      mkdir -p "$catppuccin_dir"
      curl -fsSL \
        "${CATPPUCCIN_RAW}/zsh-syntax-highlighting/main/themes/catppuccin_${CATPPUCCIN_FLAVOR}-zsh-syntax-highlighting.zsh" \
        -o "$catppuccin_file" || return 1
      log "Catppuccin zsh-syntax-highlighting theme downloaded"
    fi
  else
    log "Catppuccin zsh-syntax-highlighting theme already present"
  fi
}
step "Catppuccin: zsh-syntax-highlighting"
run_step "Catppuccin: zsh-syntax-highlighting" step_catppuccin_zsh_syntax

# ══════════════════════════════════════════════════════════════════════════════
# Dotfile symlinks (~/.zshrc, ~/.config/nvim/init.lua)
# ══════════════════════════════════════════════════════════════════════════════
# Resolve the repo directory portably — BSD readlink (macOS) has no `-f`.
SCRIPT_SRC="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_SRC" ]; do
  SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_SRC")" && pwd)"
  SCRIPT_SRC="$(readlink "$SCRIPT_SRC")"
  [ "${SCRIPT_SRC#/}" = "$SCRIPT_SRC" ] && SCRIPT_SRC="$SCRIPT_DIR/$SCRIPT_SRC"
done
REPO_DIR="$(cd -P "$(dirname "$SCRIPT_SRC")" && pwd)"

step_zshrc_symlink() { link_dotfile "$REPO_DIR/zshrc" "$HOME/.zshrc"; }
step "Shell config (~/.zshrc)"
run_step "Shell config (~/.zshrc)" step_zshrc_symlink

step_nvim_symlink() { link_dotfile "$REPO_DIR/init.lua" "$HOME/.config/nvim/init.lua"; }
step "Neovim config"
run_step "Neovim config" step_nvim_symlink

# ── Git config ────────────────────────────────────────────────────────────────
# The repo owns behavioral config; per-machine identity lives in ~/.gitconfig.local
# (git-ignored), which the committed gitconfig sources via [include]. Seed it from
# the existing global identity before the symlink swap replaces ~/.gitconfig.
step_git_config() {
  local gitconfig_local="$HOME/.gitconfig.local"
  if [ ! -f "$gitconfig_local" ]; then
    local existing_name existing_email
    existing_name="$(git config --global user.name 2>/dev/null || true)"
    existing_email="$(git config --global user.email 2>/dev/null || true)"
    if [ "$DRY_RUN" = true ]; then
      would "Seed $gitconfig_local with [user] name=\"${existing_name:-?}\" email=\"${existing_email:-?}\""
    else
      {
        echo "# Per-machine git identity + overrides. Not tracked by the init repo."
        echo "[user]"
        [ -n "$existing_name" ]  && echo "	name = $existing_name"
        [ -n "$existing_email" ] && echo "	email = $existing_email"
      } > "$gitconfig_local" || return 1
      if [ -z "$existing_name" ] || [ -z "$existing_email" ]; then
        warn "Fill in name/email in $gitconfig_local"
      else
        log "Seeded $gitconfig_local from existing git identity"
      fi
    fi
  else
    log "$gitconfig_local already exists — leaving identity untouched"
  fi
  link_dotfile "$REPO_DIR/gitconfig" "$HOME/.gitconfig" || return 1
  link_dotfile "$REPO_DIR/gitignore" "$HOME/.config/git/ignore" || return 1
}
step "Git config"
run_step "Git config" step_git_config

# ── SSH config ────────────────────────────────────────────────────────────────
step_ssh_config() {
  link_dotfile "$REPO_DIR/ssh_config" "$HOME/.ssh/config" || return 1
  if [ "$DRY_RUN" = true ]; then
    would "chmod 600 ~/.ssh/config"
  else
    chmod 600 "$HOME/.ssh/config" 2>/dev/null || true
  fi
}
step "SSH config"
run_step "SSH config" step_ssh_config

# ── Neovim plugins + treesitter parsers ──────────────────────────────────────
# Headless nvim run: lazy.nvim installs plugins, nvim-treesitter `build` hook
# compiles parsers (needs tree-sitter CLI + a C compiler — installed above).
step_nvim_plugins() {
  if ! ok nvim; then
    warn "nvim not on PATH — skipping plugin sync"
  elif [ "$DRY_RUN" = true ]; then
    would "nvim --headless '+Lazy! sync' '+qa'"
  else
    if nvim --headless '+Lazy! sync' '+qa'; then
      log "Plugins synced and parsers compiled"
    else
      warn "nvim plugin sync had errors"
      return 1
    fi
  fi
}
step "Neovim plugins + treesitter parsers"
run_step "Neovim plugins + treesitter parsers" step_nvim_plugins

# ── macOS: system defaults + account glue (SSH keychain, gh, OrbStack) ────────
step_macos_extras() {
  # shellcheck source=macos.sh
  source "$REPO_DIR/macos.sh"
}
if [ "$IS_MAC" = true ]; then
  run_step "macOS extras (macos.sh)" step_macos_extras
fi

# ── Summary ───────────────────────────────────────────────────────────────────
if [ "$DRY_RUN" = true ]; then
  echo -e "\n${MAGENTA}════════════════════════════════${NC}"
  echo -e "${MAGENTA}  Dry run complete               ${NC}"
  echo -e "${MAGENTA}  No changes were made.          ${NC}"
  echo -e "${MAGENTA}════════════════════════════════${NC}\n"
else
  echo -e "\n${BLUE}════════════════════════════════${NC}"
  echo -e "${BLUE}  Bootstrap complete             ${NC}"
  echo -e "${BLUE}════════════════════════════════${NC}\n"
fi

TOOLS=(zsh uv ruff pyright starship claude nvim zellij btm fd rg bat zoxide fzf eza)
for t in "${TOOLS[@]}"; do
  if ok "$t"; then
    echo -e "  ${GREEN}✓${NC} $t"
  else
    echo -e "  ${YELLOW}?${NC} $t (not on PATH yet — restart your shell)"
  fi
done

if [ "$DRY_RUN" = false ]; then
  echo ""
  warn "Next steps:"
  warn "  1. Start a new shell (or: exec zsh) to pick up PATH changes"
  warn "  2. Open nvim — lazy.nvim will auto-install plugins on first launch"
  warn "  3. Catppuccin mocha applied to: starship, zellij, bottom, zsh-syntax-highlighting"
  warn "     (neovim catppuccin is handled by init.lua)"
  if [ "$IS_MAC" = true ]; then
    warn "  4. Verify ~/.gitconfig.local has your name + email"
    warn "  5. gh auth login   (then re-run to register the SSH signing key)"
    warn "  6. Launch OrbStack once, then: docker run --rm hello-world"
  fi
fi

if [ "${#FAILED_STEPS[@]}" -gt 0 ]; then
  echo ""
  err "${#FAILED_STEPS[@]} step(s) failed and were skipped:"
  for s in "${FAILED_STEPS[@]}"; do
    err "  - $s"
  done
  err "Re-run init.sh to retry — steps that already succeeded report 'already installed' and are a no-op."
  exit 1
fi
