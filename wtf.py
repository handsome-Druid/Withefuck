#!/usr/bin/env python3
import os
import sys
import subprocess
import json
import requests
import argparse
from typing import Optional, Tuple, Dict

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
    config_path = os.path.join(os.path.dirname(__file__), "wtf.json")

    config, existed, load_err = _wtf_load_config(config_path)
    _wtf_report_load_error(config, load_err)
    _wtf_notify_existing_config(config, existed)

    # Fields to prompt the user for.
    fields = {
        "api_key": "API Key",
        "api_endpoint": "API Endpoint (e.g. https://api.openai.com/v1/chat/completions)",
        "model": "Model name (e.g. gpt-4)",
        "language": "Prompt language (en/zh)"
    }

    for key, desc in fields.items():
        if not _wtf_prompt_field(key, desc, config):
            return

    _wtf_save_and_report(config_path, config)

class CommandFixer:
    def __init__(self, api_key: str, api_endpoint: str, model: str, language: str = "en"):
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
    def get_last_command(self) -> Tuple[str, str]:
        """Get the last command and its output from temp file"""
        try:
            with open("/tmp/wtf_last_command.txt", "r") as f:
                lines = f.readlines()
                if len(lines) >= 2:
                    last_command = lines[0].strip()
                    output = ''.join(lines[1:]).strip()
                    return last_command, output
                return ("", "获取上一个命令失败" if self.language == "zh" else "Failed to get last command")
        except Exception as e:
            print(f"获取命令错误: {e}" if self.language == "zh" else f"Error getting command: {e}", file=sys.stderr)
            return "", str(e)
    def get_fixed_command(self, command: str, output: str) -> Optional[str]:
        """Call LLM API to get the fixed command"""
        prompt = f"Please fix the following shell command error:\nCommand: {command}\nOutput: {output}\nOnly return the corrected command, do not include any explanation.\nIf the command is correct or cannot be fixed, return 'None'."
        try:
            payload = {
                "model": self.model,
                "messages": [
                    {"role": "user", "content": prompt}
                ]
            }
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
                if "choices" in response_json and len(response_json["choices"]) > 0:
                    fixed_command = response_json["choices"][0]["message"]["content"].strip()
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

def main():
    parser = argparse.ArgumentParser(description="Command line fixer using LLM")
    parser.add_argument("--config", action="store_true", help="Configure wtf.json interactively")
    args = parser.parse_args()
    if args.config:
        update_config()
        return
    config_path = os.path.join(os.path.dirname(__file__), "wtf.json")
    if not os.path.exists(config_path):
        print("Config file not found: ./wtf.json. Please run './wtf.py --config' first.", file=sys.stderr)
        sys.exit(1)
    try:
        with open(config_path, "r") as f:
            config = json.load(f)
    except (json.JSONDecodeError, IOError) as e:
        print("读取配置文件时出错: {e}" if config.get("language", "en") == "zh" else f"Error reading config file: {e}", file=sys.stderr)
        print("请运行 './wtf.py --config' 重新配置" if config.get("language", "en") == "zh" else "Please run './wtf.py --config' to reconfigure", file=sys.stderr)
        sys.exit(1)
    api_key = config.get("api_key")
    api_endpoint = config.get("api_endpoint")
    model = config.get("model")
    language = config.get("language", "en")
    if not api_key or not api_endpoint or not model:
        print("配置不完整，请运行 './wtf.py --config' 进行设置" if language == "zh" else "Incomplete configuration. Please run './wtf.py --config' to set up.", file=sys.stderr)
        sys.exit(1)
    fixer = CommandFixer(api_key, api_endpoint, model, language)
    try:
        command, output = fixer.get_last_command()
        fixed_command = fixer.get_fixed_command(command, output)
        if not fixed_command:
            print("无法修正命令或不需要修正。" if language == "zh" else "Unable to fix the command or no fix needed.", file=sys.stderr)
            return
        print(f"\n修正后的命令: {fixed_command}" if language == "zh" else f"\nFixed command: {fixed_command}")
        input("\n按回车键执行修正后的命令，或按Ctrl+C取消..." if language == "zh" else "\nPress Enter to execute the fixed command, or Ctrl+C to cancel...")
        result = subprocess.run(
            fixed_command,
            shell=True,
            capture_output=True,
            text=True
        )
        new_output = result.stdout + result.stderr
        print(f"执行输出: {new_output}" if language == "zh" else f"Execution output: {new_output}")
        try:
            with open("/tmp/wtf_last_command.txt", "w") as f:
                f.write(fixed_command + "\n" + new_output)
        except Exception as e:
            print(f"写入最新命令和输出失败: {e}" if language == "zh" else f"Failed to write latest command and output: {e}", file=sys.stderr)
        print("\n如果结果不符合预期，请再次运行wtf.py进行进一步修正。" if language == "zh" else "\nIf the result is not as expected, run wtf.py again for further correction.")
    except KeyboardInterrupt:
        print("\n操作已取消" if language == "zh" else "\nOperation cancelled", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"出错: {e}" if language == "zh" else f"Error: {e}", file=sys.stderr)
        sys.exit(1)
        
if __name__ == "__main__":
    main()

