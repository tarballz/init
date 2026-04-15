# init

Fresh system bootstrap for Linux. Run once on a new machine to get a fully configured dev environment.

## Usage

```bash
git clone git@github.com:tarballz/init.git ~/code/init
bash ~/code/init/init.sh
```

Requires `sudo` for package installation. After it finishes, log out and back in (or run `exec zsh`) to activate zsh as your shell.

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
| bat | system package manager (symlinked to `bat` if distro ships `batcat`) |
| zoxide | official installer |
| fzf | git clone + `install` script (key-bindings + completion) |
| eza | latest release binary |
| fd | system package manager |
| ripgrep | system package manager |
| zsh-syntax-highlighting | git clone to `~/.zsh/` |
| zsh-autosuggestions | git clone to `~/.zsh/` |
| FiraCode Nerd Font Mono | nerd-fonts release zip |
| tree-sitter CLI | latest release binary |
| gcc, make, git, curl, unzip | system package manager |

Supports apt (Debian/Ubuntu), dnf (Fedora), and pacman (Arch). Supports x86\_64 and arm64.

## What it configures

**Dotfile symlinks** — the repo owns the source of truth, `~/` gets symlinks:

- `~/.zshrc` → `<repo>/zshrc`
- `~/.config/nvim/init.lua` → `<repo>/init.lua`

Any pre-existing non-symlink file is backed up to `<path>.backup.<timestamp>` before being replaced.

For per-machine overrides, drop a `~/.zshrc.local` — `zshrc` sources it at the end if it exists.

**Shell (`zshrc`)**

- `~/.local/bin` on PATH
- history: 50k entries, dedup, shared across sessions
- case-insensitive menu completion
- starship prompt, zoxide (`z`, `zi`), fzf (Ctrl-R / Ctrl-T / Alt-C)
- zsh-autosuggestions + zsh-syntax-highlighting (Catppuccin Mocha)
- aliases: `vim=nvim`, `zj=zellij`, `cat=bat`, `ls/ll/la/lt` via eza

**Catppuccin mocha theme**

- Starship — palette injected into `~/.config/starship.toml`
- Zellij — `theme "catppuccin-mocha"` in `~/.config/zellij/config.kdl`
- Bottom — theme appended to `~/.config/bottom/bottom.toml`
- bat — theme file installed and `bat cache --build` run; `BAT_THEME` exported in `zshrc`
- zsh-syntax-highlighting — theme sourced in `zshrc`
- Neovim — handled by `init.lua` via lazy.nvim

## Idempotent

Safe to re-run. Each step checks whether the tool is already installed before doing anything. Re-running refreshes existing symlinks in place (no new backups).
