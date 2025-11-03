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

# OSC 0/2: Set window/icon title: ESC ] 0 ; txt BEL  or  ESC ] 0 ; txt ESC \\
OSC_TITLE_RE = re.compile(r"\x1B\]([02]);([^\x07\x1B]*)(?:\x07|\x1B\\)")

def _get_hook_regexes():
    """
    Return regexes that match the literal divider lines inserted by the prompt hooks
    after clean_text(). Supported forms now match the fixed message:
    - bash ASCII divider: "----- Shell log started. -----"
    - zsh/powerline: " Shell log started. " or "Shell log started. "
    """
    # bash ASCII divider containing the literal message
    bash_ts = re.compile(r"^-+\s+Shell log started\.\s+-+$")
    # zsh/fish flexible: optional rounded ( ... ) or right arrow () around the literal message
    zsh_ts = re.compile(r"^\s*(?:\s*)?Shell log started\.(?:\s*|\s*)?\s*$")
    # fish fallback: some setups record replacement glyphs like '?' for powerline symbols,
    # or omit glyphs entirely after cleaning; accept any trailing non-word symbol(s) or nothing
    fish_ts = re.compile(r"^\s*Shell log started\.\s*(?:[^\w\s].*)?$")
    # ultimate fallback: any line containing the literal text, case-insensitive
    generic_ts = re.compile(r"Shell log started\.", re.IGNORECASE)
    return [zsh_ts, bash_ts, fish_ts, generic_ts]

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
    # Remove other ESC-prefixed sequences commonly seen in terminals
    # - ESC Fe (single final byte in @-Z\\^_)
    text = re.sub(r'\x1B[@-Z\\^_]', '', text)
    # - ESC with one intermediate (0x20-0x2F) and a final byte (0x40-0x7E), e.g. ESC(B, ESC)0, ESC#8, ESC%G
    text = re.sub(r'\x1B[ -/][@-~]', '', text)
    # Normalize carriage returns: preserve logical line breaks instead of merging lines
    text = text.replace('\r\n', '\n')
    text = text.replace('\r', '\n')
    # Remove leftover single-char ESC sequences commonly seen in zsh logs (ESC= / ESC>)
    text = re.sub(r'\x1B[=><]', '', text)
    # Remove visible return glyphs that appear in some logs
    text = text.replace('⏎', '')
    text = _strip_backspaces(text)
    text = CTRL_RE.sub('', text)
    return text.strip()

def _clean_line(line: str) -> str:
    """Clean a single log line while preserving line alignment.
    Mirrors clean_text but operates per-line to keep indexes consistent against raw lines.
    """
    line = CSI_RE.sub('', line)
    line = OSC_RE.sub('', line)
    # Other ESC sequences
    line = re.sub(r'\x1B[@-Z\\^_]', '', line)
    line = re.sub(r'\x1B[ -/][@-~]', '', line)
    # Remove stray ESC single-char sequences
    line = re.sub(r'\x1B[=><]', '', line)
    line = line.replace('⏎', '')
    line = _strip_backspaces(line)
    line = CTRL_RE.sub('', line)
    return line

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
    ts_idx = [i for i, ln in enumerate(lines) if any(r.search(ln) for r in ts_res)]
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
    def _is_noise_line(ln: str) -> bool:
        stripped = ln.replace('⏎', '').strip()
        return stripped == ''

    def _looks_like_prompt(ln: str) -> bool:
        s = ln.strip()
        # Typical prompts end with '#' or '$' and often include user@host
        return (('@' in s) and (s.endswith('#') or s.endswith('$') or s.endswith('# ') or s.endswith('$ ')))

    cmd_line_idx = None
    for i, ln in enumerate(block_lines):
        s = ln.strip()
        if not s or _is_noise_line(s) or _looks_like_prompt(s):
            continue
        # Prefer a line that looks like an actual command (>=2 chars or contains non-alpha like space, /, -)
        if len(s) >= 2 or re.search(r'[^A-Za-z]', s):
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

def _tail_wtf(cmd_line: str):
    """Return 'wtf' or 'wtf --logs' if the line ends with it (case-insensitive), otherwise None."""
    if not cmd_line:
        return None
    m = re.search(r"(wtf(?:\s+--logs)?)\s*$", cmd_line, re.IGNORECASE)
    return m.group(1).lower() if m else None

def _filter_wtf_commands_inline(results):
    """Filter/merge 'wtf' and 'wtf --logs' without relying on global order."""
    filtered = []
    for cmd, out in results:
        if not cmd:
            continue

        tail = _tail_wtf(cmd)
        if tail == "wtf --logs":
            # Drop this block
            continue

        if tail == "wtf":
            # Merge output into the previous block (or create a placeholder if none)
            if not filtered:
                filtered.append(("", out))
                continue
            prev_cmd, prev_out = filtered[-1]
            merged_out = f"{prev_out}\n{out}" if prev_out else out
            filtered[-1] = (prev_cmd, merged_out)
            continue

        # Normal command: keep as-is
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
    raw_text = log_path.read_text(errors="ignore")

    # Work on a per-line basis to keep raw/cleaned line indices aligned
    raw_lines = raw_text.splitlines()
    cleaned_lines = [_clean_line(l) for l in raw_lines]

    # Find hook indices on cleaned lines
    ts_res = _get_hook_regexes()
    ts_idx = [i for i, ln in enumerate(cleaned_lines) if any(r.search(ln) for r in ts_res)]

    results = []
    if len(ts_idx) >= 2:
        for a, b in zip(ts_idx[:-1], ts_idx[1:]):
            blk_clean = cleaned_lines[a+1:b]
            blk_raw = raw_lines[a+1:b]

            item = _block_to_cmd_out(blk_clean)
            if item is None:
                continue
            cmd, out = item

            # Try to improve command by using the last OSC window title in raw block
            joined_raw = "\n".join(blk_raw)
            osc_matches = list(OSC_TITLE_RE.finditer(joined_raw))
            if osc_matches:
                title_txt = osc_matches[-1].group(2)
                better = _cmd_from_title(title_txt)
                if better:
                    cmd = better

            results.append((cmd, out))

    # Fallback to old path if no blocks found
    if not results:
        cleaned_text = "\n".join(cleaned_lines)
        results = extract_commands_hook_only(cleaned_text)

    results = _filter_wtf_commands_inline(results)
    return results[-n:]

def _cmd_from_title(title: str) -> str:
    """Extract command from terminal title like "[host] cmd args [cwd]".
    Heuristics:
      - If title starts with [..], drop that prefix.
      - Drop trailing token if it looks like a path (~/ or /path) or just '~'.
    """
    if not title:
        return ''
    s = title.strip()
    m = re.match(r'^\[[^\]]*\]\s+(.*)$', s)
    if m:
        s = m.group(1)
    tokens = s.split()
    if not tokens:
        return ''
    if tokens[-1] == '~' or tokens[-1].startswith('/') or tokens[-1].startswith('~'):
        tokens = tokens[:-1]
    s = ' '.join(tokens).strip()
    return s

def get_history_count():
    config_path = str(PROJECT_DIR / WTF_CONFIG_FILENAME)
    config, _, load_err = _wtf_load_config(config_path)
    if load_err:
        return None
    return config.get("history_count")

def main():
    try:
        history_count = int(get_history_count())
    except (ValueError, TypeError):
        print("Warning: could not load configuration. Please run 'wtf --config'.")
        return
    try:
        if history_count > 100 or history_count <= 0:
            print("Warning: invalid history count. Please run 'wtf --config'.")
            return
    except Exception:
        print("Warning: invalid history count. Please run 'wtf --config'.")
        return
    try:
        cmds = get_last_n_commands(history_count)
    except Exception:
        print("Warning: could not load configuration. Please run 'wtf --config'.")
        return
    if len(cmds) == 1:
        print("Last command and its output:\n")
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
