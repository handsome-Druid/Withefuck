#!/usr/bin/env python3
import os
import sys
import subprocess
import json
import requests
import argparse
from typing import Optional, Tuple, Dict


import pathlib
PROJECT_DIR = pathlib.Path(__file__).resolve().parent
WTF_CONFIG_FILENAME = "wtf.json"

# Try to import parsing utilities from wtf_script.py. We import lazily inside the
# method to avoid import-time side effects when running the config path.

def _wtf_lang_of(cfg: Dict) -> str:
    return cfg.get("language", "en") if isinstance(cfg, dict) else "en"

def _wtf_load_config(path: str) -> Tuple[Dict, bool, Optional[Exception]]:
    try:
        with open(path, "r") as f:
            return json.load(f), True, None
    except Exception as e:
        return {}, False, e

def _wtf_save_config(path: str, cfg: Dict) -> Tuple[bool, Optional[Exception]]:
    try:
        with open(path, "w") as f:
            json.dump(cfg, f, indent=2)
        return True, None
    except Exception as e:
        return False, e

def _wtf_prompt_field(key: str, desc: str, cfg: Dict) -> bool:
    current = cfg.get(key, "")
    prompt = f"{desc} [{current}]: " if current else f"{desc}: "
    try:
        value = input(prompt).strip()
    except EOFError:
        value = ""
    if value:
        cfg[key] = value
        return True
    if key in cfg:
        return True
    if key == "language":
        cfg[key] = "en"
        return True
    if key == "history_count":
        cfg[key] = 3
        return True
    lang = _wtf_lang_of(cfg)
    print(f"{key} 是必填项！" if lang == "zh" else f"{key} is required!")
    return False

def _wtf_report_load_error(config: Dict, load_err: Optional[Exception]) -> None:
    if not load_err:
        return
    lang = _wtf_lang_of(config)
    if isinstance(load_err, json.JSONDecodeError):
        print("wtf.json 格式无效，重新开始配置。" if lang == "zh" else "Invalid wtf.json format, starting fresh configuration.")
    else:
        print(f"读取配置时出错: {load_err}" if lang == "zh" else f"Error reading configuration: {load_err}", file=sys.stderr)

def _wtf_notify_existing_config(config: Dict, existed: bool) -> None:
    if not (existed and config):
        return
    lang = _wtf_lang_of(config)
    if lang == "zh":
        print("找到现有配置。按回车保持当前值。")
    else:
        print("Existing configuration found. Press Enter to keep current values.")

def _wtf_save_and_report(config_path: str, config: Dict) -> None:
    ok, save_err = _wtf_save_config(config_path, config)
    lang = _wtf_lang_of(config)
    if ok:
        print(f"配置已保存到 {config_path}" if lang == "zh" else f"Configuration saved to {config_path}")
    else:
        print(f"保存配置时出错: {save_err}" if lang == "zh" else f"Error saving configuration: {save_err}", file=sys.stderr)
        sys.exit(1)
def update_config() -> None:
    """Interactive configuration for wtf.json"""
    config_path = str(PROJECT_DIR / WTF_CONFIG_FILENAME)

    config, existed, load_err = _wtf_load_config(config_path)
    _wtf_report_load_error(config, load_err)
    _wtf_notify_existing_config(config, existed)

    # Fields to prompt the user for.
    fields = {
        "api_key": "API Key",
        "api_endpoint": "API Endpoint (e.g. https://api.openai.com/v1/chat/completions)",
        "model": "Model name (e.g. gpt-4)",
        "language": "Prompt language (en/zh)",
        "history_count": "Number of previous commands to include in context (default 3)"
    }

    for key, desc in fields.items():
        if not _wtf_prompt_field(key, desc, config):
            return

    _wtf_save_and_report(config_path, config)

class CommandFixer:
    def __init__(self, api_key: str, api_endpoint: str, model: str, language: str = "en", history_count: int = 5):
        """Initialize the command fixer
        Args:
            api_key: LLM API key
            api_endpoint: LLM API endpoint
            model: LLM model name
            language: prompt language (en/zh)
        """
        self.api_key = api_key
        self.api_endpoint = api_endpoint
        self.model = model
        self.language = language
        self.history_count = int(history_count)
    def get_last_command(self) -> Tuple[str, str]:
        """Get the last command and its output.

        Preference order:
        Parse latest script log using the logic from script.py (get_last_n_commands)
        Returns (command, output) or ("", error_message)
        """
        # First attempt: use wtf_script.py parsing utilities if available.
        try:
            # Import lazily to avoid interfering with --config flow or environments
            from wtf_script import get_last_n_commands, get_latest_log, clean_text, extract_commands  # type: ignore
        except Exception:
            get_last_n_commands = None  # type: ignore

        if get_last_n_commands:
            try:
                cmds = get_last_n_commands(self.history_count)
                if cmds:
                    return cmds[-1]
            except FileNotFoundError as e:
                # no script logs found, will fallback
                pass
            except Exception as e:
                # parsing failed, log verbose info to stderr
                print(f"日志解析错误: {e}" if self.language == "zh" else f"Log parse error: {e}", file=sys.stderr)

    def get_fixed_command(self, command: str, ) -> Optional[str]:
        """Call LLM API to get the fixed command"""
        context = self._build_context()
        prompt = self._build_prompt(context)
        return self._call_llm_api(prompt)

    def _build_context(self) -> str:
        context_parts = []
        hist_n = self.history_count
        previous_commands = self._get_previous_commands(hist_n)
        if previous_commands:
            context_parts.append(previous_commands)
        return "\n\n----\n\n".join([p for p in context_parts if p])


    def _get_previous_commands(self, hist_n: int) -> str:
        try:
            from wtf_script import get_latest_log, clean_text, extract_commands  # type: ignore
            log_path = get_latest_log()
            raw = log_path.read_text(errors="ignore")
            cleaned = clean_text(raw)
            cmds = extract_commands(cleaned)
            tail_cmds = cmds[-hist_n:] if cmds else []
            formatted = []
            for c, o in tail_cmds:
                if c:
                    formatted.append(f"{c}\n\n{o}")
            if formatted:
                return "\n\n".join(formatted)
        except Exception:
            pass
        return ""

    def _build_prompt(self, full_context: str) -> str:
        return (
            "You are given a shell session log and a previous AI attempt (if any). "
            "Use the context to produce a corrected shell command that fixes the error."
            "Only correct the last command in the context.\n\n"
            f"Context:\n{full_context}\n\n"
            "Only return the corrected command, do not include any explanation. "
            "If the command is correct or cannot be fixed, return 'None'."
        )

    def _call_llm_api(self, prompt: str) -> Optional[str]:
        payload = {
            "model": self.model,
            "messages": [
                {"role": "user", "content": prompt}
            ]
        }
        # print("\n--- Payload to be sent to LLM API ---\n" + json.dumps(payload, ensure_ascii=False, indent=2) + "\n--- End Payload ---\n")
        try:
            response = requests.post(
                self.api_endpoint,
                headers={
                    "Content-Type": "application/json",
                    "Authorization": f"Bearer {self.api_key}"
                },
                json=payload
            )
            if response.status_code == 200:
                response_json = response.json()
                choices = response_json.get("choices", [])
                if choices and "message" in choices[0] and "content" in choices[0]["message"]:
                    fixed_command = choices[0]["message"]["content"].strip()
                    return None if fixed_command == "None" else fixed_command
                print(f"API响应格式错误: {response_json}" if self.language == "zh" else f"API response format error: {response_json}")
                return None
            print(f"API调用失败: {response.text}" if self.language == "zh" else f"API call failed: {response.text}")
            return None
        except Exception as e:
            print(f"API调用错误: {e}" if self.language == "zh" else f"API call error: {e}", file=sys.stderr)
            return None
    def execute_command(self, command: str) -> None:
        """Execute the fixed command"""
        os.system(command)

def load_config(config_path: str) -> dict:
    if not os.path.exists(config_path):
        print("Config file not found. Please run 'wtf --config' first.", file=sys.stderr)
        sys.exit(1)
    try:
        with open(config_path, "r") as f:
            return json.load(f)
    except (json.JSONDecodeError, IOError) as e:
        # Default to English if config can't be loaded
        lang = "en"
        try:
            with open(config_path, "r") as f:
                cfg = json.load(f)
                lang = cfg.get("language", "en")
        except Exception:
            pass
        print("读取配置文件时出错: {e}" if lang == "zh" else f"Error reading config file: {e}", file=sys.stderr)
        print("请运行 'wtf --config' 重新配置" if lang == "zh" else "Please run 'wtf --config' to reconfigure", file=sys.stderr)
        sys.exit(1)

def validate_config(config: dict) -> Tuple[str, str, str, str]:
    api_key = config.get("api_key")
    api_endpoint = config.get("api_endpoint")
    model = config.get("model")
    language = config.get("language", "en")
    history_count = config.get("history_count", 5)
    if not api_key or not api_endpoint or not model or not language or not history_count:
        print("配置不完整，请运行 'wtf --config' 进行设置" if language == "zh" else "Incomplete configuration. Please run 'wtf --config' to set up.", file=sys.stderr)
        sys.exit(1)
    return api_key, api_endpoint, model, language, history_count

def run_fixer(fixer: CommandFixer, language: str) -> None:
    try:
        command = fixer.get_last_command()
        fixed_command = fixer.get_fixed_command(command)
        if not fixed_command:
            print("无法修正命令或不需要修正。" if language == "zh" else "Unable to fix the command or no fix needed.", file=sys.stderr)
            return
        print(f"\n{fixed_command}")
        input("\n回车执行，Ctrl+C取消..." if language == "zh" else "\nEnter to execute, Ctrl+C to cancel...")
        result = subprocess.run(
            fixed_command,
            shell=True,
            capture_output=True,
            text=True
        )
        new_output = result.stdout + result.stderr
        print(f"{new_output}")
    except KeyboardInterrupt:
        print("\n操作已取消" if language == "zh" else "\nOperation cancelled", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"出错: {e}" if language == "zh" else f"Error: {e}", file=sys.stderr)
        sys.exit(1)
def main():
    parser = argparse.ArgumentParser(description="Command line fixer using LLM")
    parser.add_argument("--config", action="store_true", help="Configure wtf.json interactively")
    args = parser.parse_args()
    if args.config:
        update_config()
        return
    config_path = str(PROJECT_DIR / WTF_CONFIG_FILENAME)
    config = load_config(config_path)
    api_key, api_endpoint, model, language, history_count = validate_config(config)
    fixer = CommandFixer(api_key, api_endpoint, model, language, history_count)
    run_fixer(fixer, language)

if __name__ == "__main__":
    main()

