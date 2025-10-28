#!/usr/bin/env python3
import os
import sys
import subprocess
import json
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'vendor'))
import requests
import argparse
from typing import Optional, Tuple, Dict


import pathlib
PROJECT_DIR = pathlib.Path(__file__).resolve().parent
WTF_CONFIG_FILENAME = "wtf.json"


def _wtf_find_config_path_for_read() -> str:
    """Return the first existing config path, searching in this order:
    1. current working directory
    2. project directory (where wtf.py lives)
    3. XDG_CONFIG_HOME/withefuck/wtf.json
    4. ~/.wtf.json
    If none exist, return the project directory path (default location).
    """
    cwd_path = pathlib.Path.cwd() / WTF_CONFIG_FILENAME
    proj_path = PROJECT_DIR / WTF_CONFIG_FILENAME
    xdg_base = pathlib.Path(os.environ.get("XDG_CONFIG_HOME", "")) if os.environ.get("XDG_CONFIG_HOME") else pathlib.Path.home() / ".config"
    xdg_path = xdg_base / "withefuck" / WTF_CONFIG_FILENAME
    home_path = pathlib.Path.home() / ("." + WTF_CONFIG_FILENAME)

    for p in (cwd_path, proj_path, xdg_path, home_path):
        try:
            if p.exists():
                return str(p)
        except Exception:
            # ignore inaccessible paths
            pass
    return str(proj_path)

# Import parsing utilities from wtf_script.py lazily to avoid import-time side effects.


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
        if key == "history_count" and (int(cfg[key]) <= 0 or int(cfg[key]) > 100):
            print("history_count must be between 1 and 100.")
            return False
        if key == "temperature" and (float(cfg[key]) < 0.0 or float(cfg[key]) > 1.0):
            print("temperature must be between 0.0 and 1.0.")
            return False
        return True
    if key in cfg:
        return True
    if key == "history_count":
        cfg[key] = 3
        return True
    if key == "temperature":
        cfg[key] = 0.0
        return True
    print(f"{key} is required!")
    return False

def _wtf_report_load_error(load_err: Optional[Exception]) -> None:
    if not load_err:
        return
    if isinstance(load_err, json.JSONDecodeError):
        print("Invalid wtf.json format, starting fresh configuration.")
    else:
        print(f"Error reading configuration: {load_err}", file=sys.stderr)

def _wtf_notify_existing_config(config: Dict, existed: bool) -> None:
    if not (existed and config):
        return
    print("Existing configuration found. Press Enter to keep current values.")

def _wtf_save_and_report(config_path: str, config: Dict) -> None:
    ok, save_err = _wtf_save_config(config_path, config)
    if ok:
        print(f"Configuration saved to {config_path}")
    else:
        print(f"Error saving configuration: {save_err}", file=sys.stderr)
        sys.exit(1)
def update_config() -> None:
    """Interactive configuration for wtf.json"""
    # Always write config to the project directory when running interactive config
    config_path = str(PROJECT_DIR / WTF_CONFIG_FILENAME)

    config, existed, load_err = _wtf_load_config(config_path)
    _wtf_report_load_error(load_err)
    _wtf_notify_existing_config(config, existed)

    # Fields to prompt the user for.
    fields = {
        "api_key": "API Key",
        "api_endpoint": "API Endpoint (e.g. https://api.openai.com/v1/chat/completions)",
        "model": "Model name (e.g. gpt-4)",
        "history_count": "Number of previous commands to include in context (less than 100)",
        "temperature": "Sampling temperature for LLM (0.0-1.0)"
    }

    for key, desc in fields.items():
        if not _wtf_prompt_field(key, desc, config):
            return

    _wtf_save_and_report(config_path, config)

class CommandFixer:
    def __init__(self, api_key: str, api_endpoint: str, model: str, history_count: int = 5, temperature: float = 0.0):
        """Initialize the command fixer
        Args:
            api_key: LLM API key
            api_endpoint: LLM API endpoint
            model: LLM model name
        """
        self.api_key = api_key
        self.api_endpoint = api_endpoint
        self.model = model
        self.history_count = int(history_count)
        # temperature will default to 0 if not provided; keep as float
        self.temperature = float(temperature)
    def get_last_command(self) -> Tuple[str, str]:
        """Get the last command and its output.

        Preference order:
        Parse latest script log using the logic from script.py (get_last_n_commands)
        Returns (command, output) or ("", error_message)
        """
        # First attempt: use wtf_script.py parsing utilities if available.
        try:
            # Import lazily to avoid interfering with --config flow or environments
            from wtf_script import get_last_n_commands  # type: ignore
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
                print(f"Log parse error: {e}", file=sys.stderr)

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
        """Build context from the latest N commands using timestamp-only parsing.
        Falls back silently to empty context on any error.
        """
        try:
            from wtf_script import get_last_n_commands  # type: ignore
            tail_cmds = get_last_n_commands(hist_n)
            formatted = []
            for c, o in tail_cmds or []:
                if c is not None:
                    formatted.append(f"{c}\n\n{o}")
            return "\n\n".join(formatted)
        except Exception:
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
            ],
            "temperature": getattr(self, "temperature", 0.0)
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
                print(f"API response format error: {response_json}")
                return None
            print(f"API call failed: {response.text}")
            return None
        except Exception as e:
            print(f"API call error: {e}", file=sys.stderr)
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
        print(f"Error reading config file: {e}", file=sys.stderr)
        print("Please run 'wtf --config' to reconfigure", file=sys.stderr)
        sys.exit(1)

def validate_config(config: dict) -> Tuple[str, str, str, int, float]:
    api_key = config.get("api_key")
    api_endpoint = config.get("api_endpoint")
    model = config.get("model")
    history_count = config.get("history_count", 5)
    temperature = config.get("temperature", 0)
    # coerce types
    try:
        history_count = int(history_count)
    except Exception:
        history_count = 5
    try:
        temperature = float(temperature)
    except Exception:
        temperature = 0.0
    if not api_key or not api_endpoint or not model:
        print("Incomplete configuration. Please run 'wtf --config' to set up.", file=sys.stderr)
        sys.exit(1)
    return api_key, api_endpoint, model, history_count, temperature

def run_fixer(fixer: CommandFixer) -> None:
    try:
        command = fixer.get_last_command()
        fixed_command = fixer.get_fixed_command(command)
        if not fixed_command:
            print("Unable to fix the command or no fix needed.", file=sys.stderr)
            return
        print(f"\n{fixed_command} [enter/ctrl+c]")
        input()
        result = subprocess.run(
            fixed_command,
            shell=True,
            capture_output=True,
            text=True
        )
        new_output = result.stdout + result.stderr
        print(f"{new_output}")
    except KeyboardInterrupt:
        print("\nOperation cancelled", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
def _handle_suggest_mode():
    config_path = _wtf_find_config_path_for_read()
    cfg, existed, _ = _wtf_load_config(config_path)
    if not existed or not cfg:
        print("Conferror")
        return
    api_key = cfg.get("api_key")
    api_endpoint = cfg.get("api_endpoint")
    model = cfg.get("model")
    history_count = cfg.get("history_count", 5)
    temperature = cfg.get("temperature", 0)
    try:
        history_count = int(history_count)
    except Exception:
        history_count = 5
    try:
        temperature = float(temperature)
    except Exception:
        temperature = 0.0
    if not api_key or not api_endpoint or not model:
        print("Conferror")
        return
    fixer = CommandFixer(api_key, api_endpoint, model, history_count, temperature)
    try:
        last = fixer.get_last_command()
    except Exception:
        print("None")
        return
    cmd = ""
    if isinstance(last, (list, tuple)):
        cmd = last[0] if last else ""
    elif isinstance(last, str):
        cmd = last
    if not cmd:
        print("None")
        return
    fixed = fixer.get_fixed_command(cmd)
    if not fixed:
        print("None")
        return
    print(f"{fixed}")


def main():
    parser = argparse.ArgumentParser(description="Command line fixer using LLM")
    parser.add_argument("--config", action="store_true", help="Configure wtf.json interactively")
    parser.add_argument("--suggest", action="store_true", help="Only suggest the fixed command, do not execute")
    args = parser.parse_args()
    if args.config:
        update_config()
        return
    if args.suggest:
        _handle_suggest_mode()
        return
    config_path = _wtf_find_config_path_for_read()
    config = load_config(config_path)
    api_key, api_endpoint, model, history_count, temperature = validate_config(config)
    fixer = CommandFixer(api_key, api_endpoint, model, history_count, temperature)
    run_fixer(fixer)

if __name__ == "__main__":
    main()

