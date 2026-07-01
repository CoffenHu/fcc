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

# ---------- 自动安装工具 (Windows) ----------
function Install-MissingTool {
    param(
        [string] $Name,
        [string] $WingetId,
        [string] $ChocoPkg,
        [string] $ManualUrl
    )
    Write-Host ""
    Write-Header "=== 自动安装 $Name ==="
    Write-Info "检测到 $Name 未安装，正在自动安装..."

    # 优先 winget (Windows 10/11 自带)
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        try {
            winget install --id $WingetId --silent --accept-package-agreements 2>$null
            if ($LASTEXITCODE -eq 0) { return $true }
        } catch {}
    }

    # 其次 chocolatey
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        try {
            choco install $ChocoPkg -y --limit-output 2>$null
            if ($LASTEXITCODE -eq 0) { return $true }
        } catch {}
    }

    Write-Warn "自动安装失败，请手动安装: $ManualUrl"
    return $false
}

function Install-MissingNode {
    Write-Host ""
    Write-Header "=== 自动安装 Node.js ==="
    Write-Info "检测到 Node.js/npm 未安装，正在自动安装..."

    # winget
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        try {
            winget install --id OpenJS.NodeJS.LTS --silent --accept-package-agreements 2>$null
            if ($LASTEXITCODE -eq 0) {
                # 刷新 PATH
                $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                            [Environment]::GetEnvironmentVariable("Path", "User")
                return $true
            }
        } catch {}
    }

    # chocolatey
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        try {
            choco install nodejs-lts -y --limit-output 2>$null
            if ($LASTEXITCODE -eq 0) {
                $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                            [Environment]::GetEnvironmentVariable("Path", "User")
                return $true
            }
        } catch {}
    }

    Write-Warn "自动安装失败，请手动安装: https://nodejs.org (推荐 LTS 版本)"
    return $false
}

# ---------- 主流程 ----------
function Main {
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════╗"
    Write-Host "║                                                  ║"
    Write-Host "║     Free Claude Code (FCC) 一键安装脚本           ║"
    Write-Host "║                                                  ║"
    Write-Host "╚══════════════════════════════════════════════════╝"

    # ---- 步骤 1: 检测系统 ----
    Write-Header "系统检测"
    Write-Host "操作系统: Windows"
    Write-Host "架构:     $(if ([Environment]::Is64BitOperatingSystem) { 'x86_64' } else { 'x86' })"

    # ---- 步骤 2: 检测必需工具 + 自动安装 ----
    Write-Header "检测常用工具 + 自动安装"

    # 预加载常用 bin 目录
    $env:Path = "$env:USERPROFILE\.local\bin;$env:USERPROFILE\.cargo\bin;$env:Path"

    $needGit = $false
    $needCurl = $false
    $needNode = $false
    $nodeMissing = $false

    # git
    if (Test-CommandAvailable "git") {
        Write-OK "Git — $(Get-CommandVersion git)"
    } else {
        Write-Fail "Git 未安装（必需）"
        $needGit = $true
    }

    # curl
    if (Test-CommandAvailable "curl") {
        Write-OK "curl — $(Get-CommandVersion curl)"
    } else {
        Write-Fail "curl 未安装（必需）"
        $needCurl = $true
    }

    # Node.js / npm（必需 — 上游安装脚本依赖）
    if (Test-CommandAvailable "node") {
        Write-OK "Node.js — $(Get-CommandVersion node)"
    } else {
        Write-Fail "Node.js 未安装（必需）"
        $needNode = $true
        $nodeMissing = $true
    }

    if (Test-CommandAvailable "npm") {
        Write-OK "npm — $(Get-CommandVersion npm)"
    } else {
        Write-Fail "npm 未安装（必需）"
        if (-not $nodeMissing) { Write-Host "  下载: https://nodejs.org (推荐 LTS 版本)" }
    }

    # 可选工具
    if (Test-CommandAvailable "python3") {
        Write-OK "Python 3 — $(Get-CommandVersion python3)"
    } else {
        Write-Warn "Python 3 未安装（可选）"
    }

    if (Test-CommandAvailable "uv") {
        Write-OK "uv — $(Get-CommandVersion uv)"
    } else {
        Write-Warn "uv 未安装（可选）"
    }

    # 缺失的工具自动安装
    if ($needGit) {
        if (-not (Install-MissingTool -Name "Git" -WingetId "Git.Git" -ChocoPkg "git" -ManualUrl "https://git-scm.com/download/win")) {
            $script:missing = $true
        } else {
            Write-OK "Git 安装成功"
        }
    }

    if ($needCurl) {
        if (-not (Install-MissingTool -Name "curl" -WingetId "cURL.cURL" -ChocoPkg "curl" -ManualUrl "https://curl.se")) {
            $script:missing = $true
        } else {
            Write-OK "curl 安装成功"
        }
    }

    if ($needNode) {
        if (-not (Install-MissingNode)) {
            $script:missing = $true
        } else {
            Write-OK "Node.js 安装成功"
        }
    }

    # 最终验证
    $script:missing = $false
    if (-not (Test-CommandAvailable "git"))  { Write-Fail "Git 仍未找到"; $script:missing = $true }
    if (-not (Test-CommandAvailable "curl")) { Write-Fail "curl 仍未找到"; $script:missing = $true }
    if (-not (Test-CommandAvailable "node")) { Write-Fail "Node.js 仍未找到"; $script:missing = $true }
    if (-not (Test-CommandAvailable "npm"))  { Write-Fail "npm 仍未找到"; $script:missing = $true }

    if ($script:missing) {
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
    Write-Host "╔══════════════════════════════════════════════════╗"
    Write-Host "║                                                  ║"
    Write-Host "║              安装完成，开箱即用！                  ║"
    Write-Host "║                                                  ║"
    Write-Host "╠══════════════════════════════════════════════════╣"
    Write-Host "║                                                  ║"
    Write-Host "║  新终端生效:                                      ║"
    Write-Host "║    重新打开终端即可                               ║"
    Write-Host "║                                                  ║"
    Write-Host "║  直接使用 (无需额外配置):                          ║"
    Write-Host "║    fcc-claude     Claude Code 编程助手            ║"
    Write-Host "║    fcc-codex      OpenAI Codex 编程助手           ║"
    Write-Host "║                                                  ║"
    Write-Host "║  服务管理:                                        ║"
    Write-Host "║    fcc-server     启动代理服务                    ║"
    Write-Host "║    http://127.0.0.1:8082/admin   管理界面          ║"
    Write-Host "║                                                  ║"
    Write-Host "║  工作流程:                                        ║"
    Write-Host "║    1. fcc-server 启动代理                         ║"
    Write-Host "║    2. 打开 http://127.0.0.1:8082/admin 配置模型    ║"
    Write-Host "║    3. fcc-claude 或 fcc-codex 开始编码            ║"
    Write-Host "║                                                  ║"
    Write-Host "╚══════════════════════════════════════════════════╝"
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
        @{ Num = 1;  Slug = "deepseek";         Name = "DeepSeek";          KeyUrl = "https://platform.deepseek.com/api_keys";              EnvKey = "DEEPSEEK_API_KEY";      Model = "deepseek/deepseek-v4-pro" },
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

    Write-Host "  ┌──────────────────────────────────────────────────┐"
    Write-Host "  │            FCC 支持的 AI 模型提供商               │"
    Write-Host "  ├──────────────────────────────────────────────────┤"
    Write-Host "  │  远程提供商（需要 API Key）                        │"
    Write-Host "  │                                                  │"
    foreach ($p in $providers[0..11]) {
        $num = $p.Num.ToString().PadRight(3)
        $name = $p.Name.PadRight(18)
        $url = $p.KeyUrl.PadRight(35)
        Write-Host "  │   $num $name $url │"
    }
    Write-Host "  │                                                  │"
    Write-Host "  │  本地提供商（无需 API Key）                          │"
    Write-Host "  │                                                  │"
    foreach ($p in $providers[12..14]) {
        $num = $p.Num.ToString().PadRight(3)
        $name = $p.Name.PadRight(18)
        $addr = if ($p.Slug -eq "ollama") { "localhost:11434" } `
           elseif ($p.Slug -eq "lmstudio") { "localhost:1234/v1" } `
           else { "localhost:8080/v1" }
        $addr = $addr.PadRight(35)
        Write-Host "  │   $num $name $addr │"
    }
    Write-Host "  └──────────────────────────────────────────────────┘"
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

    # 先通过 fcc-init 生成默认配置（保留上游所有默认值）
    if (Get-Command fcc-init -ErrorAction SilentlyContinue) {
        Write-Info "运行 fcc-init 生成默认配置..."
        try { fcc-init 2>$null } catch {}
    }

    # 如果 fcc-init 未生成，则创建空文件
    if (-not (Test-Path $envFile)) {
        "" | Out-File -FilePath $envFile -Encoding utf8NoBOM
    }
    else {
        $backupName = ".env.backup." + (Get-Date -Format "yyyyMMddHHmmss")
        Copy-Item $envFile (Join-Path $fccDir $backupName)
    }

    # 读入现有配置并更新 MODEL、路由模型、API Key
    $lines = Get-Content $envFile -Encoding utf8NoBOM
    $newLines = @()
    $hasModel = $false
    $hasOpus = $false; $hasSonnet = $false; $hasHaiku = $false
    $hasKey = $false

    foreach ($line in $lines) {
        if ($line -match '^MODEL=') {
            $newLines += "MODEL=$($Provider.Model)"
            $hasModel = $true
        }
        elseif ($line -match '^MODEL_OPUS=') {
            $newLines += "MODEL_OPUS=$($Provider.Model)"
            $hasOpus = $true
        }
        elseif ($line -match '^MODEL_SONNET=') {
            $newLines += "MODEL_SONNET=$($Provider.Model)"
            $hasSonnet = $true
        }
        elseif ($line -match '^MODEL_HAIKU=') {
            $newLines += "MODEL_HAIKU=$($Provider.Model)"
            $hasHaiku = $true
        }
        elseif ($ApiKey -and $Provider.EnvKey -and ($line -match "^$([regex]::Escape($Provider.EnvKey))=")) {
            $newLines += "$($Provider.EnvKey)=$ApiKey"
            $hasKey = $true
        }
        else {
            $newLines += $line
        }
    }

    if (-not $hasModel)  { $newLines += "MODEL=$($Provider.Model)" }
    if (-not $hasOpus)   { $newLines += "MODEL_OPUS=$($Provider.Model)" }
    if (-not $hasSonnet) { $newLines += "MODEL_SONNET=$($Provider.Model)" }
    if (-not $hasHaiku)  { $newLines += "MODEL_HAIKU=$($Provider.Model)" }
    if ($ApiKey -and $Provider.EnvKey -and -not $hasKey) { $newLines += "$($Provider.EnvKey)=$ApiKey" }

    $newLines | Out-File -FilePath $envFile -Encoding utf8NoBOM

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
