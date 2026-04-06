# init

Fresh system bootstrap for Linux. Run once on a new machine to get a fully configured dev environment.

## Usage

```bash
git clone git@github.com:tarballz/init.git ~/code/init
bash ~/code/init/init.sh
```

Requires `sudo` for package installation. SSH key must be added to GitHub before running (needed to clone the configs repo).

After it finishes, log out and back in (or run `exec zsh`) to activate zsh as your shell.

## What it installs

| Tool | How |
|------|-----|
| zsh | system package manager, set as default shell |
| uv | official installer |
| ruff | `uv tool install` |
| pyright | `uv tool install` |
| starship | official installer |
| Claude Code | official installer |
| Neovim | latest release tarball |
| Zellij | latest release binary |
| bottom (`btm`) | latest release binary |
| fd | system package manager |
| ripgrep | system package manager |
| eza | latest release binary |
| FiraCode Nerd Font Mono | nerd-fonts release zip |
| tree-sitter CLI | latest release binary |
| gcc, make, git, curl, unzip | system package manager |

Supports apt (Debian/Ubuntu), dnf (Fedora), and pacman (Arch). Supports x86\_64 and arm64.

## What it configures

**~/.zshrc**
- `~/.local/bin` on PATH
- starship prompt
- `alias vim="nvim"`
- `alias ls="eza --icons=always"`
- zsh-syntax-highlighting with catppuccin mocha

**Catppuccin mocha theme**
- Starship — palette colors injected into `~/.config/starship.toml`
- Zellij — `theme "catppuccin-mocha"` set in `~/.config/zellij/config.kdl`
- Bottom — theme appended to `~/.config/bottom/bottom.toml`
- zsh-syntax-highlighting — theme file sourced in `.zshrc`
- Neovim — handled by `init.lua` via lazy.nvim

**Neovim**

Clones `git@github.com:tarballz/configs.git` to `~/code/configs` and symlinks `~/code/configs/init.lua` → `~/.config/nvim/init.lua`. On first launch, lazy.nvim auto-installs all plugins.

## Idempotent

Safe to re-run. Each step checks whether the tool is already installed before doing anything.
