#Requires -Version 5.1
<#
deploy.ps1 — Claude Code 配置一键部署（由同目录 d-kimi.bat 调用，也可直接运行）

行为：
  1. 从 -KeyEnvName 指定的环境变量读取 API Key（先查当前进程，再查用户级注册表，
     因此 setx 设置完无需重开终端即可生效）；
  2. 将本目录 settings.json 中的 ANTHROPIC_API_KEY 回填为真实密钥，经 JSON
     校验后写出（UTF-8 无 BOM），覆盖前自动备份现有配置；
  3. 引导 %USERPROFILE%\.claude.json：写入 penguinModeOrgEnabled=true 与
     hasCompletedOnboarding=true（Kimi 官方 Claude Code 接入流程的必要步骤，
     用于启用第三方模型支持并跳过 Anthropic 登录引导；优先经 node 执行官方
     等价脚本，node 不可用时回退 PowerShell JSON 处理，写前备份）；
  4. 按 -AgentAction 同步 vision 子代理：
       deploy = 部署本目录 agents\vision.md 到 <claude>\agents\vision.md
       remove = 备份并删除 <claude>\agents\vision.md（不再需要视觉转录专线时清理；
                 残留的其他供应商 vision 定义指向其各自端点模型，混用会路由失败）
       none   = 跳过
  5. 打印端点 / 模型 / 密钥掩码摘要。部署目标：%CLAUDE_CONFIG_DIR%（若已设置），否则 %USERPROFILE%\.claude
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$KeyEnvName,
    [Parameter(Mandatory = $true)][string]$ProfileLabel,
    [Parameter(Mandatory = $true)][ValidateSet('deploy', 'remove', 'none')][string]$AgentAction
)

$ErrorActionPreference = 'Stop'

# ---- 1. 取 API Key：进程环境变量 → 用户级（注册表 HKCU\Environment） ----
$apiKey = [Environment]::GetEnvironmentVariable($KeyEnvName, 'Process')
if (-not $apiKey) { $apiKey = [Environment]::GetEnvironmentVariable($KeyEnvName, 'User') }
$apiKey = ("$apiKey").Trim()
if (-not $apiKey) {
    Write-Host "[错误] 未找到环境变量 $KeyEnvName（当前进程与用户级注册表均未设置）。" -ForegroundColor Red
    Write-Host "       请先设置为用户环境变量后重试，例如：" -ForegroundColor Yellow
    Write-Host "         setx $KeyEnvName `"sk-kimi-你的密钥`"" -ForegroundColor Yellow
    Write-Host "       （setx 直接写入用户级注册表，本脚本从注册表读取，设置完无需重开终端。）" -ForegroundColor Yellow
    Write-Host "       密钥在 Kimi Code 控制台（https://www.kimi.com/code/console）创建。" -ForegroundColor Yellow
    exit 1
}
if ($apiKey -match '\s') {
    Write-Host "[错误] $KeyEnvName 的值含有空白字符，请检查是否复制了多余的引号或空格。" -ForegroundColor Red
    exit 1
}

# ---- 2. 定位源文件与部署目标 ----
$srcSettings = Join-Path $PSScriptRoot 'settings.json'
$claudeDir   = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE '.claude' }
$targetSettings = Join-Path $claudeDir 'settings.json'
$agentsDir  = Join-Path $claudeDir 'agents'
$targetVision  = Join-Path $agentsDir 'vision.md'
$claudeStateJson = Join-Path $env:USERPROFILE '.claude.json'
$stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')

if (-not (Test-Path $srcSettings)) {
    Write-Host "[错误] 找不到源配置：$srcSettings" -ForegroundColor Red
    exit 1
}

# ---- 3. 读取源配置并回填密钥（正则替换整值，不依赖占位符文本） ----
$text = [IO.File]::ReadAllText($srcSettings)
$pattern = '("ANTHROPIC_API_KEY"\s*:\s*")[^"]*(")'
if (-not [regex]::IsMatch($text, $pattern)) {
    Write-Host "[错误] $srcSettings 中未找到 ANTHROPIC_API_KEY 字段，无法回填密钥。" -ForegroundColor Red
    exit 1
}
$text = [regex]::Replace($text, $pattern, { param($m) $m.Groups[1].Value + $apiKey + $m.Groups[2].Value })

# ---- 4. 写出前校验：JSON 可解析、占位符已清除 ----
try { $json = $text | ConvertFrom-Json }
catch {
    Write-Host "[错误] 回填后的 settings.json 不是合法 JSON：$($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
if ("$($json.env.ANTHROPIC_API_KEY)" -match 'REPLACE_WITH') {
    Write-Host "[错误] 密钥回填未生效（仍为占位符），已中止写出。" -ForegroundColor Red
    exit 1
}

# ---- 5. 备份现有配置后写出（UTF-8 无 BOM） ----
if (-not (Test-Path $claudeDir)) { New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null }
if (Test-Path $targetSettings) {
    $bak = "$targetSettings.bak-$stamp"
    Copy-Item $targetSettings $bak -Force
    Write-Host "已备份原配置 -> $bak"
}
[IO.File]::WriteAllText($targetSettings, $text, [Text.UTF8Encoding]::new($false))
Write-Host "已部署 settings.json -> $targetSettings"

# ---- 6. 引导 .claude.json（官方接入步骤：第三方模型支持 + 跳过登录） ----
# 官方流程要求向 %USERPROFILE%\.claude.json 写入 penguinModeOrgEnabled=true 与
# hasCompletedOnboarding=true。优先用 node 执行官方等价脚本（保真序列化），
# node 不可用时回退 PowerShell JSON 处理（-Depth 100 防深层截断）。写前一律备份。
$nodeJs = @'
const fs = require('fs'), os = require('os'), path = require('path');
const p = path.join(os.homedir(), '.claude.json');
let content = {};
try { content = JSON.parse(fs.readFileSync(p, 'utf-8')); } catch (e) { if (fs.existsSync(p)) throw e; }
content.penguinModeOrgEnabled = true;
content.hasCompletedOnboarding = true;
fs.writeFileSync(p, JSON.stringify(content, null, 2), 'utf-8');
'@
$guided = $false
$node = Get-Command node -ErrorAction SilentlyContinue
if ($node) {
    if (Test-Path $claudeStateJson) {
        Copy-Item $claudeStateJson "$claudeStateJson.bak-$stamp" -Force
        Write-Host "已备份 .claude.json -> $claudeStateJson.bak-$stamp"
    }
    try {
        $tmpJs = Join-Path $env:TEMP "kimi-guide-$stamp.js"
        [IO.File]::WriteAllText($tmpJs, $nodeJs, [Text.UTF8Encoding]::new($false))
        & $node.Source $tmpJs
        Remove-Item $tmpJs -Force -ErrorAction SilentlyContinue
        if ($LASTEXITCODE -eq 0) { $guided = $true; Write-Host "已引导 .claude.json（node 通道）-> $claudeStateJson" }
    } catch { Write-Host "[警告] node 通道失败，改用 PowerShell 通道：$($_.Exception.Message)" -ForegroundColor Yellow }
}
if (-not $guided) {
    try {
        $state = $null
        if (Test-Path $claudeStateJson) {
            Copy-Item $claudeStateJson "$claudeStateJson.bak-$stamp" -Force
            Write-Host "已备份 .claude.json -> $claudeStateJson.bak-$stamp"
            $state = Get-Content $claudeStateJson -Raw | ConvertFrom-Json -Depth 100
        }
        if (-not $state) { $state = [pscustomobject]@{} }
        foreach ($prop in @('penguinModeOrgEnabled', 'hasCompletedOnboarding')) {
            if ($state.PSObject.Properties[$prop]) { $state.$prop = $true }
            else { $state | Add-Member -NotePropertyName $prop -NotePropertyValue $true }
        }
        [IO.File]::WriteAllText($claudeStateJson, ($state | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
        $guided = $true
        Write-Host "已引导 .claude.json（PowerShell 通道）-> $claudeStateJson"
    } catch {
        Write-Host "[警告] .claude.json 引导失败（$($_.Exception.Message)）。" -ForegroundColor Yellow
        Write-Host "       请按官方文档手动执行步骤②的 node 脚本：" -ForegroundColor Yellow
        Write-Host "       https://www.kimi.com/code/docs/third-party-tools/claude-code.html" -ForegroundColor Yellow
    }
}

# ---- 7. vision 子代理同步 ----
switch ($AgentAction) {
    'deploy' {
        $srcVision = Join-Path $PSScriptRoot 'agents\vision.md'
        if (Test-Path $srcVision) {
            if (-not (Test-Path $agentsDir)) { New-Item -ItemType Directory -Path $agentsDir -Force | Out-Null }
            Copy-Item $srcVision $targetVision -Force
            Write-Host "已部署 vision 子代理 -> $targetVision"
        }
        else {
            Write-Host "[警告] 未找到 $srcVision，已跳过 vision 子代理部署。" -ForegroundColor Yellow
        }
    }
    'remove' {
        if (Test-Path $targetVision) {
            Copy-Item $targetVision "$targetVision.bak-$stamp" -Force
            Remove-Item $targetVision -Force
            Write-Host "已移除 vision 子代理（原文件已备份）-> $targetVision"
        }
        else {
            Write-Host "vision 子代理不存在，无需清理。"
        }
    }
    default { }
}

# ---- 8. 摘要 ----
$masked = if ($apiKey.Length -gt 12) { $apiKey.Substring(0, 8) + '...' + $apiKey.Substring($apiKey.Length - 4) } else { '******' }
Write-Host ""
Write-Host "===== 部署完成：$ProfileLabel =====" -ForegroundColor Green
Write-Host ("  API 端点    : {0}" -f $json.env.ANTHROPIC_BASE_URL)
Write-Host ("  Opus/Sonnet : {0}（1M 上下文需 Allegretto 及以上档位）" -f $json.env.ANTHROPIC_DEFAULT_OPUS_MODEL)
Write-Host ("  Haiku       : {0}" -f $json.env.ANTHROPIC_DEFAULT_HAIKU_MODEL)
Write-Host ("  vision 专线 : {0}" -f 'k3（agents\vision.md frontmatter 裸名）')
Write-Host ("  密钥        : {0}（来自 {1}）" -f $masked, $KeyEnvName)
Write-Host ""
Write-Host "已运行的会话不会热加载 settings.json 与 .claude.json，请新开 Claude Code 会话生效。" -ForegroundColor Cyan
Write-Host "启动后输入 /status 验证：Base URL 显示 https://api.kimi.com/coding/ 即接入成功" -ForegroundColor Cyan
Write-Host "（即使模型名仍显示为 Claude 系名称，实际调用的已是 Kimi K3）。" -ForegroundColor Cyan
exit 0
