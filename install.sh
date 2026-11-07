#!/usr/bin/env bash
set -euo pipefail

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
HERE="$(dirname "$SELF")"
LYR_PY="$HERE/lyr.py"

if [[ ! -f "$LYR_PY" ]]; then
    echo "lyr-launcher: cannot find lyr.py next to $SELF" >&2
    exit 1
fi

VENV_DIR="${LYR_VENV:-${XDG_DATA_HOME:-$HOME/.local/share}/lyr/venv}"
PY="${LYR_PYTHON:-python3}"

install_shell_snippet() {
    local rc="$1"
    local snippet="$2"
    local begin="# >>> lyr launcher >>>"
    local end="# <<< lyr launcher <<<"

    [[ -n "$rc" ]] || return 0
    mkdir -p "$(dirname "$rc")"
    [[ -f "$rc" ]] || : > "$rc"

    if grep -qF "$begin" "$rc" 2>/dev/null; then
        local tmp
        tmp="$(mktemp)"
        awk -v b="$begin" -v e="$end" -v snip="$snippet" '
            $0 == b { blk=1; print b; print snip; next }
            $0 == e { blk=0; print e; next }
            !blk    { print }
        ' "$rc" > "$tmp"
        mv "$tmp" "$rc"
    else
        {
            printf '\n%s\n' "$begin"
            printf '%s\n' "$snippet"
            printf '%s\n' "$end"
        } >> "$rc"
    fi
}

install_aliases() {
    local sh_func="lyr() { \"$SELF\" \"\$@\"; }"
    local csh_alias="alias lyr '\"$SELF\"'"
    local fish_func="function lyr; \"$SELF\" \$argv; end"
    local nu_func="def lyr [...args] { ^\"$SELF\" ...\$args }"
    local xonsh_alias="aliases['lyr'] = ['$SELF']"
    local elvish_func="fn lyr {|@args| e:\"$SELF\" \$@args }"
    local pwsh_func="function lyr { & \"$SELF\" @args }"

    # 1. POSIX / Bourne / Korn / Almquist shells (bash, zsh, ksh, dash, sh, osh)
    install_shell_snippet "$HOME/.bashrc" "$sh_func"
    install_shell_snippet "$HOME/.zshrc" "$sh_func"
    install_shell_snippet "$HOME/.kshrc" "$sh_func"
    install_shell_snippet "$HOME/.dashrc" "$sh_func"
    install_shell_snippet "$HOME/.profile" "$sh_func"
    install_shell_snippet "$HOME/.oshrc" "$sh_func"

    # 2. C shells (csh, tcsh)
    install_shell_snippet "$HOME/.cshrc" "$csh_alias"
    install_shell_snippet "$HOME/.tcshrc" "$csh_alias"

    # 3. Fish
    local fish_conf="${XDG_CONFIG_HOME:-$HOME/.config}/fish/config.fish"
    install_shell_snippet "$fish_conf" "$fish_func"

    # 4. Nushell
    local nu_conf="${XDG_CONFIG_HOME:-$HOME/.config}/nushell/config.nu"
    install_shell_snippet "$nu_conf" "$nu_func"

    # 5. Xonsh
    install_shell_snippet "$HOME/.xonshrc" "$xonsh_alias"

    # 6. Elvish
    local elv_conf="${XDG_CONFIG_HOME:-$HOME/.config}/elvish/rc.elv"
    install_shell_snippet "$elv_conf" "$elvish_func"

    # 7. PowerShell (pwsh)
    local pwsh_conf="${XDG_CONFIG_HOME:-$HOME/.config}/powershell/Microsoft.PowerShell_profile.ps1"
    install_shell_snippet "$pwsh_conf" "$pwsh_func"
}

install_aliases

if ! command -v "$PY" >/dev/null 2>&1; then
    echo "lyr-launcher: $PY not found. Install Python 3.11+." >&2
    exit 1
fi

if ! "$PY" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)'; then
    echo "lyr-launcher: lyr needs Python 3.11 or newer ($PY is $( "$PY" -V 2>&1 ))." >&2
    exit 1
fi

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    echo "lyr-launcher: creating venv in $VENV_DIR" >&2
    mkdir -p "$(dirname "$VENV_DIR")"
    "$PY" -m venv --system-site-packages "$VENV_DIR"
fi

VPY="$VENV_DIR/bin/python"
REQ="$HERE/requirements.txt"
STAMP="$VENV_DIR/.requirements.stamp"

needs_install=0
if [[ -f "$REQ" ]]; then
    if [[ ! -f "$STAMP" || "$REQ" -nt "$STAMP" ]]; then
        needs_install=1
    fi
else
    if [[ ! -f "$STAMP" ]]; then
        needs_install=1
    fi
fi

if [[ "$needs_install" -eq 1 ]]; then
    "$VPY" -m pip install --quiet --upgrade pip >/dev/null 2>&1 || true
    if [[ -f "$REQ" ]]; then
        echo "lyr-launcher: installing requirements from $REQ" >&2
        "$VPY" -m pip install --quiet -r "$REQ"
    else
        echo "lyr-launcher: installing default requirements (Pillow, mutagen)" >&2
        "$VPY" -m pip install --quiet Pillow mutagen
    fi
    touch "$STAMP"
fi

exec "$VPY" "$LYR_PY" "$@"
