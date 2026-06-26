<#
.SYNOPSIS
    Free Claude Code (FCC) 一键安装/配置脚本 (Windows PowerShell)
.DESCRIPTION
    检测系统工具 → 安装 FCC → 可选开机自启动 → 可选模型配置
#>
param(
    [switch] $SkipCheck,
    [switch] $SkipAutostart,
    [switch] $SkipModel
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------- 辅助函数 ----------
function Write-OK    { Write-Host "[✓] $args" -ForegroundColor Green }
function Write-Fail  { Write-Host "[✗] $args" -ForegroundColor Red }
function Write-Warn  { Write-Host "[!] $args" -ForegroundColor Yellow }
function Write-Info  { Write-Host "[>] $args" -ForegroundColor Cyan }
function Write-Header { Write-Host ""; Write-Host "=== $args ===" -ForegroundColor White }

function Test-CommandAvailable {
    param([string] $Name)
    return [bool] (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-CommandVersion {
    param([string] $Name)
    try {
        $output = (& $Name --version 2>&1 | Out-String).Trim().Split("`n")[0]
        if (-not $output) { throw }
        return $output
    }
    catch {
        try { return (& $Name -v 2>&1 | Out-String).Trim().Split("`n")[0] }
        catch { return "已安装" }
    }
}

# ---------- 主流程 ----------
function Main {
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════╗"
    Write-Host "║   Free Claude Code (FCC) 自动化安装脚本        ║"
    Write-Host "╚═══════════════════════════════════════════════╝"

    # ---- 步骤 1: 检测系统 ----
    Write-Header "系统检测"
    Write-Host "操作系统: Windows"
    Write-Host "架构:     $(if ([Environment]::Is64BitOperatingSystem) { 'x86_64' } else { 'x86' })"

    # ---- 步骤 2: 检测工具 ----
    Write-Header "检测常用工具"

    $missing = $false
    $tools = @(
        @{ Name = "git"; Cmd = "git"; Required = $true; Hint = "https://git-scm.com/download/win" },
        @{ Name = "curl"; Cmd = "curl"; Required = $true; Hint = "Git Bash 自带 curl，或下载 https://curl.se" },
        @{ Name = "Node.js"; Cmd = "node"; Required = $false; Hint = "https://nodejs.org (推荐 LTS 版本)" },
        @{ Name = "npm"; Cmd = "npm"; Required = $false; Hint = "随 Node.js 一起安装" },
        @{ Name = "Python 3"; Cmd = "python3"; Required = $false; Hint = "" },
        @{ Name = "uv"; Cmd = "uv"; Required = $false; Hint = "" }
    )

    foreach ($tool in $tools) {
        if (Test-CommandAvailable $tool.Cmd) {
            Write-OK "$($tool.Name) — $(Get-CommandVersion $tool.Cmd)"
        }
        else {
            if ($tool.Required) {
                Write-Fail "$($tool.Name) 未安装（必需）"
                Write-Host "  下载: $($tool.Hint)"
                $missing = $true
            }
            else {
                Write-Warn "$($tool.Name) 未安装（可选）"
            }
        }
    }

    if ($missing) {
        Write-Host ""
        Write-Warn "请先安装缺失的必需工具，然后重新运行此脚本。"
        exit 1
    }

    Write-Host ""

    # ---- 步骤 3: 确认安装 ----
    Write-Header "开始安装 FCC"
    Write-Info "即将安装 Free Claude Code（包含 uv + Python 3.14）"
    Write-Info "本项目地址: https://github.com/Alishahryar1/free-claude-code"

    $confirm = Read-Host "是否继续？[Y/n]"
    if ($confirm -ne "" -and $confirm -ne "y" -and $confirm -ne "Y") {
        Write-Info "已取消安装。"
        exit 0
    }

    # ---- 步骤 4: 配置镜像加速 ----
    Write-Header "配置镜像加速"
    Write-Info "配置 npm 和 PyPI 阿里镜像源，加速国内下载..."

    if (Get-Command npm -ErrorAction SilentlyContinue) {
        npm config set registry https://registry.npmmirror.com 2>$null
        Write-OK "npm 镜像: registry.npmmirror.com"
    }

    $env:UV_INDEX_URL = "https://mirrors.aliyun.com/pypi/simple/"
    Write-OK "PyPI 镜像: mirrors.aliyun.com"

    # ---- 步骤 5: 执行安装 ----
    Write-Host ""
    Write-Header "使用 PowerShell 安装"
    Write-Info "执行 Windows 安装脚本（这将需要几分钟）..."
    Write-Info "安装内容: uv → Python 3.14 → Free Claude Code"

    try {
        Invoke-RestMethod "https://github.com/Alishahryar1/free-claude-code/blob/main/scripts/install.ps1?raw=1" | Invoke-Expression
    }
    catch {
        Write-Fail "安装失败: $_"
        exit 1
    }

    # ---- 步骤 6: 验证安装 ----
    Write-Host ""
    Write-Header "验证安装"

    # 刷新 PATH
    $env:Path = "$env:USERPROFILE\.cargo\bin;$env:USERPROFILE\.local\bin;$env:Path"

    if (Test-CommandAvailable "fcc-server") {
        Write-OK "fcc-server 已就绪"
    }
    else {
        Write-Warn "fcc-server 未在 PATH 中找到，可能需要重启终端。"
    }

    # ---- 步骤 7: 开机自启动 ----
    if (-not $SkipAutostart) {
        Write-Host ""
        Write-Header "开机自启动配置"
        $confirm = Read-Host "是否配置 fcc-server 开机自启动？[Y/n]"
        if ($confirm -eq "" -or $confirm -eq "y" -or $confirm -eq "Y") {
            Set-FccAutostart
        }
        else {
            Write-Info "跳过开机自启动配置。"
        }
    }

    # ---- 步骤 8: 模型配置 ----
    if (-not $SkipModel) {
        Write-Host ""
        Write-Header "模型配置"
        $confirm = Read-Host "是否现在配置模型和 API Key？[Y/n]"
        if ($confirm -eq "" -or $confirm -eq "y" -or $confirm -eq "Y") {
            Set-FccModel
        }
        else {
            Write-Info "跳过模型配置（之后可在 http://127.0.0.1:8082/admin 配置）。"
        }
    }

    # ---- 完成 ----
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════╗"
    Write-Host "║           安装完成！                         ║"
    Write-Host "╠═══════════════════════════════════════════════╣"
    Write-Host "║                                               ║"
    Write-Host "║  启动代理:   fcc-server                       ║"
    Write-Host "║  运行 Claude: fcc-claude                      ║"
    Write-Host "║  运行 Codex:  fcc-codex                        ║"
    Write-Host "║                                               ║"
    Write-Host "║  管理界面:   http://127.0.0.1:8082/admin       ║"
    Write-Host "║                                               ║"
    Write-Host "╚═══════════════════════════════════════════════╝"
    Write-Host ""
}

# ---------- 开机自启动 (Windows) ----------
function Set-FccAutostart {
    Write-Host ""

    # 查找 fcc-server 路径
    $fccPath = (Get-Command fcc-server -ErrorAction SilentlyContinue).Source
    if (-not $fccPath) {
        $cargoPath = Join-Path $env:USERPROFILE ".cargo\bin\fcc-server.exe"
        $localPath = Join-Path $env:USERPROFILE ".local\bin\fcc-server.exe"
        if (Test-Path $cargoPath) { $fccPath = $cargoPath }
        elseif (Test-Path $localPath) { $fccPath = $localPath }
        else {
            Write-Warn "未找到 fcc-server 路径，跳过自启动配置。"
            return
        }
    }

    # 在 Startup 文件夹创建 VBS 脚本（静默启动）
    $startupDir = [Environment]::GetFolderPath("Startup")
    $vbsPath = Join-Path $startupDir "fcc-server.vbs"

    $vbsContent = @"
Set WshShell = CreateObject("WScript.Shell")
WshShell.Run """$fccPath""", 0, False
"@

    $vbsContent | Out-File -FilePath $vbsPath -Encoding ASCII

    Write-OK "已创建 Windows 启动项: $vbsPath"
    Write-Host "  fcc-server 将在下次登录时自动静默启动（后台运行）。"
}

# ---------- 模型与 API Key 配置 ----------
function Set-FccModel {
    Write-Host ""

    $providers = @(
        @{ Num = 1;  Slug = "deepseek";         Name = "DeepSeek";          KeyUrl = "https://platform.deepseek.com/api_keys";              EnvKey = "DEEPSEEK_API_KEY";      Model = "deepseek/deepseek-chat" },
        @{ Num = 2;  Slug = "nvidia_nim";       Name = "NVIDIA NIM";        KeyUrl = "https://build.nvidia.com/settings/api-keys";           EnvKey = "NVIDIA_NIM_API_KEY";     Model = "nvidia_nim/nvidia/nemotron-3-super-120b-a12b" },
        @{ Num = 3;  Slug = "open_router";      Name = "OpenRouter";        KeyUrl = "https://openrouter.ai/keys";                           EnvKey = "OPENROUTER_API_KEY";     Model = "open_router/openrouter/free" },
        @{ Num = 4;  Slug = "gemini";           Name = "Google Gemini";     KeyUrl = "https://aistudio.google.com/apikey";                    EnvKey = "GEMINI_API_KEY";         Model = "gemini/models/gemini-3.1-flash-lite" },
        @{ Num = 5;  Slug = "groq";             Name = "Groq";              KeyUrl = "https://console.groq.com/keys";                         EnvKey = "GROQ_API_KEY";           Model = "groq/llama-3.3-70b-versatile" },
        @{ Num = 6;  Slug = "cerebras";         Name = "Cerebras";          KeyUrl = "https://cloud.cerebras.ai/apikeys";                     EnvKey = "CEREBRAS_API_KEY";       Model = "cerebras/llama3.3-70b" },
        @{ Num = 7;  Slug = "kimi";             Name = "Kimi";              KeyUrl = "https://platform.moonshot.ai/console/api-keys";         EnvKey = "KIMI_API_KEY";           Model = "kimi/kimi-moonshot-v1" },
        @{ Num = 8;  Slug = "mistral";          Name = "Mistral";           KeyUrl = "https://console.mistral.ai/api-keys";                   EnvKey = "MISTRAL_API_KEY";        Model = "mistral/mistral-large-latest" },
        @{ Num = 9;  Slug = "fireworks";        Name = "Fireworks";         KeyUrl = "https://fireworks.ai/account/api-keys";                  EnvKey = "FIREWORKS_API_KEY";      Model = "fireworks/accounts/fireworks/models/llama-v3p3-70b-instruct" },
        @{ Num = 10; Slug = "zai";              Name = "Z.ai";              KeyUrl = "https://z.ai";                                          EnvKey = "ZAI_API_KEY";            Model = "zai/glm-4" },
        @{ Num = 11; Slug = "wafer";            Name = "Wafer";             KeyUrl = "https://pass.wafer.ai";                                 EnvKey = "WAFER_API_KEY";          Model = "wafer/wafer-1" },
        @{ Num = 12; Slug = "opencode";         Name = "OpenCode";          KeyUrl = "https://opencode.ai";                                   EnvKey = "OPENCODE_API_KEY";       Model = "opencode/zen" },
        @{ Num = 13; Slug = "ollama";           Name = "Ollama (本地)";     KeyUrl = "";                                                      EnvKey = "";                       Model = "ollama/llama3.2" },
        @{ Num = 14; Slug = "lmstudio";         Name = "LM Studio (本地)";  KeyUrl = "";                                                      EnvKey = "";                       Model = "lmstudio/default" },
        @{ Num = 15; Slug = "llamacpp";         Name = "llama.cpp (本地)";  KeyUrl = "";                                                      EnvKey = "";                       Model = "llamacpp/default" }
    )

    Write-Host "  ┌─────────────────────────────────────────────┐"
    Write-Host "  │         FCC 支持的 AI 模型提供商            │"
    Write-Host "  ├─────────────────────────────────────────────┤"
    Write-Host "  │  远程提供商（需要 API Key）                  │"
    foreach ($p in $providers[0..11]) {
        Write-Host ("  │  " + $p.Num.ToString().PadRight(3) + $p.Name.PadRight(25) + " │")
    }
    Write-Host "  │                                               │"
    Write-Host "  │  本地提供商（无需 API Key）                    │"
    foreach ($p in $providers[12..14]) {
        Write-Host ("  │  " + $p.Num.ToString().PadRight(3) + $p.Name.PadRight(25) + " │")
    }
    Write-Host "  └─────────────────────────────────────────────┘"
    Write-Host ""

    $choice = Read-Host "请选择提供商 [1-15] (默认: 1 DeepSeek)"
    if (-not $choice) { $choice = "1" }

    try { $idx = [int]$choice - 1 }
    catch { Write-Warn "无效选择，跳过模型配置。"; return }

    if ($idx -lt 0 -or $idx -ge $providers.Count) {
        Write-Warn "无效选择，跳过模型配置。"
        return
    }

    $selected = $providers[$idx]
    Write-Host ""
    Write-Info "已选择: $($selected.Name)"

    # 本地提供商无需 Key
    if ($idx -ge 12) {
        Write-Info "$($selected.Name) 无需 API Key，使用默认地址。"
        Write-FccConfig $selected
        return
    }

    Write-Host "  获取 Key: $($selected.KeyUrl)"
    Write-Host ""
    $apiKey = Read-Host "请输入 $($selected.Name) API Key"

    if (-not $apiKey) {
        Write-Warn "API Key 为空，跳过配置。之后可在管理界面配置。"
        return
    }

    Write-FccConfig $selected $apiKey
}

# ---------- 写入 FCC 配置文件 ----------
function Write-FccConfig {
    param($Provider, $ApiKey = "")

    $fccDir = Join-Path $env:USERPROFILE ".fcc"
    $envFile = Join-Path $fccDir ".env"

    if (-not (Test-Path $fccDir)) {
        New-Item -Path $fccDir -ItemType Directory -Force | Out-Null
    }

    # 备份已有配置
    if (Test-Path $envFile) {
        $backupName = ".env.backup." + (Get-Date -Format "yyyyMMddHHmmss")
        Copy-Item $envFile (Join-Path $fccDir $backupName)
    }

    # 写入配置
    $config = @"
# FCC 配置文件 (由 setup-fcc.ps1 自动生成)
# 修改后重启 fcc-server 生效

# $($Provider.Name) 配置
$($Provider.EnvKey)=$ApiKey

# 模型配置
MODEL=$($Provider.Model)

# 服务端口 (默认 8082)
PORT=8082

# 服务认证
ANTHROPIC_AUTH_TOKEN=freecc

# 自动打开浏览器
FCC_OPEN_BROWSER=true
"@

    $config | Out-File -FilePath $envFile -Encoding utf8NoBOM

    Write-OK "$($Provider.Name) 配置已写入: $envFile"
    Write-Info "默认模型: $($Provider.Model)"
    Write-Info "你可以随时编辑此文件或通过管理界面修改配置。"

    # 提示重启
    $fccRunning = Get-Process -Name "fcc-server" -ErrorAction SilentlyContinue
    if ($fccRunning) {
        Write-Warn "检测到 fcc-server 正在运行，重启以应用新配置:"
        Write-Host "  Stop-Process -Name fcc-server; fcc-server"
    }
}

# 入口
Main
