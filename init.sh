#!/usr/bin/env bash
# Fresh system bootstrap script
# Installs: zsh, uv, ruff, pyright, starship, zellij, claude, neovim, bottom,
#           bat, zoxide, fzf, eza, fd, ripgrep, zsh-autosuggestions,
#           zsh-syntax-highlighting, FiraCode Nerd Font, tree-sitter CLI
# Symlinks: ~/.zshrc -> <repo>/zshrc, ~/.config/nvim/init.lua -> <repo>/init.lua
# Catppuccin mocha theme for: starship, zellij, bottom, bat, zsh-syntax-highlighting
#   (neovim catppuccin is handled by init.lua via lazy.nvim)
# Usage: ./init.sh [--dry-run]
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

if [ "$DRY_RUN" = true ]; then
  echo -e "\n${MAGENTA}[DRY RUN] No changes will be made.${NC}\n"
fi

# ── Architecture ──────────────────────────────────────────────────────────────
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  ARCH_MUSL="x86_64-unknown-linux-musl" ; NVIM_ARCH="x86_64" ;;
  aarch64) ARCH_MUSL="aarch64-unknown-linux-musl" ; NVIM_ARCH="arm64"  ;;
  *) err "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# ── Package manager ───────────────────────────────────────────────────────────
if ok apt-get; then
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
  local tmp; tmp=$(mktemp -d)
  curl -fsSL "$url" | tar -xz -C "$tmp"
  sudo install -m 755 "$(find "$tmp" -name "$bin" -type f | head -1)" "$dest/$bin"
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
  mkdir -p "$(dirname "$dest")"
  if [ -L "$dest" ]; then
    ln -sfn "$src" "$dest"
    log "Symlink refreshed: $dest -> $src"
  elif [ -e "$dest" ]; then
    local backup="${dest}.backup.$(date +%Y%m%d-%H%M%S)"
    mv "$dest" "$backup"
    ln -s "$src" "$dest"
    warn "Existing $dest backed up to $backup"
    log "Linked $src -> $dest"
  else
    ln -s "$src" "$dest"
    log "Linked $src -> $dest"
  fi
}

# ── Update package lists ──────────────────────────────────────────────────────
step "Updating package lists"
if [ "$DRY_RUN" = true ]; then
  would "$PKG_UPDATE"
else
  $PKG_UPDATE
fi

# ── Base build tools & git ────────────────────────────────────────────────────
step "Base build dependencies"
if [ "$DRY_RUN" = true ]; then
  if ok apt-get || ok dnf; then
    would "$PKG_INSTALL git curl wget unzip gcc make"
  elif ok pacman; then
    would "$PKG_INSTALL git curl wget unzip base-devel"
  fi
else
  if ok apt-get; then
    $PKG_INSTALL git curl wget unzip gcc make
  elif ok dnf; then
    $PKG_INSTALL git curl wget unzip gcc make
  elif ok pacman; then
    $PKG_INSTALL git curl wget unzip base-devel
  fi
  log "Base dependencies ready"
fi

# ── zsh ───────────────────────────────────────────────────────────────────────
step "zsh"
if ! ok zsh; then
  if [ "$DRY_RUN" = true ]; then
    would "$PKG_INSTALL zsh"
  else
    $PKG_INSTALL zsh
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
    chsh -s "$(command -v zsh)"
    warn "Log out and back in for the shell change to take effect"
  fi
else
  log "zsh is already the default shell"
fi

# ── uv ────────────────────────────────────────────────────────────────────────
step "uv"
if ! ok uv; then
  if [ "$DRY_RUN" = true ]; then
    would "curl -LsSf https://astral.sh/uv/install.sh | sh"
  else
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
    log "uv installed"
  fi
else
  log "uv already installed: $(uv --version)"
fi

export PATH="$HOME/.local/bin:$PATH"

# ── ruff (via uv tool) ────────────────────────────────────────────────────────
step "ruff"
if ! ok ruff; then
  if [ "$DRY_RUN" = true ]; then
    would "uv tool install ruff"
  else
    uv tool install ruff
    log "ruff installed"
  fi
else
  log "ruff already installed: $(ruff --version)"
fi

# ── pyright (via uv tool) ─────────────────────────────────────────────────────
step "pyright"
if ! ok pyright; then
  if [ "$DRY_RUN" = true ]; then
    would "uv tool install pyright"
  else
    uv tool install pyright
    log "pyright installed"
  fi
else
  log "pyright already installed: $(pyright --version)"
fi

# ── starship ──────────────────────────────────────────────────────────────────
step "starship"
if ! ok starship; then
  if [ "$DRY_RUN" = true ]; then
    would "curl -fsSL https://starship.rs/install.sh | sh -s -- --yes"
  else
    curl -fsSL https://starship.rs/install.sh | sh -s -- --yes
    log "starship installed"
  fi
else
  log "starship already installed: $(starship --version | head -1)"
fi

# ── Claude Code ───────────────────────────────────────────────────────────────
step "Claude Code"
if ! ok claude; then
  if [ "$DRY_RUN" = true ]; then
    would "curl -fsSL https://claude.ai/install.sh | bash"
  else
    curl -fsSL https://claude.ai/install.sh | bash
    log "Claude Code installed"
  fi
else
  log "Claude Code already installed: $(claude --version 2>/dev/null || echo 'unknown version')"
fi

# ── Neovim ────────────────────────────────────────────────────────────────────
step "Neovim"
if ! ok nvim; then
  if [ "$DRY_RUN" = true ]; then
    would "Download and install nvim-linux-${NVIM_ARCH}.tar.gz -> /usr/local/"
  else
    tmp=$(mktemp -d)
    curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${NVIM_ARCH}.tar.gz" \
      | tar -xz -C "$tmp"
    sudo cp -r "$tmp/nvim-linux-${NVIM_ARCH}/"* /usr/local/
    rm -rf "$tmp"
    log "Neovim installed: $(nvim --version | head -1)"
  fi
else
  log "Neovim already installed: $(nvim --version | head -1)"
fi

# ── Zellij ────────────────────────────────────────────────────────────────────
step "Zellij"
if ! ok zellij; then
  if [ "$DRY_RUN" = true ]; then
    would "install_binary_from_tar zellij-org/zellij -> zellij-${ARCH_MUSL}.tar.gz"
  else
    TAG=$(latest_gh_tag "zellij-org/zellij")
    install_binary_from_tar \
      "https://github.com/zellij-org/zellij/releases/download/${TAG}/zellij-${ARCH_MUSL}.tar.gz" \
      "zellij"
    log "Zellij installed: $(zellij --version)"
  fi
else
  log "Zellij already installed: $(zellij --version)"
fi

# ── Bottom (btm) ──────────────────────────────────────────────────────────────
step "Bottom (btm)"
if ! ok btm; then
  if [ "$DRY_RUN" = true ]; then
    would "install_binary_from_tar ClementTsang/bottom -> bottom_${ARCH_MUSL}.tar.gz"
  else
    TAG=$(latest_gh_tag "ClementTsang/bottom")
    install_binary_from_tar \
      "https://github.com/ClementTsang/bottom/releases/download/${TAG}/bottom_${ARCH_MUSL}.tar.gz" \
      "btm"
    log "Bottom installed: $(btm --version)"
  fi
else
  log "Bottom already installed: $(btm --version)"
fi

# ── fd (Telescope file finder) ────────────────────────────────────────────────
step "fd"
if ! ok fd; then
  if [ "$DRY_RUN" = true ]; then
    would "$PKG_INSTALL fd-find (+ symlink fdfind -> fd on Debian/Ubuntu)"
  else
    if ok apt-get; then
      $PKG_INSTALL fd-find
      if ok fdfind && ! ok fd; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
        log "Created symlink: fd -> fdfind"
      fi
    elif ok dnf; then
      $PKG_INSTALL fd-find
    elif ok pacman; then
      $PKG_INSTALL fd
    fi
    log "fd installed"
  fi
else
  log "fd already installed: $(fd --version)"
fi

# ── eza (modern ls replacement) ──────────────────────────────────────────────
step "eza"
if ! ok eza; then
  if [ "$DRY_RUN" = true ]; then
    would "install_binary_from_tar eza-community/eza -> eza_${ARCH_MUSL}.tar.gz"
  else
    TAG=$(latest_gh_tag "eza-community/eza")
    install_binary_from_tar \
      "https://github.com/eza-community/eza/releases/download/${TAG}/eza_${ARCH_MUSL}.tar.gz" \
      "eza"
    log "eza installed: $(eza --version | head -1)"
  fi
else
  log "eza already installed: $(eza --version | head -1)"
fi

# ── FiraCode Nerd Font Mono ───────────────────────────────────────────────────
step "FiraCode Nerd Font Mono"
FONT_DIR="$HOME/.local/share/fonts"
if ! fc-list | grep -qi "FiraCode Nerd"; then
  if [ "$DRY_RUN" = true ]; then
    would "Download FiraCode.zip from nerd-fonts and install *Mono*.ttf -> $FONT_DIR/"
  else
    mkdir -p "$FONT_DIR"
    tmp=$(mktemp -d)
    curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip" \
      -o "$tmp/FiraCode.zip"
    unzip -q "$tmp/FiraCode.zip" -d "$tmp/FiraCode"
    cp "$tmp/FiraCode/"*Mono*.ttf "$FONT_DIR/"
    fc-cache -f "$FONT_DIR"
    rm -rf "$tmp"
    log "FiraCode Nerd Font Mono installed"
  fi
else
  log "FiraCode Nerd Font Mono already installed"
fi

# ── tree-sitter CLI (nvim-treesitter parser compilation) ─────────────────────
step "tree-sitter"
if ! ok tree-sitter; then
  if [ "$DRY_RUN" = true ]; then
    would "Download tree-sitter-linux-x64.gz -> /usr/local/bin/tree-sitter"
  else
    TAG=$(latest_gh_tag "tree-sitter/tree-sitter")
    curl -fsSL "https://github.com/tree-sitter/tree-sitter/releases/download/${TAG}/tree-sitter-linux-x64.gz" \
      | gunzip -c > /tmp/tree-sitter
    sudo install -m 755 /tmp/tree-sitter /usr/local/bin/tree-sitter
    rm /tmp/tree-sitter
    log "tree-sitter installed: $(tree-sitter --version)"
  fi
else
  log "tree-sitter already installed: $(tree-sitter --version)"
fi

# ── ripgrep (Telescope live_grep) ─────────────────────────────────────────────
step "ripgrep"
if ! ok rg; then
  if [ "$DRY_RUN" = true ]; then
    would "$PKG_INSTALL ripgrep"
  else
    $PKG_INSTALL ripgrep
    log "ripgrep installed: $(rg --version | head -1)"
  fi
else
  log "ripgrep already installed: $(rg --version | head -1)"
fi

# ── bat (modern cat with syntax highlighting) ────────────────────────────────
step "bat"
if ! ok bat; then
  if [ "$DRY_RUN" = true ]; then
    would "$PKG_INSTALL bat (+ symlink batcat -> bat on Debian/Ubuntu)"
  else
    if ok apt-get; then
      $PKG_INSTALL bat
      if ok batcat && ! ok bat; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
        log "Created symlink: bat -> batcat"
      fi
    elif ok dnf; then
      $PKG_INSTALL bat
    elif ok pacman; then
      $PKG_INSTALL bat
    fi
    log "bat installed"
  fi
else
  log "bat already installed: $(bat --version)"
fi

# ── zoxide (smarter cd) ──────────────────────────────────────────────────────
step "zoxide"
if ! ok zoxide; then
  if [ "$DRY_RUN" = true ]; then
    would "curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh"
  else
    curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
    log "zoxide installed"
  fi
else
  log "zoxide already installed: $(zoxide --version)"
fi

# ── fzf (fuzzy finder) ───────────────────────────────────────────────────────
step "fzf"
if [ ! -d "$HOME/.fzf" ]; then
  if [ "$DRY_RUN" = true ]; then
    would "git clone --depth=1 https://github.com/junegunn/fzf.git ~/.fzf && ~/.fzf/install"
  else
    git clone --depth=1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
    "$HOME/.fzf/install" --key-bindings --completion --no-update-rc --no-bash --no-fish
    log "fzf installed"
  fi
else
  log "fzf already present at ~/.fzf"
fi

# ── zsh-autosuggestions ──────────────────────────────────────────────────────
step "zsh-autosuggestions"
ZSH_AUTOSUGGEST_DIR="$HOME/.zsh/zsh-autosuggestions"
if [ ! -d "$ZSH_AUTOSUGGEST_DIR" ]; then
  if [ "$DRY_RUN" = true ]; then
    would "git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git $ZSH_AUTOSUGGEST_DIR"
  else
    mkdir -p "$HOME/.zsh"
    git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git "$ZSH_AUTOSUGGEST_DIR"
    log "zsh-autosuggestions cloned"
  fi
else
  log "zsh-autosuggestions already present"
fi

# ── zsh-history-substring-search ─────────────────────────────────────────────
step "zsh-history-substring-search"
ZSH_HSS_DIR="$HOME/.zsh/zsh-history-substring-search"
if [ ! -d "$ZSH_HSS_DIR" ]; then
  if [ "$DRY_RUN" = true ]; then
    would "git clone --depth=1 https://github.com/zsh-users/zsh-history-substring-search.git $ZSH_HSS_DIR"
  else
    git clone --depth=1 https://github.com/zsh-users/zsh-history-substring-search.git "$ZSH_HSS_DIR"
    log "zsh-history-substring-search cloned"
  fi
else
  log "zsh-history-substring-search already present"
fi

# ══════════════════════════════════════════════════════════════════════════════
# Catppuccin themes (flavor: mocha — matches neovim config)
# ══════════════════════════════════════════════════════════════════════════════
CATPPUCCIN_RAW="https://raw.githubusercontent.com/catppuccin"

# ── Catppuccin: Starship (palette only, no format changes) ───────────────────
step "Catppuccin: Starship"
STARSHIP_CONFIG="$HOME/.config/starship.toml"

if ! grep -q "\[palettes\.catppuccin_${CATPPUCCIN_FLAVOR}\]" "$STARSHIP_CONFIG" 2>/dev/null; then
  if [ "$DRY_RUN" = true ]; then
    would "Add catppuccin_${CATPPUCCIN_FLAVOR} palette to $STARSHIP_CONFIG"
  else
    mkdir -p "$HOME/.config"
    touch "$STARSHIP_CONFIG"
    if ! grep -q "^palette\s*=" "$STARSHIP_CONFIG"; then
      tmp=$(mktemp)
      echo "palette = \"catppuccin_${CATPPUCCIN_FLAVOR}\"" | cat - "$STARSHIP_CONFIG" > "$tmp"
      mv "$tmp" "$STARSHIP_CONFIG"
      log "Set palette = catppuccin_${CATPPUCCIN_FLAVOR} in starship.toml"
    fi
    cat >> "$STARSHIP_CONFIG" << 'EOF'

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

# ── Catppuccin: Zellij ────────────────────────────────────────────────────────
# Catppuccin is bundled in Zellij — just activate it in the config.
step "Catppuccin: Zellij"
ZELLIJ_CONFIG_DIR="$HOME/.config/zellij"
ZELLIJ_CONFIG="$ZELLIJ_CONFIG_DIR/config.kdl"

if ! grep -q "^theme " "$ZELLIJ_CONFIG" 2>/dev/null; then
  if [ "$DRY_RUN" = true ]; then
    would "Set theme \"catppuccin-${CATPPUCCIN_FLAVOR}\" in $ZELLIJ_CONFIG"
  else
    mkdir -p "$ZELLIJ_CONFIG_DIR"
    if [ ! -f "$ZELLIJ_CONFIG" ]; then
      zellij setup --dump-config > "$ZELLIJ_CONFIG"
      log "Zellij default config written"
    fi
    if grep -q "// theme" "$ZELLIJ_CONFIG" 2>/dev/null; then
      sed -i "s|// theme.*|theme \"catppuccin-${CATPPUCCIN_FLAVOR}\"|" "$ZELLIJ_CONFIG"
    else
      echo "" >> "$ZELLIJ_CONFIG"
      echo "theme \"catppuccin-${CATPPUCCIN_FLAVOR}\"" >> "$ZELLIJ_CONFIG"
    fi
    log "Catppuccin ${CATPPUCCIN_FLAVOR} theme set in Zellij config"
  fi
else
  log "Zellij theme already configured"
fi

# ── Catppuccin: Bottom ────────────────────────────────────────────────────────
step "Catppuccin: Bottom"
BOTTOM_CONFIG="$HOME/.config/bottom/bottom.toml"

if ! grep -q "catppuccin" "$BOTTOM_CONFIG" 2>/dev/null; then
  if [ "$DRY_RUN" = true ]; then
    would "Append Catppuccin ${CATPPUCCIN_FLAVOR} theme to $BOTTOM_CONFIG"
  else
    mkdir -p "$HOME/.config/bottom"
    curl -fsSL "${CATPPUCCIN_RAW}/bottom/main/themes/${CATPPUCCIN_FLAVOR}.toml" \
      >> "$BOTTOM_CONFIG"
    log "Catppuccin ${CATPPUCCIN_FLAVOR} theme appended to $BOTTOM_CONFIG"
  fi
else
  log "Catppuccin bottom theme already present"
fi

# ── Catppuccin: bat ──────────────────────────────────────────────────────────
step "Catppuccin: bat"
if ok bat; then
  BAT_THEMES_DIR="$(bat --config-dir)/themes"
  if [ ! -f "$BAT_THEMES_DIR/Catppuccin Mocha.tmTheme" ]; then
    if [ "$DRY_RUN" = true ]; then
      would "Download Catppuccin Mocha.tmTheme -> $BAT_THEMES_DIR/ && bat cache --build"
    else
      mkdir -p "$BAT_THEMES_DIR"
      curl -fsSL \
        "${CATPPUCCIN_RAW}/bat/main/themes/Catppuccin%20Mocha.tmTheme" \
        -o "$BAT_THEMES_DIR/Catppuccin Mocha.tmTheme"
      bat cache --build >/dev/null
      log "Catppuccin Mocha bat theme installed"
    fi
  else
    log "Catppuccin bat theme already present"
  fi
else
  warn "bat not on PATH yet — skipping bat theme (re-run after restarting shell)"
fi

# ── Catppuccin: zsh-syntax-highlighting ──────────────────────────────────────
step "Catppuccin: zsh-syntax-highlighting"
ZSH_PLUGINS_DIR="$HOME/.zsh"
ZSH_SYNTAX_HL_DIR="$ZSH_PLUGINS_DIR/zsh-syntax-highlighting"
CATPPUCCIN_ZSH_DIR="$ZSH_PLUGINS_DIR/catppuccin-zsh-syntax-highlighting"
CATPPUCCIN_ZSH_FILE="$CATPPUCCIN_ZSH_DIR/catppuccin_${CATPPUCCIN_FLAVOR}-zsh-syntax-highlighting.zsh"

if [ ! -d "$ZSH_SYNTAX_HL_DIR" ]; then
  if [ "$DRY_RUN" = true ]; then
    would "git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git $ZSH_SYNTAX_HL_DIR"
  else
    mkdir -p "$ZSH_PLUGINS_DIR"
    git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_SYNTAX_HL_DIR"
    log "zsh-syntax-highlighting cloned"
  fi
else
  log "zsh-syntax-highlighting already present"
fi

if [ ! -f "$CATPPUCCIN_ZSH_FILE" ]; then
  if [ "$DRY_RUN" = true ]; then
    would "Download catppuccin_${CATPPUCCIN_FLAVOR}-zsh-syntax-highlighting.zsh -> $CATPPUCCIN_ZSH_DIR/"
  else
    mkdir -p "$CATPPUCCIN_ZSH_DIR"
    curl -fsSL \
      "${CATPPUCCIN_RAW}/zsh-syntax-highlighting/main/themes/catppuccin_${CATPPUCCIN_FLAVOR}-zsh-syntax-highlighting.zsh" \
      -o "$CATPPUCCIN_ZSH_FILE"
    log "Catppuccin zsh-syntax-highlighting theme downloaded"
  fi
else
  log "Catppuccin zsh-syntax-highlighting theme already present"
fi

# ══════════════════════════════════════════════════════════════════════════════
# Dotfile symlinks (~/.zshrc, ~/.config/nvim/init.lua)
# ══════════════════════════════════════════════════════════════════════════════
REPO_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

step "Shell config (~/.zshrc)"
link_dotfile "$REPO_DIR/zshrc" "$HOME/.zshrc"

step "Neovim config"
link_dotfile "$REPO_DIR/init.lua" "$HOME/.config/nvim/init.lua"

# ── Neovim plugins + treesitter parsers ──────────────────────────────────────
# Headless nvim run: lazy.nvim installs plugins, nvim-treesitter `build` hook
# compiles parsers (needs tree-sitter CLI + a C compiler — installed above).
step "Neovim plugins + treesitter parsers"
if ! ok nvim; then
  warn "nvim not on PATH — skipping plugin sync"
elif [ "$DRY_RUN" = true ]; then
  would "nvim --headless '+Lazy! sync' '+qa'"
else
  nvim --headless '+Lazy! sync' '+qa' || warn "nvim plugin sync had errors"
  log "Plugins synced and parsers compiled"
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
fi
