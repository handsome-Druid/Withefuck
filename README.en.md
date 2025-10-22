# Withefuck

[English](./README.en.md) | [中文](./README.md)

Inspired by [nvbn/thefuck](https://github.com/nvbn/thefuck), Withefuck leverages Large Language Models (LLMs) to fix mistyped shell commands automatically. No rule sets to maintain, supports multi-round corrections with recent context.

- Advantage 1: No manual rule maintenance
- Advantage 2: Uses multiple recent commands to infer your real intent

Supports bash and zsh for now.

## Quick Start

```bash
git clone https://github.com/handsome-Druid/Withefuck.git
cd Withefuck
chmod +x ./install.sh
./install.sh
```

## Usage

### Single-turn fix
![Quick Fix](./docs/demo-quick-fix.gif)

### Multi-turn fix

![Iterative Fix](./docs/demo-iterative-fix.gif)
