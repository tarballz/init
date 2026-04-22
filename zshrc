# ─── PATH ──────────────────────────────────────────────────────────────────────
export PATH="$HOME/.local/bin:$PATH"

# ─── Environment ───────────────────────────────────────────────────────────────
export EDITOR=nvim
export VISUAL=nvim
export PAGER=less
export LESS='-R --mouse --wheel-lines=3'
export CLICOLOR=1
export BAT_THEME="Catppuccin Mocha"

# ─── History ───────────────────────────────────────────────────────────────────
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt SHARE_HISTORY INC_APPEND_HISTORY APPEND_HISTORY
setopt HIST_IGNORE_DUPS HIST_IGNORE_ALL_DUPS HIST_FIND_NO_DUPS
setopt HIST_IGNORE_SPACE HIST_REDUCE_BLANKS HIST_VERIFY

# ─── Completion ────────────────────────────────────────────────────────────────
autoload -Uz compinit && compinit
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu select
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '%F{yellow}-- %d --%f'

# ─── Key bindings ──────────────────────────────────────────────────────────────
bindkey -v                                    # vi keymap (Esc → normal mode)
export KEYTIMEOUT=1                           # 10ms Esc delay — snappy mode switch

# Word-wise navigation with Ctrl+Arrow (xterm/modern terminals)
bindkey '^[[1;5C' forward-word                # Ctrl+Right
bindkey '^[[1;5D' backward-word               # Ctrl+Left
bindkey '^[[1;3C' forward-word                # Alt+Right
bindkey '^[[1;3D' backward-word               # Alt+Left

# Word-wise delete
bindkey '^H'      backward-kill-word          # Ctrl+Backspace (some terms)
bindkey '^[[3;5~' kill-word                   # Ctrl+Delete

# ─── Tool integrations ─────────────────────────────────────────────────────────
command -v starship >/dev/null && eval "$(starship init zsh)"
command -v zoxide   >/dev/null && eval "$(zoxide init zsh)"

# fzf (installer writes ~/.fzf.zsh with key-bindings + completion)
[ -f "$HOME/.fzf.zsh" ] && source "$HOME/.fzf.zsh"

# ─── Plugins ───────────────────────────────────────────────────────────────────
# autosuggestions must come before syntax-highlighting;
# syntax-highlighting theme must come before the plugin itself.
[ -f "$HOME/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh" ] \
  && source "$HOME/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh"

[ -f "$HOME/.zsh/catppuccin-zsh-syntax-highlighting/catppuccin_mocha-zsh-syntax-highlighting.zsh" ] \
  && source "$HOME/.zsh/catppuccin-zsh-syntax-highlighting/catppuccin_mocha-zsh-syntax-highlighting.zsh"
[ -f "$HOME/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ] \
  && source "$HOME/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"

# history-substring-search must be sourced AFTER syntax-highlighting
[ -f "$HOME/.zsh/zsh-history-substring-search/zsh-history-substring-search.zsh" ] \
  && source "$HOME/.zsh/zsh-history-substring-search/zsh-history-substring-search.zsh" \
  && bindkey '^[[A' history-substring-search-up \
  && bindkey '^[[B' history-substring-search-down

# ─── Aliases ───────────────────────────────────────────────────────────────────
alias vim="nvim"
alias zj="zellij"

# eza (modern ls)
alias ls="eza --icons=always --group-directories-first"
alias ll="eza -l --icons=always --git --group-directories-first"
alias la="eza -la --icons=always --git --group-directories-first"
alias lt="eza --tree --level=2 --icons=always"

# bat (modern cat)
alias cat="bat --paging=never"

# claude
alias claude="claude --allow-dangerously-skip-permissions"

# marimapper (editable — runs from source)
alias marimapper='uv run --project ~/code/marimapper marimapper'
alias marimapper_check_camera='uv run --project ~/code/marimapper marimapper_check_camera'
alias marimapper_check_backend='uv run --project ~/code/marimapper marimapper_check_backend'
alias marimapper_upload_mapping_to_pixelblaze='uv run --project ~/code/marimapper marimapper_upload_mapping_to_pixelblaze'
alias marimapper_export_2d_map='uv run --project ~/code/marimapper marimapper_export_2d_map'

# misc color
alias grep="grep --color=auto"
alias diff="diff --color=auto"
alias ip="ip --color=auto"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

[ -f "$HOME/.cargo/env" ] && \. "$HOME/.cargo/env"

# ─── Local overrides ───────────────────────────────────────────────────────────
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
