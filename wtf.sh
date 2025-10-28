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

if [ "$_WTF_MODE" = "rs" ]; then
  WTF_BIN="${SCRIPT_DIR}/wtf" || echo "${SCRIPT_DIR}/wtf not found"
elif [ "$_WTF_MODE" = "py" ]; then
  WTF_BIN="${SCRIPT_DIR}/wtf.py" || echo "${SCRIPT_DIR}/wtf.py not found"
  if [ ! -f ${SCRIPT_DIR}/wtf_script.py ]; then
    echo "Warning: wtf_script.py not found in ${SCRIPT_DIR}. wtf.py would not work without it." >&2
  fi
fi


# Define shell integration function (available when this file is sourced).
_wtf_define_shell_func() {
  wtf() {
    # Validate version marker at runtime
    if [ "$_WTF_MODE" = "invalid" ]; then
      echo "Invalid or missing version.txt. Please don't tamper with it." >&2
      return 1
    fi

    # If user provided args, forward them.
    if [ "$#" -gt 0 ]; then
      for a in "$@"; do
        if [ "$a" = "--uninstall" ]; then
          if [ ! -f "${SCRIPT_DIR}/uninstall.sh" ]; then
            echo "Unknown argument: $1"
            return $?
          fi
          "${SCRIPT_DIR}/uninstall.sh"
          return $?
        elif [ "$a" = "--update" ]; then
          if [ ! -f "${SCRIPT_DIR}/update.sh" ]; then
            echo "Unknown argument: $1"
            return $?
          fi
          "${SCRIPT_DIR}/update.sh"
          return $?
        elif [ "$a" = "--help" ] || [ "$a" = "-h" ]; then
          if [ -f "${SCRIPT_DIR}/uninstall.sh" ] && [ -f "${SCRIPT_DIR}/update.sh" ]; then
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
            return 0
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
            return 0
          fi
        elif [ "$a" = "--version" ] || [ "$a" = "-V" ]; then
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
      done

      for a in "$@"; do
        if [ "$a" = "--config" ]; then
          "${WTF_BIN}" --config
          return $?
        fi
        if [ "$a" = "--logs" ]; then
          if [ "$_WTF_MODE" = "rs" ]; then
            "${WTF_BIN}" --logs
            return $?
          else
            "${SCRIPT_DIR}/wtf_script.py"
            return $?
          fi
        fi
      done
      echo "Unknown argument: $1"
      return 1
    fi


    if [ ! -x "$WTF_BIN" ] && [ -f "$WTF_BIN" ]; then
      chmod +x "$WTF_BIN" || true
    fi
    if [ ! -x "${SCRIPT_DIR}/wtf_script.py" ] && [ -f "${SCRIPT_DIR}/wtf_script.py" ]; then
      chmod +x "${SCRIPT_DIR}/wtf_script.py" || true
    fi

    raw_out="$("$WTF_BIN" --suggest 2>/dev/null || true)"

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


