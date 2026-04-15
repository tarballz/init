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
bindkey -e                                    # emacs keymap

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

# misc color
alias grep="grep --color=auto"
alias diff="diff --color=auto"
alias ip="ip --color=auto"

# ─── Local overrides ───────────────────────────────────────────────────────────
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
