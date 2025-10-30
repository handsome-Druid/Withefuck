# fish integration for Withefuck session logging
# This file is sourced by fish (conf.d) to start per-session logging via script(1).

# Continue only in interactive sessions (compatible with older fish)

# if not status is-login
#     return
# end

if not status --is-interactive
    return
end

# Ensure we have a real TTY; otherwise forcing script may cause fish to exit immediately
if not test -t 1
    return
end

if test -z "$UNDER_SCRIPT"
    set -gx UNDER_SCRIPT 1
    set -l LOGDIR "$HOME/.shell_logs"
    mkdir -p "$LOGDIR"

    # Build a unique log path: timestamp, random, PID, TTY (compose as a single string)
    set -l TTY_RAW (tty 2>/dev/null)
    set -l TTY_NAME "unknown"
    if test -n "$TTY_RAW"
        set TTY_NAME (printf '%s' "$TTY_RAW" | sed 's#/dev/##; s#/#_#g')
    end
    set -l __ts (date +%Y%m%dT%H%M%S)
    set -l __rand (random)
    set - TS "$LOGDIR/typescript-$__ts-$__rand-$fish_pid-$TTY_NAME.log"

    # Export for consumers
    set -gx WTF_TYPESCRIPT "$TS"
    touch "$TS"
    if test $status -ne 0
        echo "Warning: cannot create log file at $TS; session logging disabled." 1>&2
        return
    end

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
    # Force interactive mode to avoid fish exiting if the pty is not detected as interactive
    exec script -q -f -c "fish -i --login" "$TS"; or \
    exec script --flush --command "fish -i --login" "$TS"; or \
    exec script -q -c "fish -i --login" "$TS"
else
    # After each command, print a separator like bash/zsh PROMPT_COMMAND/precmd
    # Prefer a prompt wrapper for broad fish compatibility (works even if fish_postexec is unavailable)
    if not set -q __WITHEFUCK_FISH_HOOKED
        set -g __WITHEFUCK_FISH_HOOKED 1

        # Preserve existing prompt if present
        if functions -q fish_prompt
            functions -c fish_prompt __wtf_orig_fish_prompt 2>/dev/null
        end

        function __wtf_echo_separator --description 'Withefuck: print shell log separator'
            set -l msg "Shell log started."

            printf "\033[48;5;208m\033[30m %s \033[0m\033[38;5;208m\033[0m\n" "$msg" 2>/dev/null
        end

        function fish_prompt --description 'Withefuck wrapped prompt'
            # Print separator before drawing prompt (runs after each command)
            __wtf_echo_separator
            if functions -q __wtf_orig_fish_prompt
                __wtf_orig_fish_prompt
            else
                # Minimal default prompt
                printf '%s ' (prompt_pwd)
            end
        end
    end
end