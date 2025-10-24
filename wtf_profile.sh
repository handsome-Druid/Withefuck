# Set up per-session shell logging and log rotation.
# If sourced, continue only in interactive shells.
if (return 0 2>/dev/null); then
    case $- in
        *i*) ;;
        *) return;;
    esac
fi

if [ -z "$UNDER_SCRIPT" ]; then
    export UNDER_SCRIPT=1
    LOGDIR="$HOME/.shell_logs"
    mkdir -p "$LOGDIR"

    # zsh hooks are installed in the UNDER_SCRIPT branch below.

    # Build a unique log path: timestamp, random, PID, TTY
    TTY_NAME=$(tty 2>/dev/null | sed 's#/dev/##; s#/#_#g')
    if [ -z "$TTY_NAME" ]; then
        TTY_NAME="unknown"
    fi
    # Use $RANDOM when available; otherwise rely on PID and timestamp.
    TS="$LOGDIR/typescript-$(date +%Y%m%dT%H%M%S)-${RANDOM:-}-$$-$TTY_NAME.log"

    # Export for consumers (e.g. Python utilities)
    export WTF_TYPESCRIPT="$TS"

    # Ensure the file exists
    touch "$TS" || true

    # Delete logs older than 7 days. Prefer -delete; fallback to -exec for BusyBox.
    if ! find "$LOGDIR" -type f -name 'typescript-*.log' -mtime +7 -delete 2>/dev/null; then
        find "$LOGDIR" -type f -name 'typescript-*.log' -mtime +7 -exec rm -f {} + 2>/dev/null || true
    fi

    # Start script(1) and log to the unique file. Use user's $SHELL. Flags: -q -f -c.
    USER_SHELL="$(ps -p $$ -o comm=)"
    # Ensure script(1) exists. Do not run here to avoid blocking.
    if ! command -v script >/dev/null 2>&1; then
        echo "Warning: 'script' command not found; session logging disabled." >&2
        return 0 2>/dev/null || exit 0
    fi

    # Prefer util-linux flags. Replace current process with the recorded shell.
    # Fallback to alternate flag form if the first fails.
    exec script -q -f -c "$USER_SHELL --login" "$TS" 2>/dev/null || \
        exec script --flush --command "$USER_SHELL --login" "$TS"
else
    # Inside recorded shell (UNDER_SCRIPT=1): install hooks.
    # For bash: print a powerline-style timestamp when on a TTY; fallback to ASCII otherwise.
    # Note: The glyph "" requires a powerline-compatible font. Without it, a placeholder may appear.
    WTF_PROMPT_HOOK='__wtf_status=$?; \
    if [ -t 1 ]; then \
        __wtf_ts=$(date +%Y-%m-%dT%H:%M:%S); \
        # Green background + black text for timestamp block, then green arrow, then reset. \
        printf "\033[42m\033[30m %s \033[0m\033[32m\033[0m\n" "$__wtf_ts"; \
    else \
        __wtf_ts=$(date +%Y-%m-%dT%H:%M:%S); \
        printf "%s %s %s\n" "-----" "$__wtf_ts" "-----"; \
    fi; \
    (exit $__wtf_status)'
    if [ -n "$BASH_VERSION" ]; then
        if [ -n "$PROMPT_COMMAND" ]; then
            export PROMPT_COMMAND="$PROMPT_COMMAND; $WTF_PROMPT_HOOK"
        else
            export PROMPT_COMMAND="$WTF_PROMPT_HOOK"
        fi
    fi

    if [ -n "$ZSH_VERSION" ]; then
        __wtf_precmd() {
            local st=$?
            if [ -t 1 ]; then
                # Powerline-style: green segment with timestamp and a right arrow.
                print -P -- "%K{green}%F{0} %D{%Y-%m-%dT%H:%M:%S} %f%k%F{green}%f"
            else
                local ts=$(date +%Y-%m-%dT%H:%M:%S)
                printf "%s %s %s\n" "-----" "$ts" "-----"
            fi
            return $st
        }
    autoload -U add-zsh-hook 2>/dev/null || true
        if command -v add-zsh-hook >/dev/null 2>&1 || typeset -f add-zsh-hook >/dev/null 2>&1; then
            add-zsh-hook -Uz precmd __wtf_precmd 2>/dev/null || add-zsh-hook precmd __wtf_precmd 2>/dev/null || true
        else
            # Fallback: append to precmd_functions if available; else define precmd.
            typeset -ga precmd_functions 2>/dev/null || true
            if [ -n "${precmd_functions+set}" ]; then
                case " ${precmd_functions[@]} " in
                    *" __wtf_precmd "*) :;;
                    *) precmd_functions+=(__wtf_precmd);;
                esac
            elif ! typeset -f precmd >/dev/null 2>&1; then
                precmd() { __wtf_precmd; }
            fi
        fi
    fi
fi
