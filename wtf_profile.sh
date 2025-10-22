# This script sets up unique shell session logging and log rotation.
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

    # Generate a unique log name for this session: timestamp, random, PID, TTY
    TTY_NAME=$(tty 2>/dev/null | sed 's#/dev/##; s#/#_#g')
    if [ -z "$TTY_NAME" ]; then
        TTY_NAME="unknown"
    fi
    # Use $RANDOM when available; fall back to empty (keep $$ and timestamp
    # to preserve uniqueness) so this works in shells without $RANDOM.
    TS="$LOGDIR/typescript-$(date +%Y%m%dT%H%M%S)-${RANDOM:-}-$$-$TTY_NAME.log"

    # Export for other programs (e.g. script.py)
    export WTF_TYPESCRIPT="$TS"

    # Ensure file exists immediately
    touch "$TS" || true

    # Delete logs older than 7 days. Prefer -delete; if not supported, fall
    # back to -exec rm -f {} + so BusyBox find still works.
    if ! find "$LOGDIR" -type f -name 'typescript-*.log' -mtime +7 -delete 2>/dev/null; then
        find "$LOGDIR" -type f -name 'typescript-*.log' -mtime +7 -exec rm -f {} + 2>/dev/null || true
    fi

    # Start script and log to unique file. Prefer user's $SHELL to avoid forcing
    # bash when the user uses zsh. Use common flags for `script` (`-q -f -c`).
    USER_SHELL="$(ps -p $$ -o comm=)"
    # Ensure `script` exists. Don't try to run it here (that would block);
    # if missing, bail out (return when sourced, exit when executed).
    if ! command -v script >/dev/null 2>&1; then
        echo "Warning: 'script' command not found; session logging disabled." >&2
        return 0 2>/dev/null || exit 0
    fi

    # Prefer util-linux style flags. Use exec to replace current process with
    # the recorded shell. If the first form fails immediately, fall back to
    # the other common form.
    exec script -q -f -c "$USER_SHELL --login" "$TS" 2>/dev/null || \
        exec script --flush --command "$USER_SHELL --login" "$TS"
fi
