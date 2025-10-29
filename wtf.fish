# fish integration for Withefuck
# This file is sourced by fish (conf.d) to define a `wtf` function compatible with fish.

# Determine the directory where this file resides (resolve symlinks if possible)
set -l _src (status filename)
if test -z "$_src"
    set -l _src (status current-filename 2>/dev/null)
end
set -l _wtf_realpath "$_src"
if type -q readlink
    set -l maybe (readlink -f "$_src" 2>/dev/null)
    if test -n "$maybe"
        set _wtf_realpath "$maybe"
    end
end
set -l SCRIPT_DIR (dirname "$_wtf_realpath")

# Decide runtime mode strictly by version.txt suffix: "*-py" or "*-rs"
set -l _WTF_VERSION_FILE "$SCRIPT_DIR/version.txt"
set -l _WTF_VERSION ""
if test -f "$_WTF_VERSION_FILE"
    set _WTF_VERSION (head -n 1 "$_WTF_VERSION_FILE" | tr -d '\r' | tr -d ' ')
end

set -l _WTF_MODE "invalid"
switch $_WTF_VERSION
    case '*-rs'
        set _WTF_MODE 'rs'
    case '*-py'
        set _WTF_MODE 'py'
end

set -l WTF_BIN ""
if test "$_WTF_MODE" = 'rs'
    set WTF_BIN "$SCRIPT_DIR/wtf"
else if test "$_WTF_MODE" = 'py'
    set WTF_BIN "$SCRIPT_DIR/wtf.py"
end

function __wtf_print_help --description 'Print Withefuck help'
    if test -f "$SCRIPT_DIR/uninstall.sh"; and test -f "$SCRIPT_DIR/update.sh"
        echo "Withefuck - Command line tool to fix your previous console command."
        echo
        echo "Usage:"
        echo "  wtf                Suggest fix for last command"
        echo
        echo "Options:"
        echo "  --config           Configure Withefuck"
        echo "  --logs             View shell logs"
        echo "  --update           Update Withefuck"
        echo "  --uninstall        Uninstall Withefuck"
        echo "  -h, --help         Show this help text"
        echo "  -V, --version      Show version"
    else
        echo "Withefuck - Command line tool to fix your previous console command."
        echo
        echo "Usage:"
        echo "  wtf                Suggest fix for last command"
        echo
        echo "Options:"
        echo "  --config           Configure Withefuck"
        echo "  --logs             View shell logs"
        echo "  -h, --help         Show this help text"
        echo "  -V, --version      Show version"
    end
end

function wtf --description 'Withefuck (fish)'
    # Validate version marker at runtime
    if test "$_WTF_MODE" = 'invalid'
        echo "Invalid or missing version.txt. Please don't tamper with it." >&2
        return 1
    end

    # Handle args first
    if test (count $argv) -gt 0
        for a in $argv
            switch $a
                case '--uninstall'
                    if test -f "$SCRIPT_DIR/uninstall.sh"
                        "$SCRIPT_DIR/uninstall.sh"
                        return $status
                    else
                        echo "Unknown argument: $argv[1]"
                        return 1
                    end
                case '--update'
                    if test -f "$SCRIPT_DIR/update.sh"
                        "$SCRIPT_DIR/update.sh"
                        return $status
                    else
                        echo "Unknown argument: $argv[1]"
                        return 1
                    end
                case '--help' '-h'
                    __wtf_print_help
                    return 0
                case '--version' '-V'
                    if test -f "$SCRIPT_DIR/version.txt"
                        echo -n "wtf "
                        head -n 1 "$SCRIPT_DIR/version.txt"
                        echo
                        return 0
                    else
                        echo "Version information not available."
                        return 1
                    end
            end
        end

        for a in $argv
            switch $a
                case '--config'
                    "$WTF_BIN" --config
                    return $status
                case '--logs'
                    if test "$_WTF_MODE" = 'rs'
                        "$WTF_BIN" --logs
                        return $status
                    else
                        if test -f "$SCRIPT_DIR/wtf_script.py"
                            "$SCRIPT_DIR/wtf_script.py"
                            return $status
                        else
                            echo "wtf_script.py not found in $SCRIPT_DIR" >&2
                            return 1
                        end
                    end
            end
        end
        echo "Unknown argument: $argv[1]"
        return 1
    end

    # Ensure executables are marked executable if present
    if test -f "$WTF_BIN"; and not test -x "$WTF_BIN"
        chmod +x "$WTF_BIN" ^/dev/null
    end
    if test -f "$SCRIPT_DIR/wtf_script.py"; and not test -x "$SCRIPT_DIR/wtf_script.py"
        chmod +x "$SCRIPT_DIR/wtf_script.py" ^/dev/null
    end

    # Get suggestion
    set -l raw_out ("$WTF_BIN" --suggest 2>/dev/null)
    set -l out (printf '%s' "$raw_out" | tr -d '\r' | string trim)

    if test -z "$out"
        echo "Incomplete configuration. Please run 'wtf --config' to set up." >&2
        return 1
    end

    set -l cmd "$out"
    if test "$cmd" = 'Conferror'
        echo "Incomplete configuration. Please run 'wtf --config' to set up." >&2
        return 1
    end

    if test "$cmd" = 'None' ; or string match -q 'None *' -- "$cmd"
        echo "Unable to fix the command or no fix needed." >&2
        return 0
    end

    # Print suggestion for visibility and prompt to execute
    echo -n "$cmd "
    # Simple, portable prompt without relying on termcap in fish
    set -l prompt '[enter/ctrl+c] '
    read -P "$prompt" reply
    if test -z "$reply"
        eval $cmd
        return $status
    else
        return 0
    end
end
