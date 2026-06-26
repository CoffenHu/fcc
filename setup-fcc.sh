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
                echo "  │  Debian/Ubuntu: sudo apt install git"
                echo "  │  CentOS/RHEL:   sudo yum install git"
                echo "  │  Fedora:        sudo dnf install git"
                echo "  │  Arch:          sudo pacman -S git"
            fi ;;
        node|npm)
            if [ "$OS" = "macos" ]; then
                echo "  │  brew install node"
            else
                echo "  │  Debian/Ubuntu:"
                echo "  │    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo bash -"
                echo "  │    sudo apt install -y nodejs"
                echo "  │  CentOS/RHEL:"
                echo "  │    curl -fsSL https://rpm.nodesource.com/setup_22.x | sudo bash -"
                echo "  │    sudo yum install -y nodejs"
                echo "  │  Fedora: sudo dnf install nodejs"
            fi ;;
        curl)
            if [ "$OS" = "macos" ]; then
                echo "  │  系统自带 curl"
            else
                echo "  │  Debian/Ubuntu: sudo apt install curl"
                echo "  │  CentOS/RHEL:   sudo yum install curl"
            fi ;;
    esac
    echo "  └───────────────────────────────────────────"
}

# ---------- FCC 配置文件路径 ----------
FCC_ENV_FILE="$HOME/.fcc/.env"

# ---------- PATH 自动修复 ----------
fix_shell_path() {
    local bins=("$HOME/.local/bin" "$HOME/.cargo/bin")
    local profiles=("$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" "$HOME/.zshrc")
    local found=false

    # 检查是否有可用的 profile 文件
    for profile in "${profiles[@]}"; do
        [ -f "$profile" ] && found=true && break
    done

    # 如果都不存在，创建 ~/.bashrc（Docker 容器常见情况）
    if [ "$found" = false ]; then
        touch "$HOME/.bashrc"
    fi

    for bin_dir in "${bins[@]}"; do
        # 当前会话立即生效
        [ -d "$bin_dir" ] && export PATH="$bin_dir:$PATH"

        for profile in "${profiles[@]}"; do
            if [ -f "$profile" ]; then
                if ! grep -q "$bin_dir" "$profile" 2>/dev/null; then
                    echo "export PATH=\"$bin_dir:\$PATH\"" >> "$profile"
                fi
            fi
        done
    done
}

# ---------- 开机自启动配置 ----------
configure_autostart() {
    echo ""

    FCC_SERVER_PATH=$(command -v fcc-server 2>/dev/null || echo "$HOME/.local/bin/fcc-server")

    if [ "$IS_DOCKER" = true ]; then
        # Docker 容器: 通过 .bashrc 实现自动启动
        if ! grep -q "fcc-server" "$HOME/.bashrc" 2>/dev/null; then
            cat >> "$HOME/.bashrc" << 'BASHRC'
# FCC auto-start (added by setup-fcc.sh)
if command -v fcc-server >/dev/null 2>&1; then
    if ! pgrep -f "fcc-server" >/dev/null 2>&1; then
        echo "Starting fcc-server..."
        fcc-server &
        sleep 1
    fi
fi
BASHRC
        fi
        ok "已配置 Docker 自启动 (写入 ~/.bashrc)"
        # 立即启动
        if ! pgrep -f "fcc-server" >/dev/null 2>&1; then
            nohup "$FCC_SERVER_PATH" > "$HOME/.fcc/fcc.log" 2>&1 &
            sleep 1
            ok "fcc-server 已在后台启动"
        fi
        return
    fi

    if [ "$OS" = "macos" ]; then
        # macOS: 创建 LaunchAgent plist
        PLIST_DIR="$HOME/Library/LaunchAgents"
        mkdir -p "$PLIST_DIR"
        PLIST_FILE="$PLIST_DIR/com.fcc.server.plist"

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
        # 立即启动
        nohup "$FCC_SERVER_PATH" > "$HOME/.fcc/fcc.log" 2>&1 &
        sleep 1
        ok "fcc-server 已在后台启动"

    elif [ "$OS" = "linux" ]; then
        # Linux: 优先 systemd，不可用时回退到 .bashrc
        if command -v systemctl >/dev/null 2>&1 && systemctl --user >/dev/null 2>&1; then
            SYSTEMD_DIR="$HOME/.config/systemd/user"
            mkdir -p "$SYSTEMD_DIR"
            SERVICE_FILE="$SYSTEMD_DIR/fcc-server.service"

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
            ok "已创建 systemd 用户服务: $SERVICE_FILE"
            echo "  管理命令:"
            echo "    systemctl --user status fcc-server"
            echo "    systemctl --user stop fcc-server"
        else
            # systemd 不可用，回退到 .bashrc
            if ! grep -q "fcc-server" "$HOME/.bashrc" 2>/dev/null; then
                cat >> "$HOME/.bashrc" << 'BASHRC'
# FCC auto-start (added by setup-fcc.sh)
if command -v fcc-server >/dev/null 2>&1; then
    if ! pgrep -f "fcc-server" >/dev/null 2>&1; then
        echo "Starting fcc-server..."
        fcc-server &
        sleep 1
    fi
fi
BASHRC
            fi
            ok "已配置自启动 (写入 ~/.bashrc)"
            # 立即启动
            nohup "$FCC_SERVER_PATH" > "$HOME/.fcc/fcc.log" 2>&1 &
            sleep 1
            ok "fcc-server 已在后台启动"
        fi
    fi
}

# ---------- 启动 fcc-server（开箱即用） ----------
start_fcc_server_now() {
    FCC_SERVER_PATH=$(command -v fcc-server 2>/dev/null || echo "$HOME/.local/bin/fcc-server")

    if [ -x "$FCC_SERVER_PATH" ] || command -v fcc-server >/dev/null 2>&1; then
        # 检查是否已在运行
        if pgrep -f "fcc-server" >/dev/null 2>&1; then
            return
        fi
        mkdir -p "$HOME/.fcc"
        nohup "$FCC_SERVER_PATH" > "$HOME/.fcc/fcc.log" 2>&1 &
        sleep 1
        if pgrep -f "fcc-server" >/dev/null 2>&1; then
            ok "fcc-server 已启动，现在可直接使用 fcc-claude / fcc-codex"
        fi
    fi
}

# ---------- 模型与 API Key 配置 ----------
configure_model() {
    echo ""

    mkdir -p "$HOME/.fcc"

    echo "  ┌──────────────────────────────────────────────────┐"
    echo "  │            FCC 支持的 AI 模型提供商               │"
    echo "  ├──────────────────────────────────────────────────┤"
    echo "  │  远程提供商（需要 API Key）                        │"
    echo "  │                                                  │"
    echo "  │   1. DeepSeek         platform.deepseek.com       │"
    echo "  │   2. NVIDIA NIM       build.nvidia.com             │"
    echo "  │   3. OpenRouter       openrouter.ai                │"
    echo "  │   4. Google Gemini    aistudio.google.com           │"
    echo "  │   5. Groq             console.groq.com              │"
    echo "  │   6. Cerebras         cloud.cerebras.ai             │"
    echo "  │   7. Kimi             platform.moonshot.ai          │"
    echo "  │   8. Mistral          console.mistral.ai            │"
    echo "  │   9. Fireworks        fireworks.ai                  │"
    echo "  │  10. Z.ai             z.ai                          │"
    echo "  │  11. Wafer            pass.wafer.ai                 │"
    echo "  │  12. OpenCode         opencode.ai                   │"
    echo "  │                                                  │"
    echo "  │  本地提供商（无需 API Key）                          │"
    echo "  │                                                  │"
    echo "  │  13. Ollama           localhost:11434               │"
    echo "  │  14. LM Studio        localhost:1234/v1             │"
    echo "  │  15. llama.cpp        localhost:8080/v1             │"
    echo "  └──────────────────────────────────────────────────┘"
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
    echo "╔══════════════════════════════════════════════════╗"
    echo "║                                                  ║"
    echo "║     Free Claude Code (FCC) 一键安装脚本           ║"
    echo "║                                                  ║"
    echo "╚══════════════════════════════════════════════════╝"

    # ---- 步骤 1: 检测系统 ----
    detect_os

    if [ "$OS" = "unknown" ]; then
        fail "无法识别当前操作系统"
        exit 1
    fi

    # 预加载常用 bin 目录，避免已安装的 uv 等工具检测不到
    [ -d "$HOME/.local/bin" ] && export PATH="$HOME/.local/bin:$PATH"
    [ -d "$HOME/.cargo/bin" ] && export PATH="$HOME/.cargo/bin:$PATH"

    # ---- 步骤 2: 检测必需工具 ----
    header "=== 检测常用工具 ==="
    MISSING=0

    check_cmd git  "Git"  "true" || { MISSING=1; install_hint git; }
    check_cmd curl "curl" "true" || { MISSING=1; install_hint curl; }

    # npm/node 为必需（上游安装脚本依赖 npm 安装 claude/codex 客户端）
    check_cmd node "Node.js" "true" || { MISSING=1; install_hint node; }
    check_cmd npm  "npm"  "true" || { MISSING=1; install_hint npm; }
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
    header "=== 使用 Shell 安装 ==="
    info "执行安装脚本（这将需要几分钟）..."
    info "安装内容: uv → Python 3.14 → Free Claude Code"

    curl -fsSL "https://github.com/Alishahryar1/free-claude-code/blob/main/scripts/install.sh?raw=1" | sh

    # ---- 步骤 6: 修复 PATH + 验证 ----
    header "=== 修复 PATH + 验证安装 ==="

    # 将 ~/.local/bin 写入 shell 配置文件，避免每次重启终端丢失
    fix_shell_path

    if has_cmd fcc-server; then
        ok "fcc-server 已就绪"
    else
        # 最后一次尝试
        if [ -x "$HOME/.local/bin/fcc-server" ]; then
            export PATH="$HOME/.local/bin:$PATH"
            ok "fcc-server 已找到并加入 PATH"
        else
            warn "fcc-server 未找到，请检查安装是否成功。"
        fi
    fi

    # 自动后台启动 fcc-server，让用户安装后就能直接用
    start_fcc_server_now

    # ---- 步骤 7: 开机自启动 ----
    header "=== 开机自启动配置 ==="
    read -r -p "是否配置 fcc-server 开机自启动？[Y/n] " REPLY_AUTOSTART </dev/tty
    REPLY_AUTOSTART="${REPLY_AUTOSTART:-y}"
    if [ "$REPLY_AUTOSTART" = "y" ] || [ "$REPLY_AUTOSTART" = "Y" ]; then
        configure_autostart
    else
        info "跳过开机自启动配置。"
        echo "  手动启动: fcc-server &"
    fi

    # ---- 步骤 8: 模型配置 ----
    header "=== 模型配置 ==="
    read -r -p "是否现在配置模型和 API Key？[Y/n] " REPLY_MODEL </dev/tty
    REPLY_MODEL="${REPLY_MODEL:-y}"
    if [ "$REPLY_MODEL" = "y" ] || [ "$REPLY_MODEL" = "Y" ]; then
        configure_model
    else
        info "跳过模型配置（之后可在 http://127.0.0.1:8082/admin 配置）。"
    fi

    # ---- 步骤 9: Claude Code 自动升级配置 ----
    header "=== Claude Code 自动升级配置 ==="
    echo "  Claude Code 默认会自动更新到最新版。"
    echo "  禁用后可锁定版本，避免兼容性问题。"
    echo ""
    read -r -p "是否禁用 Claude Code 自动升级？[Y/n] " DISABLE_UPGRADE </dev/tty
    DISABLE_UPGRADE="${DISABLE_UPGRADE:-y}"

    if [ "$DISABLE_UPGRADE" = "y" ] || [ "$DISABLE_UPGRADE" = "Y" ]; then
        # 写入环境变量到 shell 配置文件
        for profile in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" "$HOME/.zshrc"; do
            if [ -f "$profile" ] && ! grep -q "CLAUDE_CODE_DISABLE_AUTO_UPDATE" "$profile" 2>/dev/null; then
                echo "export CLAUDE_CODE_DISABLE_AUTO_UPDATE=true" >> "$profile"
            fi
        done
        export CLAUDE_CODE_DISABLE_AUTO_UPDATE=true
        ok "已禁用 Claude Code 自动升级"

        # ---- 步骤 10: 安装稳定版本 ----
        header "=== 安装 Claude Code 稳定版本 ==="
        STABLE_VERSION="2.1.150"
        info "最新版可能存在兼容性问题，稳定版 $STABLE_VERSION 经过充分测试。"
        echo ""
        read -r -p "是否安装 Claude Code $STABLE_VERSION 稳定版本？[Y/n] " INSTALL_STABLE </dev/tty
        INSTALL_STABLE="${INSTALL_STABLE:-y}"

        if [ "$INSTALL_STABLE" = "y" ] || [ "$INSTALL_STABLE" = "Y" ]; then
            if has_cmd npm; then
                info "正在安装 Claude Code @ $STABLE_VERSION ..."
                npm install -g "@anthropic-ai/claude-code@$STABLE_VERSION" 2>/dev/null && \
                    ok "Claude Code $STABLE_VERSION 已安装" || \
                    warn "安装失败，请手动执行: npm install -g @anthropic-ai/claude-code@$STABLE_VERSION"
            else
                warn "npm 未找到，无法安装指定版本。请手动执行: npm install -g @anthropic-ai/claude-code@$STABLE_VERSION"
            fi
        else
            info "保持当前版本。"
        fi
    else
        info "保持默认自动升级策略。"
    fi

    # ---- 完成 ----
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║                                                  ║"
    echo "║              安装完成，开箱即用！                  ║"
    echo "║                                                  ║"
    echo "╠══════════════════════════════════════════════════╣"
    echo "║                                                  ║"
    echo "║  新终端生效:                                      ║"
    echo "║    source ~/.bashrc   (或重开终端)                ║"
    echo "║                                                  ║"
    echo "║  直接使用 (无需额外配置):                          ║"
    echo "║    fcc-claude     Claude Code 编程助手            ║"
    echo "║    fcc-codex      OpenAI Codex 编程助手           ║"
    echo "║                                                  ║"
    echo "║  服务管理:                                        ║"
    echo "║    fcc-server     启动代理服务                    ║"
    echo "║    http://127.0.0.1:8082/admin   管理界面          ║"
    echo "║                                                  ║"
    echo "║  工作流程:                                        ║"
    echo "║    1. fcc-server 已在后台运行                     ║"
    echo "║    2. 打开 http://127.0.0.1:8082/admin 配置模型    ║"
    echo "║    3. fcc-claude 或 fcc-codex 开始编码            ║"
    echo "║                                                  ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
    # 最后一次尝试：确保当前会话能直接用
    [ -d "$HOME/.local/bin" ] && export PATH="$HOME/.local/bin:$PATH" 2>/dev/null || true
    [ -d "$HOME/.cargo/bin" ] && export PATH="$HOME/.cargo/bin:$PATH" 2>/dev/null || true
}

main
