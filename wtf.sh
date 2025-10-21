#!/bin/bash
# This script sets up unique shell session logging and log rotation.

case $- in
    *i*) ;;
    *) return;;
esac

if [ -z "$UNDER_SCRIPT" ]; then
    export UNDER_SCRIPT=1
    LOGDIR="$HOME/.shell_logs"
    mkdir -p "$LOGDIR"

    # Generate a unique log name for this session: timestamp, random, PID, TTY
    TTY_NAME=$(tty 2>/dev/null | sed 's#/dev/##; s#/#_#g')
    if [ -z "$TTY_NAME" ]; then
        TTY_NAME="unknown"
    fi
    TS="$LOGDIR/typescript-$(date +%Y%m%dT%H%M%S)-$RANDOM-$$-$TTY_NAME.log"

    # Export for other programs (e.g. script.py)
    export WTF_TYPESCRIPT="$TS"

    # Ensure file exists immediately
    touch "$TS" || true

    # Delete logs older than 7 days
    find "$LOGDIR" -type f -name 'typescript-*.log' -mtime +7 -delete 2>/dev/null || true

    # Start script and log to unique file
    exec script --flush --command "bash --login" "$TS"
fi
