#!/usr/bin/env python3
import re
from pathlib import Path
import pathlib
PROJECT_DIR = pathlib.Path(__file__).resolve().parent
WTF_CONFIG_FILENAME = "wtf.json"
from wtf import _wtf_load_config

LOGDIR = Path.home() / ".shell_logs"

 # Remove ANSI color codes
# CSI: ESC [ ...
CSI_RE = re.compile(r"\x1B\[[0-?]*[ -/]*[@-~]")
# OSC: ESC ] ... BEL or ST (ESC \\)
OSC_RE = re.compile(r"\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)")
# Other single-char controls that pollute logs
CTRL_RE = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f]")

def _get_hook_regexes():
    """
    Return regexes that match the literal divider lines inserted by the prompt hooks
    after clean_text(). Supported forms now match the fixed message:
    - bash ASCII divider: "----- Shell log started. -----"
    - zsh/powerline: " Shell log started. " or "Shell log started. "
    """
    # bash ASCII divider containing the literal message
    bash_ts = re.compile(r"^-+\s+Shell log started\.\s+-+$")
    # zsh flexible: optional rounded ( ... ) or right arrow () around the literal message
    zsh_ts = re.compile(r"^\s*(?:\s*)?Shell log started\.(?:\s*|\s*)?\s*$")
    return [zsh_ts, bash_ts]

def _strip_backspaces(s: str) -> str:
    # Normalize sequences like "l\bls" -> "ls"
    out = []
    for ch in s:
        if ch == '\b':
            if out:
                out.pop()
        else:
            out.append(ch)
    return ''.join(out)

def clean_text(text: str) -> str:
    # Strip CSI/OSC control sequences; normalize backspaces and CRs
    text = CSI_RE.sub('', text)
    text = OSC_RE.sub('', text)
    # Normalize carriage returns: preserve logical line breaks instead of merging lines
    text = text.replace('\r\n', '\n')
    text = text.replace('\r', '\n')
    # Remove leftover single-char ESC sequences commonly seen in zsh logs (ESC= / ESC>)
    text = re.sub(r'\x1B[=><]', '', text)
    text = _strip_backspaces(text)
    text = CTRL_RE.sub('', text)
    return text.strip()

def is_wtf(cmd):
    if cmd is None:
        return False
    # Match only our helper invocations exactly (case-insensitive)
    s = cmd.strip().lower()
    return s == 'wtf' or s == 'wtf --logs'

def append_result(results, current_cmd, current_output):
    if current_cmd is not None:
        results.append((current_cmd, "\n".join(current_output).strip()))

def _extract_blocks_by_hooks(lines):
    """
    Split the log by hook divider lines (dividers excluded).
    Return blocks from oldest to newest (each is List[str]).
    Only keep content strictly between adjacent hook lines.
    """
    ts_res = _get_hook_regexes()
    ts_idx = [i for i, ln in enumerate(lines) if any(r.match(ln) for r in ts_res)]
    blocks = []
    if len(ts_idx) < 2:
        return blocks
    for a, b in zip(ts_idx[:-1], ts_idx[1:]):
        seg = lines[a + 1:b]
        blocks.append(seg)
    return blocks

def _block_to_cmd_out(block_lines):
    """
    Convert one block to (cmd, out).
    - cmd: first non-empty line (prompt kept as-is)
    - out: remaining lines joined and stripped
    Return None if no non-empty line exists.
    """
    if not block_lines:
        return None
    # 找第一条非空行作为命令
    cmd_line_idx = None
    for i, ln in enumerate(block_lines):
        if ln.strip():
            cmd_line_idx = i
            break
    if cmd_line_idx is None:
        return None
    # Start building command and decide where output begins
    cmd = block_lines[cmd_line_idx]
    out_start = cmd_line_idx + 1

    if out_start < len(block_lines):
        next_line = block_lines[out_start]

        # Helper: does a line contain 'wtf' not followed by specific options?
        def contains_wtf_without_help_opts(line: str) -> bool:
            # Find 'wtf' as a whole word anywhere in the line, capture what's after it on the same line
            m = re.search(r"(?i)\bwtf\b(.*)$", line)
            if not m:
                return False
            rest = m.group(1) or ""
            # If the immediate args are one of the allowed info flags, do NOT treat specially
            re_allowed = re.compile(r"(?i)^\s*(--help|-h|-V|--version|--config)\b")
            return not re_allowed.match(rest)

        # If the next line contains 'wtf' (anywhere) and isn't followed by help/version/config flags,
        # treat it as part of the command line (to support zsh themes that wrap prompts).
        if contains_wtf_without_help_opts(next_line):
            cmd = cmd + "\n" + next_line
            out_start += 1

    out = "\n".join(block_lines[out_start:]).strip()
    return (cmd, out)

def extract_last_command_simple(text: str):
    """
    Minimal extraction: take the content between the last two hook lines.
    cmd = first non-empty line in that range; out = the rest.
    Return None if fewer than two hook lines exist.
    """
    lines = text.splitlines()
    blocks = _extract_blocks_by_hooks(lines)
    if not blocks:
        return None
    last_block = blocks[-1]
    return _block_to_cmd_out(last_block)

def extract_commands_hook_only(text: str):
    """
    Extract all (cmd, out) blocks using only hook dividers. Oldest to newest.
    cmd = first non-empty line (prompt kept); out = remaining lines (stripped).
    Empty blocks are dropped. No special filtering.
    """
    lines = text.splitlines()
    blocks = _extract_blocks_by_hooks(lines)
    pairs = []
    for blk in blocks:
        item = _block_to_cmd_out(blk)
        if item is not None:
            pairs.append(item)
    return pairs

def _filter_wtf_commands_inline(results):
    """Filter/merge 'wtf' and 'wtf --logs' without relying on global order."""
    def _tail_wtf(cmd_line: str):
        """匹配行尾部的 'wtf' 或 'wtf --logs'。忽略前导提示符，只看尾部命令。"""
        if not cmd_line:
            return None
        m = re.search(r"(wtf(?:\s+--logs)?)\s*$", cmd_line, re.IGNORECASE)
        return m.group(1).lower() if m else None

    filtered = []
    for cmd, out in results:
        if cmd is None:
            continue
        tail = _tail_wtf(cmd)
        if tail == 'wtf --logs':
            # Drop this block
            continue
        if tail == 'wtf':
            # Merge output into the previous block
            if filtered:
                prev_cmd, prev_out = filtered[-1]
                prev_out = f"{prev_out}\n{out}" if prev_out else out
                filtered[-1] = (prev_cmd, prev_out)
            else:
                filtered.append(("", out))
            continue
        filtered.append((cmd, out))
    return filtered

def get_latest_log():
    # Prefer using the environment variable (WTF_TYPESCRIPT) to locate the current session log (exported by .bashrc)
    import os
    env_path = os.environ.get("WTF_TYPESCRIPT")
    if env_path:
        p = Path(env_path)
        if p.exists():
            return p

    # Fallback: select the latest typescript-*.log by name
    files = sorted(LOGDIR.glob("typescript-*.log"))
    if not files:
        raise FileNotFoundError("No script log found. Please run some commands first.")
    return files[-1]

def get_last_n_commands(n=3):
    log_path = get_latest_log()
    text = log_path.read_text(errors="ignore")
    text = clean_text(text)
    commands = extract_commands_hook_only(text)
    commands = _filter_wtf_commands_inline(commands)
    return commands[-n:]

def get_history_count():
    config_path = str(PROJECT_DIR / WTF_CONFIG_FILENAME)
    config, existed, load_err = _wtf_load_config(config_path)
    if load_err:
        return None
    return config.get("history_count")

def main():
    try:
        history_count = int(get_history_count())
    except (ValueError, TypeError):
        print("Warning: could not load configuration. Please run 'wtf --config'.")
        return
    if history_count is None or history_count > 100 or history_count <= 0:
        print("Warning: invalid history count. Please run 'wtf --config'.")
        return
    try:
        cmds = get_last_n_commands(history_count)
    except Exception as e:
        print(f"Warning: could not load configuration. Please run 'wtf --config'.")
        return
    if len(cmds) == 1:
        print(f"Last command and its output:\n")
    else:
        print(f"Last {len(cmds)} commands and their outputs:\n")
    for i, (cmd, output) in enumerate(cmds, 1):
        # print(f"=== Command {i} ===")
        print(f"$ {cmd}")
        # print("----- Output -----")
        print(output if output else "(No output)")
        print()

if __name__ == "__main__":
    main()