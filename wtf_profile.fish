# fish integration for Withefuck session logging
# This file is sourced by fish (conf.d) to start per-session logging via script(1).

# Continue only in interactive sessions (compatible with older fish)

if not status is-login
    return
end

if not status --is-interactive
    return
end

if test -z "$UNDER_SCRIPT"
    set -gx UNDER_SCRIPT 1
    set -l LOGDIR "$HOME/.shell_logs"
    mkdir -p "$LOGDIR"

    # Build a unique log path: timestamp, random, PID, TTY
    set -l TTY_RAW (tty 2>/dev/null)
    set -l TTY_NAME "unknown"
    if test -n "$TTY_RAW"
        set TTY_NAME (printf '%s' "$TTY_RAW" | sed 's#/dev/##; s#/#_#g')
    end
    set -l TS "$LOGDIR/typescript-"(date +%Y%m%dT%H%M%S)"-"$RANDOM"-"$fish_pid"-"$TTY_NAME".log

    # Export for consumers
    set -gx WTF_TYPESCRIPT "$TS"
    touch "$TS" 2>/dev/null

    # Delete logs older than 7 days (if find is available)
    if type -q find
        find "$LOGDIR" -type f -name 'typescript-*.log' -mtime +7 -delete 2>/dev/null; or find "$LOGDIR" -type f -name 'typescript-*.log' -mtime +7 -exec rm -f {} + 2>/dev/null
    end

    # Ensure script(1) exists
    if not type -q script
        echo "Warning: 'script' command not found; session logging disabled." 1>&2
        return
    end

    # Replace current process with the recorded shell
    # Use fish as the user shell here since we are in fish already
    exec script -q -f -c "fish --login" "$TS" 2>/dev/null; or exec script --flush --command "fish --login" "$TS"
else
    # Inside recorded shell: show a greeting once at startup
    functions -q fish_greeting; and functions -e fish_greeting
    function fish_greeting
        set -l msg "Shell log started."
        if test -t 1
            # Use basic color if available
            if type -q set_color
                set_color -b yellow
                set_color -o black
                echo -n " $msg "
                set_color normal
                echo
            else
                echo "----- $msg -----"
            end
        else
            echo "----- $msg -----"
        end
    end
end
