#!/usr/bin/env bash

# Determine the directory this file lives in in a way that works for bash and zsh
# and when the file is sourced or executed.
_detect_script_path() {
  if [ -n "${ZSH_VERSION:-}" ]; then
    _src="${(%):-%x}"
  else
    _src="${BASH_SOURCE[0]:-$0}"
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
WTFSCRIPT="$SCRIPT_DIR/wtf.py"

# Define shell integration function (available when this file is sourced).
_wtf_define_shell_func() {
  wtf() {
    # If user provided args, forward them. Special-case --config to prefer
    # installed `withefuck` executable if available.
    if [[ "$#" -gt 0 ]]; then
      for a in "$@"; do
        if [[ "$a" == "--config" ]]; then
          "${SCRIPT_DIR}/wtf.py" --config
          return $?
        fi
        if [[ "$a" == "--logs" ]]; then
          "${SCRIPT_DIR}/wtf_script.py"
          return $?
        fi
        if [[ "$a" == "--uninstall" ]]; then
          "${SCRIPT_DIR}/uninstall.sh"
          return $?
        fi
        if [[ "$a" == "--help" || "$a" == "-h" ]]; then
          echo "Withefuck - Command line tool to fix your previous console command."
          echo
          echo "Usage:"
          echo "  wtf               # Suggest fix for last command"
          echo
          echo "Options:"
          echo "  --config          # Configure Withefuck"
          echo "  --logs            # View shell logs"
          echo "  --uninstall       # Uninstall Withefuck"
          echo "  -h, --help        # Show this help message"
          return 0
        fi
        echo "Unknown argument: $a"
        return 1
      done
    fi

    # Ensure the wrapper script is executable
    if [[ ! -x "${SCRIPT_DIR}/wtf.py" && -f "${SCRIPT_DIR}/wtf.py" ]]; then
      chmod +x "${SCRIPT_DIR}/wtf.py" || true
    fi

    # Call the wrapper to get suggestion (format: <cmd> <lang>)
    raw_out="$("${SCRIPT_DIR}/wtf.py" --suggest 2>/dev/null || true)"
    out="$(echo "$raw_out" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

    if [[ -z "$out" ]]; then
      >&2 echo "Incomplete configuration. Please run 'wtf --config' to set up."
      return 1
    fi

    lang="en"
    last_token=$(awk '{print $NF}' <<<"$out")
    if [[ "$last_token" == "zh" || "$last_token" == "en" ]]; then
      lang="$last_token"
      cmd="$(echo "$out" | sed -E 's/[[:space:]]+(zh|en)$//')"
    else
      cmd="$out"
    fi

    if [[ "$cmd" == "Conferror" ]]; then
      if [[ "$lang" == "zh" ]]; then
        >&2 echo "配置不完整，请运行 'wtf --config' 进行设置"
      else
        >&2 echo "Incomplete configuration. Please run 'wtf --config' to set up."
      fi
      return 1
    fi

    if [[ "$cmd" == "None" || "$cmd" == "None "* ]]; then
      if [[ "$lang" == "zh" ]]; then
        >&2 echo "无法修正命令或不需要修正。"
      else
        >&2 echo "Unable to fix the command or no fix needed."
      fi
      return 0
    fi

    # Print suggestion for visibility
    echo "$cmd"

    if [[ "$lang" == "zh" ]]; then
      prompt="回车执行，Ctrl+C取消..."
    else
      prompt="Enter to execute, Ctrl+C to cancel..."
    fi

    # Portable prompt/read: print prompt then read input. Works in bash and zsh.
    printf "%s" "$prompt"
    IFS= read -r reply || {
      if [[ "$lang" == "zh" ]]; then
        printf "\n操作已取消\n" >&2
      else
        printf "\nOperation cancelled\n" >&2
      fi
      return 1
    }

    if [[ -z "$reply" ]]; then
      eval "$cmd"
      return $?
    else
      if [[ "$lang" == "zh" ]]; then
        >&2 echo "操作已取消"
      else
        >&2 echo "Operation cancelled"
      fi
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


