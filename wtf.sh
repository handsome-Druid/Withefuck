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

  if echo $0 | grep -q "dash"; then
    SCRIPT_DIR="/usr/local/bin"
  fi

# Decide runtime mode strictly by version.txt suffix: "*-py" or "*-rs"
_WTF_VERSION_FILE="${SCRIPT_DIR}/version.txt"
_WTF_VERSION=""
if [ -f "$_WTF_VERSION_FILE" ]; then
  _WTF_VERSION="$(sed -n '1p' "$_WTF_VERSION_FILE" | tr -d '\r' | tr -d ' ')"
fi

_WTF_MODE="invalid"
case "$_WTF_VERSION" in
  *-rs) _WTF_MODE="rs" ;;
  *-py) _WTF_MODE="py" ;;
esac

# Fixed rust binary path to use under -rs mode
WTF_BIN="/usr/local/bin/wtf"

# Define shell integration function (available when this file is sourced).
_wtf_define_shell_func() {
  wtf() {
    # Validate version marker at runtime
    if [ "$_WTF_MODE" = "invalid" ]; then
      echo "Invalid or missing version.txt. Expected version to end with -py or -rs. Please reinstall correctly." >&2
      return 1
    fi

    # If user provided args, forward them. Special-case --config to prefer
    # installed `withefuck` executable if available.
    if [ "$#" -gt 0 ]; then
      # Always keep uninstall handled here
      for a in "$@"; do
        if [ "$a" = "--uninstall" ]; then
          "${SCRIPT_DIR}/uninstall.sh"
          return $?
        elif [ "$a" = "--update" ]; then
          "${SCRIPT_DIR}/update.sh"
          return $?
        fi
      done

      if [ "$_WTF_MODE" = "rs" ]; then
        # Always forward to rust binary under -rs mode
        if [ ! -x "$WTF_BIN" ]; then
          echo "Rust mode selected by version.txt but /usr/local/bin/wtf is not installed or not executable." >&2
          return 1
        fi
        "$WTF_BIN" "$@"
        return $?
      else
        # Python mode: handle known options
        for a in "$@"; do
          if [ "$a" = "--config" ]; then
            "${SCRIPT_DIR}/wtf.py" --config
            return $?
          fi
          if [ "$a" = "--logs" ]; then
            "${SCRIPT_DIR}/wtf_script.py"
            return $?
          fi
          if [ "$a" = "--version" ] || [ "$a" = "-V" ]; then
            if [ -f "${SCRIPT_DIR}/version.txt" ]; then
              echo -n "wtf "
              sed -n '1p' "${SCRIPT_DIR}/version.txt"
              echo
              return 0
            else
              echo "Version information not available."
              return 1
            fi
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
            echo "  --update           Update Withefuck
            echo "  --uninstall        Uninstall Withefuck"
            echo "  -h, --help         Show this help text"
            echo "  -V, --version      Show version"
            return 0
          fi
        done
        echo "Unknown argument: $1"
        return 1
      fi
    fi

    if [ "$_WTF_MODE" = "rs" ]; then
      # Rust mode: delegate behavior entirely to binary
      if [ ! -x "$WTF_BIN" ]; then
        echo "Rust mode selected by version.txt but /usr/local/bin/wtf is not installed or not executable." >&2
        return 1
      fi
      "$WTF_BIN"
      return $?
    else
      # Python mode behavior (existing suggest + confirm flow)
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
      echo -en "$_prompt" 1>&2
      IFS= read -r reply || {
        return 1
      }

      if [ -z "$reply" ]; then
        eval "$cmd"
        return $?
      else
        return 0
      fi
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


