#!/usr/bin/env python3
import re
from pathlib import Path

LOGDIR = Path.home() / ".shell_logs"

 # Remove ANSI color codes
ANSI_RE = re.compile(r'\x1B\[[0-?]*[ -/]*[@-~]')

def clean_text(text: str) -> str:
    text = ANSI_RE.sub('', text)
    text = text.replace('\r', '')
    return text.strip()

def is_prompt(line, prompt_re, generic_re):
    return prompt_re.match(line) or generic_re.match(line)

def is_wtf(cmd):
    lower = cmd.lower()
    return any(x in lower for x in ['wtf.py', './wtf.py', ' python wtf.py', 'python3 wtf.py','wtf','wtf_script.py'])

def append_result(results, current_cmd, current_output):
    if current_cmd is not None:
        results.append((current_cmd, "\n".join(current_output).strip()))

def parse_lines(lines, prompt_re, generic_re):
    results = []
    current_cmd = None
    current_output = []
    for line in lines:
        match = is_prompt(line, prompt_re, generic_re)
        if match:
            append_result(results, current_cmd, current_output)
            current_cmd = match.group(1).strip()
            current_output = []
        elif current_cmd is not None:
            current_output.append(line)
    append_result(results, current_cmd, current_output)
    return results

def merge_wtf_commands(filtered, out):
    if filtered:
        prev_cmd, prev_out = filtered[-1]
        prev_out = f"{prev_out}\n{out}" if prev_out else out
        filtered[-1] = (prev_cmd, prev_out)
    else:
        filtered.append(("", out))

def filter_wtf_commands(results):
    filtered = []
    for cmd, out in results:
        if is_wtf(cmd):
            merge_wtf_commands(filtered, out)
        else:
            filtered.append((cmd, out))
    return filtered

def extract_commands(text: str):
    """
    Parse bash script logs to extract commands and their outputs.
    Compatible with prompts containing conda environment, e.g.:
    (/workspace/Withefuck/.conda) root@ubuntu:/workspace/Withefuck# ls
    """
    lines = text.splitlines()
    prompt_re = re.compile(r'^\([^)]*\)\s*\S+@[^:]+:[^#]+#\s*(.*)$')
    generic_re = re.compile(r'^[^#\$>]+[#\$>]\s*(.*)$')
    results = parse_lines(lines, prompt_re, generic_re)
    results = [(cmd, out) for cmd, out in results if cmd]
    filtered = filter_wtf_commands(results)
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

def get_last_n_commands(n=5):
    log_path = get_latest_log()
    text = log_path.read_text(errors="ignore")
    text = clean_text(text)
    commands = extract_commands(text)
    return commands[-n:]

def main():
    cmds = get_last_n_commands(5)
    print(f"Last {len(cmds)} commands and their outputs:\n")
    for i, (cmd, output) in enumerate(cmds, 1):
        print(f"=== Command {i} ===")
        print(f"$ {cmd}")
        # print("----- Output -----")
        print(output if output else "(No output)")
        print()

if __name__ == "__main__":
    main()