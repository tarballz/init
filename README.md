# init

Bootstrap for a fully configured dev environment. Supports Linux (via `init.sh`) and Windows (via `setup.ps1`).

---

## Linux

```bash
git clone git@github.com:tarballz/init.git ~/code/init
bash ~/code/init/init.sh
```

Requires `sudo` for package installation. After it finishes, log out and back in (or run `exec zsh`) to activate zsh as your shell.

Pass `--dry-run` to preview all changes without making them:

```bash
bash ~/code/init/init.sh --dry-run
```

### What it installs

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

### What it configures

**Dotfile symlinks** — the repo owns the source of truth, `~/` gets symlinks:

- `~/.zshrc` → `<repo>/zshrc`
- `~/.config/nvim/init.lua` → `<repo>/init.lua`

Any pre-existing non-symlink file is backed up to `<path>.backup.<timestamp>` before being replaced.

For per-machine overrides, drop a `~/.zshrc.local` — `zshrc` sources it at the end if it exists.

**Shell (`zshrc`)**

- `~/.local/bin` on PATH
- history: 50k entries, dedup, shared across sessions
- case-insensitive menu completion with Ctrl+←/→ word navigation
- starship prompt, zoxide (`z`, `zi`), fzf (Ctrl-R / Ctrl-T / Alt-C)
- zsh-autosuggestions + zsh-syntax-highlighting (Catppuccin Mocha)
- aliases: `vim=nvim`, `zj=zellij`, `cat=bat`, `find=fd`, `ls/ll/la/lt` via eza (all guarded)

**Catppuccin Mocha theme**

- Starship — palette injected into `~/.config/starship.toml`
- Zellij — `theme "catppuccin-mocha"` in `~/.config/zellij/config.kdl`
- Bottom — theme appended to `~/.config/bottom/bottom.toml`
- bat — theme file installed and `bat cache --build` run; `BAT_THEME` exported in `zshrc`
- zsh-syntax-highlighting — theme sourced in `zshrc`
- Neovim — handled by `init.lua` via lazy.nvim

---

## Windows (PowerShell 7)

```powershell
git clone git@github.com:tarballz/init.git ~/code/init
~/code/init/setup.ps1
```

No admin required. Run in PowerShell 7 (not Windows PowerShell 5).

Pass `-DryRun` to preview all changes without making them:

```powershell
~/code/init/setup.ps1 -DryRun
```

### What it installs

All tools via [Scoop](https://scoop.sh) (no admin), with winget as a fallback slot for anything Scoop doesn't cover.

| Tool | Purpose |
|------|---------|
| starship | prompt |
| zoxide | smart `cd` |
| eza | modern `ls` |
| bat | modern `cat` |
| fd | modern `find` |
| ripgrep | fast grep |
| fzf | fuzzy finder |
| uutils-coreutils | Unix commands missing from PS (`ln`, `touch`, `wc`, `head`, `tail`, `xargs`, …) |
| neovim | editor |
| zellij | terminal multiplexer |
| bottom (`btm`) | system monitor |
| JetBrainsMono-NF | Nerd Font |
| PSFzf | PowerShell fzf module (Ctrl-T / Ctrl-R) |

### What it configures

**Dotfile symlinks:**

- `$PROFILE` → `<repo>/profile.ps1`
- `$LOCALAPPDATA\nvim\init.lua` → `<repo>/init.lua`

Requires Developer Mode or an elevated shell to create symlinks on Windows.

For per-machine overrides, drop a `~/profile.local.ps1` — `profile.ps1` sources it at the end if it exists.

**Shell (`profile.ps1`)**

- PSReadLine configured for inline autosuggestions, Catppuccin Mocha syntax highlighting, history-substring-search (Up/Down arrows), and Ctrl+←/→ word navigation
- starship prompt, zoxide, PSFzf (Ctrl-T / Ctrl-R)
- Aliases: `vim=nvim`, `zj=zellij`, `cat=bat`, `find=fd`, `ls/ll/la/lt` via eza
- `rm`, `cp`, `mv` redirected to uutils (PS built-ins removed); `sort`/`tee` left as PS cmdlets for pipeline compatibility
- `grep` aliased to `rg`
- All aliases guarded — silently skipped if the tool isn't installed

**Catppuccin Mocha theme**

- Windows Terminal — installed via the [Fragment API](https://learn.microsoft.com/en-us/windows/terminal/fragments) (non-destructive, no `settings.json` editing). After running, set *Catppuccin Mocha* as your color scheme in Windows Terminal settings.
- PSReadLine — colors set directly in `profile.ps1`
- bat — `BAT_THEME=Catppuccin Mocha` exported in `profile.ps1`
- Neovim — handled by `init.lua` via lazy.nvim

---

## Idempotent

Both scripts are safe to re-run. Each step checks whether the tool or config is already present before doing anything.
