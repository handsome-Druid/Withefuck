# Withefuck

[English](./README.en.md) | [中文](./README.md)

受 [nvbn/thefuck](https://github.com/nvbn/thefuck) 启发，Withefuck 使用大语言模型（LLM）自动修正你在终端输入的错误命令，无需手动维护规则库，开箱即用，支持多轮修正。

- 优势 1：无需手动维护配置规则，减少心智负担
- 优势 2：可参考最近多条命令历史，自动推断你的真实意图

目前仅支持bash

## 快速开始

```bash
git clone https://github.com/handsome-Druid/Withefuck.git
cd Withefuck
chmod +x ./install.sh
./install.sh
wtf --config
```

## 在 shell 中使用

仓库中包含一个可被 source 的 shell helper `wtf_func.sh`，它会在当前 shell 内定义 `wtf` 函数。

使用方法：

```bash
# 在当前 shell 会话中启用 wtf 函数
source /path/to/Withefuck/wtf_func.sh

# 之后在任意时刻运行：
wtf
```

或者将 `source /path/to/Withefuck/wtf_func.sh` 添加到你的 `~/.bashrc` 以长期启用。

`wtf` 函数会调用安装在 PATH 下的 `withefuck --suggest`：
- 如果输出 `CONFIG_MISSING`，函数会自动运行 `withefuck --config` 进行交互配置；
- 如果输出 `None`，则不作任何操作；
- 否则会显示 AI 建议的命令，按 Enter 在当前 shell 中执行，Ctrl+C 取消。


## 使用方法

### 第一次使用务必运行

```bash
wtf --config
```

配置 API Key、接口地址、语言（支持中文/英文）以及要包含的历史命令数量。

### 演示

将你的演示 GIF 放到 `docs/` 目录，并使用如下文件名：

- `docs/demo-quick-fix.gif`（单次修正）
- `docs/demo-iterative-fix.gif`（多轮修正）

在 GitHub 上会自动展示如下两段动图：

![Quick Fix](./docs/demo-quick-fix.gif)

![Iterative Fix](./docs/demo-iterative-fix.gif)
