# Withefuck

[English](./README.en.md) | [中文](./README.md)

Inspired by [nvbn/thefuck](https://github.com/nvbn/thefuck), Withefuck leverages Large Language Models (LLMs) to fix mistyped shell commands automatically. No rule sets to maintain, supports multi-round corrections with recent context.

- Advantage 1: No manual rule maintenance
- Advantage 2: Uses multiple recent commands to infer your real intent

Only supports bash for now.

## Quick Start

```bash
git clone https://github.com/handsome-Druid/Withefuck.git
cd Withefuck
chmod +x ./install.sh
./install.sh
wtf --config
```

## Usage

### First-time setup

```bash
wtf --config
```

Configure your API key, API endpoint, language (Chinese/English), and how many recent commands to include.

### Demo

Place your demo GIFs under the `docs/` directory with these filenames:

- `docs/demo-quick-fix.gif` (single-shot fix)
- `docs/demo-iterative-fix.gif` (iterative fix)

They will be rendered automatically on GitHub:

![Quick Fix](./docs/demo-quick-fix.gif)

![Iterative Fix](./docs/demo-iterative-fix.gif)
