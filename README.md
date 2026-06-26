# FCC 一键安装脚本

基于 [free-claude-code](https://github.com/Alishahryar1/free-claude-code) 项目的自动化安装与配置脚本。

- 🔍 自动检测操作系统（Windows / macOS / Linux / Docker / WSL）
- ✅ 检测必需工具（git、curl）和可选工具（node、npm、python3、uv）
- 📦 一键安装 FCC（uv → Python 3.14 → Free Claude Code）
- 🚀 可选配置 fcc-server 开机自启动
- 🔑 可选配置 AI 模型与 API Key（支持 15 个提供商）

## 快速安装

### Linux / macOS

```bash
curl -fsSL https://raw.githubusercontent.com/CoffenHu/fcc/master/setup-fcc.sh | bash
```

### Windows

**Git Bash**（推荐）：

```bash
curl -fsSL https://raw.githubusercontent.com/CoffenHu/fcc/master/setup-fcc.sh | bash
```

**PowerShell**：

```powershell
irm https://raw.githubusercontent.com/CoffenHu/fcc/master/setup-fcc.ps1 | iex
```

> 安装前会列出检测结果，确认后才开始下载安装。

## 安装过程

脚本运行后分 9 个步骤：

| 步骤 | 说明 | 交互 |
|------|------|------|
| 1 | 检测操作系统和架构 | 自动 |
| 2 | 检测 git/curl/node/npm/python3/uv | 自动 |
| 3 | Windows 下查找 PowerShell | 自动 |
| 4 | 确认是否继续安装 | **Y/n** |
| 5 | 配置 npm + PyPI 阿里镜像源 | 自动 |
| 6 | 调用 FCC 官方脚本安装 | 自动 |
| 7 | 验证安装结果 | 自动 |
| 8 | 配置开机自启动 | **Y/n** |
| 9 | 选择模型提供商 + API Key | **Y/n** |

## 支持的 AI 模型提供商

### 远程提供商（需要 API Key）

| # | 提供商 | 获取 Key 地址 |
|---|--------|--------------|
| 1 | **DeepSeek** | [platform.deepseek.com](https://platform.deepseek.com/api_keys) |
| 2 | NVIDIA NIM | [build.nvidia.com](https://build.nvidia.com/settings/api-keys) |
| 3 | OpenRouter | [openrouter.ai](https://openrouter.ai/keys) |
| 4 | Google Gemini | [aistudio.google.com](https://aistudio.google.com/apikey) |
| 5 | Groq | [console.groq.com](https://console.groq.com/keys) |
| 6 | Cerebras | [cloud.cerebras.ai](https://cloud.cerebras.ai/apikeys) |
| 7 | Kimi | [platform.moonshot.ai](https://platform.moonshot.ai/console/api-keys) |
| 8 | Mistral | [console.mistral.ai](https://console.mistral.ai/api-keys) |
| 9 | Fireworks | [fireworks.ai](https://fireworks.ai/account/api-keys) |
| 10 | Z.ai | [z.ai](https://z.ai) |
| 11 | Wafer | [pass.wafer.ai](https://pass.wafer.ai) |
| 12 | OpenCode | [opencode.ai](https://opencode.ai) |

### 本地提供商（无需 API Key）

| # | 提供商 | 默认地址 |
|---|--------|---------|
| 13 | Ollama | `http://localhost:11434` |
| 14 | LM Studio | `http://localhost:1234/v1` |
| 15 | llama.cpp | `http://localhost:8080/v1` |

## 开机自启动

| 系统 | 实现方式 |
|------|----------|
| Windows | 启动文件夹 `.vbs` 脚本（无窗口静默启动） |
| macOS | `LaunchAgent` plist，登录后自动加载 |
| Linux | `systemd` 用户服务（`systemctl --user enable`） |

## 前置要求

| 工具 | 必需 | 说明 |
|------|------|------|
| git | ✅ | 克隆和版本管理 |
| curl | ✅ | 下载安装脚本 |
| node / npm | ❌ | FCC 内部用于安装 claude/codex 客户端 |
| python3 | ❌ | FCC 运行依赖（安装脚本会自动安装 3.14） |

## 使用 FCC

```bash
# 1. 启动代理
fcc-server

# 2. 打开管理界面
# http://127.0.0.1:8082/admin

# 3. 在管理界面配置 API Key 和模型（或通过本脚本步骤 8 配置）

# 4. 运行 Claude Code
fcc-claude

# 5. 或运行 Codex
fcc-codex
```

## 配置文件

模型配置写入 `~/.fcc/.env`，可随时编辑或通过管理界面修改：

```bash
# 查看/编辑配置
cat ~/.fcc/.env
vim ~/.fcc/.env

# 重启 fcc-server 使配置生效
pkill fcc-server && fcc-server
```

## 卸载

```bash
# 停止运行中的进程
pkill fcc-server

# macOS / Linux
curl -fsSL https://raw.githubusercontent.com/Alishahryar1/free-claude-code/main/scripts/uninstall.sh | sh

# Windows PowerShell
irm https://raw.githubusercontent.com/Alishahryar1/free-claude-code/main/scripts/uninstall.ps1 | iex
```

## 目录结构

```
fcc/
├── setup-fcc.sh          # Linux/macOS/Windows(Git Bash) 安装脚本
├── setup-fcc.ps1         # Windows PowerShell 安装脚本
└── README.md             # 本文件
```

## 相关项目

- [free-claude-code](https://github.com/Alishahryar1/free-claude-code) — FCC 核心项目
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) — Anthropic 官方 CLI

## License

MIT
