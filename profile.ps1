# ─── PATH ──────────────────────────────────────────────────────────────────────
$env:PATH = "$env:USERPROFILE\scoop\shims;" + $env:PATH
$env:PATH = "$env:USERPROFILE\.local\bin;" + $env:PATH

# ─── Environment ───────────────────────────────────────────────────────────────
$env:EDITOR    = 'nvim'
$env:VISUAL    = 'nvim'
$env:PAGER     = 'less'
$env:LESS      = '-R --mouse --wheel-lines=3'
$env:BAT_THEME = 'Catppuccin Mocha'

# fzf
$env:FZF_DEFAULT_COMMAND = 'fd --type f --hidden --follow --exclude .git'
$env:FZF_CTRL_T_COMMAND  = $env:FZF_DEFAULT_COMMAND
$env:FZF_ALT_C_COMMAND   = 'fd --type d --hidden --follow --exclude .git'
$env:FZF_DEFAULT_OPTS    = '--height 40% --layout=reverse --border'

# ─── PSReadLine ────────────────────────────────────────────────────────────────
# Covers: autosuggestions, syntax highlighting (Catppuccin Mocha),
# history-substring-search, and Ctrl+←/→ word navigation.
if (Get-Module -ListAvailable -Name PSReadLine) {
    Set-PSReadLineOption -EditMode Emacs
    Set-PSReadLineOption -PredictionSource HistoryAndPlugin
    Set-PSReadLineOption -PredictionViewStyle InlineView
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd

    # History substring search (mirrors zsh-history-substring-search)
    Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward

    # Ctrl+←/→ word navigation
    Set-PSReadLineKeyHandler -Key Ctrl+LeftArrow  -Function BackwardWord
    Set-PSReadLineKeyHandler -Key Ctrl+RightArrow -Function ForwardWord

    # Catppuccin Mocha palette (mirrors catppuccin-zsh-syntax-highlighting)
    Set-PSReadLineOption -Colors @{
        Command          = '#89b4fa'  # Blue
        Parameter        = '#cdd6f4'  # Text
        String           = '#a6e3a1'  # Green
        Variable         = '#cba6f7'  # Mauve
        Comment          = '#6c7086'  # Overlay0
        Keyword          = '#cba6f7'  # Mauve
        Error            = '#f38ba8'  # Red
        Number           = '#fab387'  # Peach
        Type             = '#89dceb'  # Sky
        Operator         = '#89dceb'  # Sky
        Member           = '#89b4fa'  # Blue
        InlinePrediction = '#6c7086'  # Overlay0 (ghost text / autosuggestions)
        Selection        = '#313244'  # Surface0
    }
}

# ─── Tool integrations ─────────────────────────────────────────────────────────
if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (&starship init powershell)
}

if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}

# PSFzf: Ctrl+T file picker, Ctrl+R history search (mirrors fzf --zsh)
if (Get-Module -ListAvailable -Name PSFzf) {
    Import-Module PSFzf
    Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
}

# ─── Aliases & functions ───────────────────────────────────────────────────────
# PS lookup order: Alias > Function > Cmdlet > External command.
# For tools that shadow PS built-in aliases, Remove-Alias first, then define a
# function (not Set-Alias — functions can embed arguments, aliases cannot).
# External executables are called with .exe suffix to bypass function recursion.

if (Get-Command nvim -ErrorAction SilentlyContinue) {
    Remove-Alias -Name vim -Force -ErrorAction SilentlyContinue
    Set-Alias vim nvim
}

if (Get-Command zellij -ErrorAction SilentlyContinue) {
    Set-Alias zj zellij
}

if (Get-Command claude -ErrorAction SilentlyContinue) {
    function claude { claude.exe --allow-dangerously-skip-permissions @args }
}

# eza (modern ls) — removes built-in ls alias
if (Get-Command eza -ErrorAction SilentlyContinue) {
    Remove-Alias -Name ls -Force -ErrorAction SilentlyContinue
    function ls { eza --icons=always --group-directories-first @args }
    function ll { eza -l  --icons=always --git --group-directories-first @args }
    function la { eza -la --icons=always --git --group-directories-first @args }
    function lt { eza --tree --level=2 --icons=always @args }
}

# bat (modern cat) — removes built-in cat alias
if (Get-Command bat -ErrorAction SilentlyContinue) {
    Remove-Alias -Name cat -Force -ErrorAction SilentlyContinue
    function cat { bat.exe --paging=never @args }
}

# fd (modern find) — no PS alias conflict
if (Get-Command fd -ErrorAction SilentlyContinue) {
    function find { fd.exe @args }
}

# ripgrep as grep — no PS alias conflict
if (Get-Command rg -ErrorAction SilentlyContinue) {
    function grep { rg.exe @args }
}

# uutils-coreutils: override rm/cp/mv where PS built-ins are broken or aliased.
# sort and tee are intentionally left as PS cmdlets (Sort-Object and Tee-Object
# are valuable in PS object pipelines).
# ln, touch, wc, head, tail, xargs, etc. have no PS alias conflicts and are
# available in PATH automatically once uutils is installed.
if (Get-Command touch -ErrorAction SilentlyContinue) {
    Remove-Alias -Name rm  -Force -ErrorAction SilentlyContinue
    Remove-Alias -Name del -Force -ErrorAction SilentlyContinue
    Remove-Alias -Name cp  -Force -ErrorAction SilentlyContinue
    Remove-Alias -Name mv  -Force -ErrorAction SilentlyContinue
}

# ─── Local overrides ───────────────────────────────────────────────────────────
$_localProfile = Join-Path $HOME 'profile.local.ps1'
if (Test-Path $_localProfile) { . $_localProfile }
