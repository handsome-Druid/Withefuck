# Determine the directory this file lives in in a way that works for bash and zsh
# and when the file is sourced or executed.
_detect_script_path() {
  if [ -n "${ZSH_VERSION:-}" ]; then
    _src="${(%):-%x}"
  elif [ -n "${BASH_VERSION:-}" ] || [ -n "${BASH_SOURCE:-}" ]; then
    # In bash, BASH_SOURCE may be an array; use the first element if present.
    _src="${BASH_SOURCE[0]:-$0}"
  else
    # POSIX sh (ash/dash) doesn't provide BASH_SOURCE; fall back to $0.
    _src="$0"
  fi
  if command -v readlink >/dev/null 2>&1; then
    _wtf_realpath="$(readlink -f "$_src" 2>/dev/null || printf '%s' "$_src")"
  else
    _wtf_realpath="$_src"
  fi
  SCRIPT_DIR="$(cd "$(dirname "$_wtf_realpath")" && pwd)"
}
_detect_script_path
unset -f _detect_script_path

  # If running under ash, fallback SCRIPT_DIR to /usr/local/bin (ash cannot
  # reliably determine sourced script path in the same way bash/zsh do).
  if [ -n "${ASH_VERSION:-}" ] || [ "$(basename "${SHELL:-}")" = "ash" ]; then
    SCRIPT_DIR="/usr/local/bin"
  fi

# Define shell integration function (available when this file is sourced).
_wtf_define_shell_func() {
  wtf() {
    # If user provided args, forward them. Special-case --config to prefer
    # installed `withefuck` executable if available.
    if [ "$#" -gt 0 ]; then
      for a in "$@"; do
        if [ "$a" = "--config" ]; then
          "${SCRIPT_DIR}/wtf.py" --config
          return $?
        fi
        if [ "$a" = "--logs" ]; then
          "${SCRIPT_DIR}/wtf_script.py"
          return $?
        fi
        if [ "$a" = "--uninstall" ]; then
          "${SCRIPT_DIR}/uninstall.sh"
          return $?
        fi
        if [ "$a" = "--help" ] || [ "$a" = "-h" ]; then
          echo "Withefuck - Command line tool to fix your previous console command."
          echo
          echo "Usage:"
          echo "  wtf                Suggest fix for last command"
          echo
          echo "Options:"
          echo "  --config           Configure Withefuck"
          echo "  --logs             View shell logs"
          echo "  --uninstall        Uninstall Withefuck"
          echo "  -h, --help         Show this help message"
          return 0
        fi
        echo "Unknown argument: $a"
        return 1
      done
    fi

    # Ensure the wrapper script is executable
    if [ ! -x "${SCRIPT_DIR}/wtf.py" ] && [ -f "${SCRIPT_DIR}/wtf.py" ]; then
      chmod +x "${SCRIPT_DIR}/wtf.py" || true
    fi

    # Call the wrapper to get suggestion (format: <cmd>)
  raw_out="$("${SCRIPT_DIR}/wtf.py" --suggest 2>/dev/null || true)"
  out="$(printf '%s' "$raw_out" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

    if [ -z "$out" ]; then
      >&2 echo "Incomplete configuration. Please run 'wtf --config' to set up."
      return 1
    fi

    cmd="$out"

    if [ "$cmd" = "Conferror" ]; then
      >&2 echo "Incomplete configuration. Please run 'wtf --config' to set up."
      return 1
    fi

    case "$cmd" in
      None|None\ *)
        >&2 echo "Unable to fix the command or no fix needed."
        return 0
        ;;
    esac

    # Print suggestion for visibility
    echo -n "$cmd "


      # Portable colored prompt (safe for zsh/bash)
    if [ -z "${WTF_NO_COLOR:-}" ] && [ -z "${NO_COLOR:-}" ] && [ -t 1 ]; then
      # Use literal ANSI codes safely
      _green='\033[32m'
      _red='\033[31m'
      _reset='\033[0m'
      _prompt="[${_green}enter${_reset}/${_red}ctrl+c${_reset}] "
    else
      _prompt="[enter/ctrl+c] "
    fi

    # Safe echo (no tput)
    echo -ne "$_prompt" 1>&2
    IFS= read -r reply || {
      return 1
    }

    if [ -z "$reply" ]; then
      eval "$cmd"
      return $?
    else
      return 0
    fi
  }
}

# If the file is sourced, define the function and stop.
# If the file is sourced, define the function and stop. Use a portable "sourced"
# detection: trying to `return` succeeds only when sourced.
if (return 0 2>/dev/null); then
  _wtf_define_shell_func
  unset -f _wtf_define_shell_func
  return 0 2>/dev/null || true
fi


