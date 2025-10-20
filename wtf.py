#!/usr/bin/env python3
import os
import sys
import subprocess
import json
import requests
from typing import Optional, Tuple

class CommandFixer:
    def __init__(self, api_key: str, api_endpoint: str, model: str):
        """初始化命令修正器
        Args:
            api_key: LLM API 密钥
            api_endpoint: LLM API 终端点
            model: LLM模型名称
        """
        self.api_key = api_key
        self.api_endpoint = api_endpoint
        self.model = model

    def get_last_command(self) -> Tuple[str, str]:
        """获取上一条命令和它的输出"""
        try:
            # 读取最后一条命令和它的输出（来自临时文件）
            with open("/tmp/wtf_last_command.txt", "r") as f:
                lines = f.readlines()
                if len(lines) >= 2:
                    last_command = lines[0].strip()
                    output = ''.join(lines[1:]).strip()
                else:
                    return "", "无法获取上一条命令"
            
            print(f"\n检测到的上一条命令: {last_command}")
            print(f"命令输出: {output}")
            
            return last_command, output
            
        except Exception as e:
            print(f"获取命令时出错: {e}", file=sys.stderr)
            return "", str(e)
    
    def get_fixed_command(self, command: str, output: str) -> Optional[str]:
        """调用 LLM API 获取修正后的命令
        
        Args:
            command: 原始命令
            output: 命令执行的输出
            
        Returns:
            修正后的命令，如果无法修正则返回 None
        """
        prompt = f"""请修正以下 shell 命令的错误:
命令: {command}
输出: {output}
只需返回修正后的命令，不要包含任何解释。
如果命令没有错误或无法修正，请返回 'None'。"""

        try:
            payload = {
                "model": self.model,
                "messages": [
                    {"role": "user", "content": prompt}
                ]
            }
            print(f"\n发送到API的数据: {json.dumps(payload, ensure_ascii=False, indent=2)}")
            response = requests.post(
                self.api_endpoint,
                headers={
                    "Content-Type": "application/json",
                    "Authorization": f"Bearer {self.api_key}"
                },
                json=payload
            )
            print(f"\nAPI响应状态码: {response.status_code}")
            print(f"API响应内容: {response.text}")
            if response.status_code == 200:
                response_json = response.json()
                if "choices" in response_json and len(response_json["choices"]) > 0:
                    fixed_command = response_json["choices"][0]["message"]["content"].strip()
                    return None if fixed_command == "None" else fixed_command
                else:
                    print(f"API响应格式不正确: {response_json}")
            else:
                print(f"API调用失败: {response.text}")
            return None
        except Exception as e:
            print(f"调用 API 时出错: {e}", file=sys.stderr)
            return None

    def execute_command(self, command: str) -> None:
        """执行修正后的命令"""
        os.system(command)

def main():
    # 从 config.json 读取配置
    config_path = os.path.join(os.path.dirname(__file__), "config.json")
    if not os.path.exists(config_path):
        print(f"未找到配置文件: {config_path}", file=sys.stderr)
        sys.exit(1)
    with open(config_path, "r") as f:
        config = json.load(f)
    api_key = config.get("api_key")
    api_endpoint = config.get("api_endpoint")
    model = config.get("model")
    if not api_key or not api_endpoint or not model:
        print("config.json 配置不完整，需包含 api_key、api_endpoint、model", file=sys.stderr)
        sys.exit(1)
    fixer = CommandFixer(api_key, api_endpoint, model)
    
    try:
        command, output = fixer.get_last_command()
        max_attempts = 3
        attempt = 0
        while attempt < max_attempts:
            fixed_command = fixer.get_fixed_command(command, output)
            if not fixed_command:
                print("无法修正命令或命令无需修正", file=sys.stderr)
                break
            print(f"\n修正后的命令: {fixed_command}")
            input("\n按回车执行修正后的命令，或按 Ctrl+C 取消...")
            # 执行修正后的命令并获取新输出
            result = subprocess.run(
                fixed_command,
                shell=True,
                capture_output=True,
                text=True
            )
            new_output = result.stdout + result.stderr
            print(f"执行输出: {new_output}")
            # 判断是否还有报错（简单判断：输出包含 'not found' 或 '错误' 或 'unknown' 或 'usage:'）
            error_keywords = ["not found", "错误", "unknown", "usage:"]
            if any(kw in new_output.lower() for kw in error_keywords):
                print("检测到命令仍有错误，尝试再次纠正...")
                # 用修正后的命令和新输出作为下一轮prompt
                command, output = fixed_command, new_output
                attempt += 1
            else:
                print("命令已成功执行，无需再次纠正。")
                break
        else:
            print("多次纠正后仍未成功，请手动检查命令。", file=sys.stderr)
    except KeyboardInterrupt:
        print("\n操作已取消", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"出错: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
