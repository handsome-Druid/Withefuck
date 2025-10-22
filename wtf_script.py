#!/usr/bin/env python3
import re
from pathlib import Path
import pathlib
import json
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
    # Remove CSI/OSC and other control sequences, normalize backspaces
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

def is_prompt(line, prompt_re, generic_re):
    return prompt_re.match(line) or generic_re.match(line)

def is_wtf(cmd):
    if cmd is None:
        return False
    # Match only our helper invocations exactly (case-insensitive)
    s = cmd.strip().lower()
    return s == 'wtf' or s == 'wtf --logs'

def append_result(results, current_cmd, current_output):
    if current_cmd is not None:
        results.append((current_cmd, "\n".join(current_output).strip()))

def parse_lines(lines, prompt_re, generic_re, zsh_re=None):
    results = []
    current_cmd = None
    current_output = []
    for line in lines:
        # Prefer zsh/p10k rule (captures content after the last terminator)
        match = None
        if zsh_re:
            match = zsh_re.match(line)
        if not match:
            match = is_prompt(line, prompt_re, generic_re)
        if match:
            candidate = (match.group(1) or '').strip()
            # Remove possible keypad toggles residues if any remain
            candidate = candidate.strip('=>')
            # Only start a new command when there is an actual candidate
            if candidate:
                append_result(results, current_cmd, current_output)
                current_cmd = candidate
                current_output = []
            else:
                # Likely a prompt-only line or an output line falsely matched by generic pattern
                # If we're collecting output for a command, keep the line as output
                if current_cmd is not None:
                    current_output.append(line)
                # Otherwise, ignore and continue without cutting a block
                continue
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
            s = (cmd or '').strip().lower()
            # Merge only plain 'wtf' invocations into previous command
            if s == 'wtf':
                merge_wtf_commands(filtered, out)
                continue
            # Drop 'wtf --logs' entirely (don't merge, don't keep)
            if s == 'wtf --logs':
                continue
            # For any other matches (future-proof), merge by default
            merge_wtf_commands(filtered, out)
            continue
        filtered.append((cmd, out))
    return filtered

def extract_commands(text: str):
    """
    Parse bash/zsh script logs to extract commands and their outputs.
    兼容常见 zsh/powerlevel10k 提示符，包括：➜、❯、%、→、±、»、›、>、#、$、以及 Powerline 符号如 。

    解析策略：
    - 使用“最后一个提示符结束符”后的内容作为命令（避免多段彩色/图标提示符干扰）。
    - 允许多行提示符（命令常出现在最后一行，前缀为上述结束符之一）。
    - 过滤空命令；与 wtf 自身相关的命令会被合并到前一个命令的输出中。
    """
    lines = text.splitlines()
    # 传统 bash/root 风格（带 conda 环境与路径）的提示符：(... ) user@host:path# <cmd>
    prompt_re = re.compile(r'^\([^)]*\)\s*\S+@[^:]+:[^#]+[#\$]\s*(.*)$')

    # 常见“提示符结束符”集合（取最后一次出现作为命令起点）
    # 包含：# $ % ❯ ➜ → λ ± » › ⋗ ᐅ ⟩ ⟫ ▶ ▷ ‣ ⮞ 以及 Powerline 分隔符 
    prompt_end_chars = '#$%❯➜→λ±»›⋗ᐅ⟩⟫▶▷‣⮞>'
    esc_end = re.escape(prompt_end_chars)

    # 通用 zsh/p10k 匹配：抓取“行内最后一个提示符结束符”后的全部内容
    # 例：⚡ user@host  /path   main ±  ls
    #                              ^^^^^^^^ 最后一个结束符（）之后捕获到 ls
    zsh_re = re.compile(rf'^.*[{esc_end}]\s+(.+)$')

    # 保守通用匹配：<任意非结束符> + <结束符其一> + <命令>
    # 保守通用匹配：<任意非结束符> + <结束符其一> + <命令>
    # 额外规则：避免把以可选空白后紧跟 # 的行（如脚本注释、"    # note"）当成提示符
    generic_re = re.compile(rf'^(?!\s*#)[^{esc_end}]+[{esc_end}]\s*(.*)$')

    results = parse_lines(lines, prompt_re, generic_re, zsh_re)

    # 后置过滤：
    cleaned = []
    for cmd, out in results:
        if not cmd:
            continue
        # 去掉首尾空白
        cmd = cmd.strip()
        # 丢弃仅有提示符或空的情况
        if not cmd:
            continue
        # 命令起始字符的简单校验：字母/数字/./~/`/"/'/-/_ 等常见情况
        if not re.match(r"[A-Za-z0-9\./~`\"'-]", cmd):
            # 仍允许，比如以括号或感叹号开头的历史/子进程调用，但避免过度误判
            continue
        cleaned.append((cmd, out))

    filtered = filter_wtf_commands(cleaned)
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

def get_history_count():
    config_path = str(PROJECT_DIR / WTF_CONFIG_FILENAME)
    config, existed, load_err = _wtf_load_config(config_path)
    if load_err:
        return None
    return config.get("history_count")

def main():
    try:
        history_count = int(get_history_count())
    except (ValueError, TypeError) or history_count > 100 or history_count <= 0:
        print("Warning: could not load configuration. Please run 'wtf --config'.")
        return
    if history_count > 100 or history_count <= 0:
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