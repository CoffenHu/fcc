#!/usr/bin/env bash
# ==============================================================================
# Free Claude Code (FCC) 一键安装/检测脚本
# 支持 Linux (含 WSL/Docker) / macOS
# Windows 用户请使用: irm ...setup-fcc.ps1 | iex
# ==============================================================================
set -euo pipefail

# ---------- 颜色定义 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

ok()    { printf "${GREEN}[✓]${NC} %s\n" "$*"; }
fail()  { printf "${RED}[✗]${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}[!]${NC} %s\n" "$*"; }
info()  { printf "${CYAN}[>]${NC} %s\n" "$*"; }
header(){ printf "\n${BOLD}%s${NC}\n" "$*"; }

# ---------- 系统检测 ----------
detect_os() {
    local kernel
    kernel="$(uname -s)"

    IS_DOCKER=false
    if [ -f /.dockerenv ] || grep -q docker /proc/1/cgroup 2>/dev/null; then
        IS_DOCKER=true
    fi

    case "$kernel" in
        Linux*)  OS="linux";;
        Darwin*) OS="macos";;
        MINGW*|MSYS*|CYGWIN*)
            echo "Windows 用户请使用 PowerShell 脚本: irm https://raw.githubusercontent.com/CoffenHu/fcc/master/setup-fcc.ps1 | iex"
            exit 1
            ;;
        *)       OS="unknown";;
    esac

    header "=== 系统检测 ==="
    if [ "$IS_DOCKER" = true ]; then
        echo "操作系统: Linux (Docker)"
    else
        echo "操作系统: $OS"
    fi
    echo "架构:     $(uname -m)"
    echo "Shell:    ${SHELL:-unknown}"
}

# ---------- 命令检测 ----------
has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

check_cmd() {
    local cmd="$1"
    local name="${2:-$cmd}"
    local required="${3:-true}"
    local version

    if has_cmd "$cmd"; then
        version=$( ("$cmd" --version 2>&1 || "$cmd" -v 2>&1 || echo "已安装") | head -1 | tr -d '\r\n' )
        ok "$name — $version"
        return 0
    else
        if [ "$required" = "true" ]; then
            fail "$name 未安装（必需）"
            return 1
        else
            warn "$name 未安装（可选）"
            return 0
        fi
    fi
}

# ---------- 安装建议 ----------
install_hint() {
    local tool="$1"
    echo ""
    echo "  ┌─ 如何安装 $tool ─────────────────────────"
    case "$tool" in
        git)
            if [ "$OS" = "macos" ]; then
                echo "  │  brew install git"
            else
                echo "  │  sudo apt install git  (Debian/Ubuntu)"
                echo "  │  sudo dnf install git  (Fedora)"
                echo "  │  sudo pacman -S git    (Arch)"
            fi ;;
        node|npm)
            if [ "$OS" = "macos" ]; then
                echo "  │  brew install node"
            else
                echo "  │  curl -fsSL https://deb.nodesource.com/setup_22.x | sudo bash -"
                echo "  │  sudo apt install -y nodejs"
            fi ;;
        curl)
            if [ "$OS" = "macos" ]; then
                echo "  │  系统自带 curl"
            else
                echo "  │  sudo apt install curl  (Debian/Ubuntu)"
            fi ;;
    esac
    echo "  └───────────────────────────────────────────"
}

# ---------- FCC 配置文件路径 ----------
FCC_ENV_FILE="$HOME/.fcc/.env"

# ---------- 开机自启动配置 ----------
configure_autostart() {
    echo ""

    if [ "$IS_DOCKER" = true ]; then
        warn "当前运行在 Docker 容器中，跳过自启动配置。"
        return
    fi

    if [ "$OS" = "macos" ]; then
        # macOS: 创建 LaunchAgent plist
        PLIST_DIR="$HOME/Library/LaunchAgents"
        mkdir -p "$PLIST_DIR"
        PLIST_FILE="$PLIST_DIR/com.fcc.server.plist"

        FCC_SERVER_PATH=$(command -v fcc-server 2>/dev/null || echo "$HOME/.local/bin/fcc-server")

        cat > "$PLIST_FILE" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.fcc.server</string>
    <key>ProgramArguments</key>
    <array>
        <string>$FCC_SERVER_PATH</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>StandardOutPath</key>
    <string>$HOME/.fcc/launchd.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/.fcc/launchd.log</string>
</dict>
</plist>
PLIST
        launchctl load "$PLIST_FILE" 2>/dev/null || true
        ok "已创建 macOS 启动项: $PLIST_FILE"

    elif [ "$OS" = "linux" ]; then
        # Linux: 创建 systemd user service
        SYSTEMD_DIR="$HOME/.config/systemd/user"
        mkdir -p "$SYSTEMD_DIR"
        SERVICE_FILE="$SYSTEMD_DIR/fcc-server.service"

        FCC_SERVER_PATH=$(command -v fcc-server 2>/dev/null || echo "$HOME/.local/bin/fcc-server")

        cat > "$SERVICE_FILE" << SERVICE
[Unit]
Description=Free Claude Code Proxy Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$FCC_SERVER_PATH
Restart=on-failure
RestartSec=5
Environment="PATH=$PATH"

[Install]
WantedBy=default.target
SERVICE

        systemctl --user daemon-reload 2>/dev/null || true
        systemctl --user enable fcc-server.service 2>/dev/null || true
        systemctl --user start fcc-server.service 2>/dev/null || true
        ok "已创建 Linux systemd 用户服务: $SERVICE_FILE"
        echo "  管理命令:"
        echo "    systemctl --user status fcc-server"
        echo "    systemctl --user stop fcc-server"
        echo "    systemctl --user disable fcc-server"
    fi
}

# ---------- 模型与 API Key 配置 ----------
configure_model() {
    echo ""

    # 确保配置文件目录存在
    mkdir -p "$HOME/.fcc"

    # 列出可用的提供商
    echo "  ┌─────────────────────────────────────────────┐"
    echo "  │         FCC 支持的 AI 模型提供商            │"
    echo "  ├─────────────────────────────────────────────┤"
    echo "  │  远程提供商（需要 API Key）                  │"
    echo "  │                                               │"
    echo "  │  1. DeepSeek         (platform.deepseek.com) │"
    echo "  │  2. NVIDIA NIM       (build.nvidia.com)       │"
    echo "  │  3. OpenRouter       (openrouter.ai)          │"
    echo "  │  4. Google Gemini    (aistudio.google.com)    │"
    echo "  │  5. Groq             (console.groq.com)       │"
    echo "  │  6. Cerebras         (cloud.cerebras.ai)      │"
    echo "  │  7. Kimi             (platform.moonshot.ai)   │"
    echo "  │  8. Mistral          (console.mistral.ai)     │"
    echo "  │  9. Fireworks        (fireworks.ai)           │"
    echo "  │ 10. Z.ai             (z.ai)                   │"
    echo "  │ 11. Wafer            (pass.wafer.ai)          │"
    echo "  │ 12. OpenCode         (opencode.ai)            │"
    echo "  │                                               │"
    echo "  │  本地提供商（无需 API Key）                    │"
    echo "  │                                               │"
    echo "  │ 13. Ollama           (localhost:11434)         │"
    echo "  │ 14. LM Studio        (localhost:1234)          │"
    echo "  │ 15. llama.cpp        (localhost:8080)          │"
    echo "  └─────────────────────────────────────────────┘"
    echo ""

    read -r -p "请选择提供商 [1-15] (默认: 1 DeepSeek): " PROVIDER_CHOICE </dev/tty
    PROVIDER_CHOICE="${PROVIDER_CHOICE:-1}"

    case "$PROVIDER_CHOICE" in
        1)  PROVIDER="deepseek"
            PROVIDER_NAME="DeepSeek"
            ENV_KEY="DEEPSEEK_API_KEY"
            DEFAULT_MODEL="deepseek/deepseek-chat"
            KEY_URL="https://platform.deepseek.com/api_keys"
            ;;
        2)  PROVIDER="nvidia_nim"
            PROVIDER_NAME="NVIDIA NIM"
            ENV_KEY="NVIDIA_NIM_API_KEY"
            DEFAULT_MODEL="nvidia_nim/nvidia/nemotron-3-super-120b-a12b"
            KEY_URL="https://build.nvidia.com/settings/api-keys"
            ;;
        3)  PROVIDER="open_router"
            PROVIDER_NAME="OpenRouter"
            ENV_KEY="OPENROUTER_API_KEY"
            DEFAULT_MODEL="open_router/openrouter/free"
            KEY_URL="https://openrouter.ai/keys"
            ;;
        4)  PROVIDER="gemini"
            PROVIDER_NAME="Google Gemini"
            ENV_KEY="GEMINI_API_KEY"
            DEFAULT_MODEL="gemini/models/gemini-3.1-flash-lite"
            KEY_URL="https://aistudio.google.com/apikey"
            ;;
        5)  PROVIDER="groq"
            PROVIDER_NAME="Groq"
            ENV_KEY="GROQ_API_KEY"
            DEFAULT_MODEL="groq/llama-3.3-70b-versatile"
            KEY_URL="https://console.groq.com/keys"
            ;;
        6)  PROVIDER="cerebras"
            PROVIDER_NAME="Cerebras"
            ENV_KEY="CEREBRAS_API_KEY"
            DEFAULT_MODEL="cerebras/llama3.3-70b"
            KEY_URL="https://cloud.cerebras.ai/apikeys"
            ;;
        7)  PROVIDER="kimi"
            PROVIDER_NAME="Kimi"
            ENV_KEY="KIMI_API_KEY"
            DEFAULT_MODEL="kimi/kimi-moonshot-v1"
            KEY_URL="https://platform.moonshot.ai/console/api-keys"
            ;;
        8)  PROVIDER="mistral"
            PROVIDER_NAME="Mistral"
            ENV_KEY="MISTRAL_API_KEY"
            DEFAULT_MODEL="mistral/mistral-large-latest"
            KEY_URL="https://console.mistral.ai/api-keys"
            ;;
        9)  PROVIDER="fireworks"
            PROVIDER_NAME="Fireworks"
            ENV_KEY="FIREWORKS_API_KEY"
            DEFAULT_MODEL="fireworks/accounts/fireworks/models/llama-v3p3-70b-instruct"
            KEY_URL="https://fireworks.ai/account/api-keys"
            ;;
        10) PROVIDER="zai"
            PROVIDER_NAME="Z.ai"
            ENV_KEY="ZAI_API_KEY"
            DEFAULT_MODEL="zai/glm-4"
            KEY_URL="https://z.ai"
            ;;
        11) PROVIDER="wafer"
            PROVIDER_NAME="Wafer"
            ENV_KEY="WAFER_API_KEY"
            DEFAULT_MODEL="wafer/wafer-1"
            KEY_URL="https://pass.wafer.ai"
            ;;
        12) PROVIDER="opencode"
            PROVIDER_NAME="OpenCode"
            ENV_KEY="OPENCODE_API_KEY"
            DEFAULT_MODEL="opencode/zen"
            KEY_URL="https://opencode.ai"
            ;;
        13|14|15)
            # 本地提供商
            case "$PROVIDER_CHOICE" in
                13) PROVIDER="ollama"
                    PROVIDER_NAME="Ollama"
                    LOCAL_URL="$HOME/.fcc"
                    DEFAULT_MODEL="ollama/llama3.2"
                    info "Ollama 无需 API Key，默认地址: http://localhost:11434"
                    info "如需修改地址，可使用 fcc-server 管理界面。"
                    ;;
                14) PROVIDER="lmstudio"
                    PROVIDER_NAME="LM Studio"
                    DEFAULT_MODEL="lmstudio/default"
                    info "LM Studio 无需 API Key，默认地址: http://localhost:1234/v1"
                    ;;
                15) PROVIDER="llamacpp"
                    PROVIDER_NAME="llama.cpp"
                    DEFAULT_MODEL="llamacpp/default"
                    info "llama.cpp 无需 API Key，默认地址: http://localhost:8080/v1"
                    ;;
            esac
            write_fcc_config "$PROVIDER" "$PROVIDER_NAME" "" "$DEFAULT_MODEL"
            return
            ;;
        *)
            warn "无效选择，跳过模型配置。"
            return
            ;;
    esac

    echo ""
    info "已选择: $PROVIDER_NAME"
    echo "  获取 Key: $KEY_URL"
    echo ""

    read -r -p "请输入 ${PROVIDER_NAME} API Key: " API_KEY </dev/tty

    if [ -z "$API_KEY" ]; then
        warn "API Key 为空，跳过配置。你之后可以在管理界面配置。"
        return
    fi

    write_fcc_config "$PROVIDER" "$PROVIDER_NAME" "$API_KEY" "$DEFAULT_MODEL"
}

# ---------- 写入 FCC 配置文件 ----------
write_fcc_config() {
    local provider="$1"
    local provider_name="$2"
    local api_key="$3"
    local default_model="$4"

    # 备份已有配置
    if [ -f "$FCC_ENV_FILE" ]; then
        cp "$FCC_ENV_FILE" "${FCC_ENV_FILE}.backup.$(date +%Y%m%d%H%M%S)"
    fi

    # 写入配置
    cat > "$FCC_ENV_FILE" << EOF
# FCC 配置文件 (由 setup-fcc.sh 自动生成)
# 修改后重启 fcc-server 生效

# ${provider_name} 配置
${ENV_KEY:-}=${api_key}

# 模型配置
MODEL=${default_model}

# 服务端口 (默认 8082)
PORT=8082

# 服务认证 (留空使用默认值 freecc)
ANTHROPIC_AUTH_TOKEN=freecc

# 自动打开浏览器
FCC_OPEN_BROWSER=true
EOF

    ok "${provider_name} 配置已写入: $FCC_ENV_FILE"
    info "默认模型: $default_model"
    info "你可以随时编辑此文件或通过管理界面修改配置。"

    # 如果 fcc-server 正在运行，提示重启
    if pgrep -f "fcc-server" >/dev/null 2>&1; then
        warn "检测到 fcc-server 正在运行，重启以应用新配置:"
        echo "  pkill fcc-server && fcc-server"
    fi
}

# ---------- 主流程 ----------
main() {
    echo ""
    echo "╔═══════════════════════════════════════════════╗"
    echo "║   Free Claude Code (FCC) 自动化安装脚本        ║"
    echo "╚═══════════════════════════════════════════════╝"

    # ---- 步骤 1: 检测系统 ----
    detect_os

    if [ "$OS" = "unknown" ]; then
        fail "无法识别当前操作系统"
        exit 1
    fi

    # ---- 步骤 2: 检测必需工具 ----
    header "=== 检测常用工具 ==="
    MISSING=0

    check_cmd git  "Git"  "true" || { MISSING=1; install_hint git; }
    check_cmd curl "curl" "true" || { MISSING=1; install_hint curl; }

    # 可选工具（安装脚本内部用它来装 claude/codex 客户端）
    check_cmd node "Node.js" "false" || true
    check_cmd npm  "npm"  "false" || true
    check_cmd python3 "Python 3" "false" || true
    check_cmd uv   "uv"   "false" || true

    if [ "$MISSING" -eq 1 ]; then
        echo ""
        warn "请先安装缺失的必需工具，然后重新运行此脚本。"
        exit 1
    fi

    echo ""

    # ---- 步骤 3: 询问用户 ----
    header "=== 开始安装 FCC ==="
    info "即将安装 Free Claude Code（包含 uv + Python 3.14）"
    info "free-claude-code项目地址: https://github.com/Alishahryar1/free-claude-code"
    read -r -p "是否继续？[Y/n] " REPLY </dev/tty
    REPLY="${REPLY:-y}"
    if [ "$REPLY" != "y" ] && [ "$REPLY" != "Y" ]; then
        info "已取消安装。"
        exit 0
    fi

    # ---- 步骤 4: 配置镜像加速 ----
    header "=== 配置镜像加速 ==="
    info "配置 npm 和 PyPI 阿里镜像源，加速国内下载..."

    if has_cmd npm; then
        npm config set registry https://registry.npmmirror.com 2>/dev/null || true
        ok "npm 镜像: registry.npmmirror.com"
    fi

    export UV_INDEX_URL="https://mirrors.aliyun.com/pypi/simple/"
    ok "PyPI 镜像: mirrors.aliyun.com"

    # ---- 步骤 5: 执行安装 ----
    echo ""

    header "=== 使用 Shell 安装 ==="
    info "执行安装脚本（这将需要几分钟）..."
    info "安装内容: uv → Python 3.14 → Free Claude Code"

    curl -fsSL "https://github.com/Alishahryar1/free-claude-code/blob/main/scripts/install.sh?raw=1" | sh

    # ---- 步骤 6: 验证安装 ----
    echo ""
    header "=== 验证安装 ==="

    # 刷新 PATH（uv 安装后可能新增了路径）
    if [ -d "$HOME/.local/bin" ]; then
        export PATH="$HOME/.local/bin:$PATH"
    fi
    if [ -d "$HOME/.cargo/bin" ]; then
        export PATH="$HOME/.cargo/bin:$PATH"
    fi

    if has_cmd fcc-server; then
        ok "fcc-server 已就绪"
    else
        warn "fcc-server 未在当前 PATH 中找到。"
        echo "  提示: 运行 'source ~/.bashrc' 或重新打开终端。"
        echo "  如果仍找不到，检查 ~/.local/bin 是否在 PATH 中。"
    fi

    # ---- 步骤 7: 开机自启动 ----
    header "=== 开机自启动配置 ==="
    read -r -p "是否配置 fcc-server 开机自启动？[Y/n] " REPLY_AUTOSTART </dev/tty
    REPLY_AUTOSTART="${REPLY_AUTOSTART:-y}"
    if [ "$REPLY_AUTOSTART" = "y" ] || [ "$REPLY_AUTOSTART" = "Y" ]; then
        configure_autostart
    else
        info "跳过开机自启动配置。"
    fi

    # ---- 步骤 8: 模型配置 ----
    echo ""
    header "=== 模型配置 ==="
    read -r -p "是否现在配置模型和 API Key？[Y/n] " REPLY_MODEL </dev/tty
    REPLY_MODEL="${REPLY_MODEL:-y}"
    if [ "$REPLY_MODEL" = "y" ] || [ "$REPLY_MODEL" = "Y" ]; then
        configure_model
    else
        info "跳过模型配置（之后可在 http://127.0.0.1:8082/admin 配置）。"
    fi

    # ---- 完成 ----
    echo ""
    echo "╔═══════════════════════════════════════════════╗"
    echo "║           安装完成！                         ║"
    echo "╠═══════════════════════════════════════════════╣"
    echo "║                                               ║"
    echo "║  启动代理:   fcc-server                       ║"
    echo "║  运行 Claude: fcc-claude                      ║"
    echo "║  运行 Codex:  fcc-codex                        ║"
    echo "║                                               ║"
    echo "║  管理界面:   http://127.0.0.1:8082/admin       ║"
    echo "║                                               ║"
    echo "║  工作流程:                                     ║"
    echo "║  1. fcc-server    # 启动代理                  ║"
    echo "║  2. 打开 http://127.0.0.1:8082/admin          ║"
    echo "║  3. 配置 API Key 和模型                        ║"
    echo "║  4. fcc-claude    # 开始使用                  ║"
    echo "║                                               ║"
    echo "╚═══════════════════════════════════════════════╝"
    echo ""
}

main
