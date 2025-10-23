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

# Prefer Rust binary if installed
WTF_BIN="/usr/local/bin/wtf"
if [ ! -x "$WTF_BIN" ]; then
  # also try PATH (avoid recursion by not using function name)
  if command -v /usr/bin/command >/dev/null 2>&1; then :; fi
  _wtf_path_bin="$(command -v wtf 2>/dev/null || true)"
  case "$_wtf_path_bin" in
    */wtf) [ -x "$_wtf_path_bin" ] && WTF_BIN="$_wtf_path_bin" ;;
  esac
fi

# Define shell integration function (available when this file is sourced).
_wtf_define_shell_func() {
  wtf() {
    # If user provided args, forward them to Rust binary; keep --uninstall local.
    if [ "$#" -gt 0 ]; then
      # Always keep uninstall handled here
      for a in "$@"; do
        if [ "$a" = "--uninstall" ]; then
          "${SCRIPT_DIR}/uninstall.sh"
          return $?
        fi
      done

      if [ -x "$WTF_BIN" ]; then
        "$WTF_BIN" "$@"
        return $?
      else
        >&2 echo "wtf binary not found. Please install it to /usr/local/bin/wtf."
        return 127
      fi
    fi

    # Call Rust binary to get suggestion (format: <cmd>)
  if [ -x "$WTF_BIN" ]; then
    raw_out="$("$WTF_BIN" --suggest 2>/dev/null || true)"
  else
    >&2 echo "wtf binary not found. Please install it to /usr/local/bin/wtf."
    return 127
  fi
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
    printf '%s ' "$cmd"

    # Portable colored prompt printed to stderr
    if [ -z "${WTF_NO_COLOR:-}" ] && [ -z "${NO_COLOR:-}" ] && { [ -t 2 ] || [ -t 1 ]; }; then
      _prompt="$(printf '[\033[32menter\033[0m/\033[31mctrl+c\033[0m] ')"
    else
      _prompt="[enter/ctrl+c] "
    fi
    printf '%s' "$_prompt" 1>&2
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


