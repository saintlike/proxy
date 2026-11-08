<#
.SYNOPSIS
  从 claude-rules.txt 生成三种订阅格式：
    rules/claude-rules.list   Shadowrocket / Surge 的 RULE-SET（TYPE,PATTERN,PROXY）
    rules/claude-rules.yaml   Clash / Stash 的 rule-provider（behavior: classical 的 payload）
    rules/claude-rules.txt    纯域名清单（给不认上面两种的客户端）

.EXAMPLE
  pwsh -File .\scripts\gen-ruleset.ps1
#>
[CmdletBinding()]
param(
    [string]$Source = (Join-Path $PSScriptRoot '..\claude-rules.txt'),
    [string]$OutDir = (Join-Path $PSScriptRoot '..\rules'),
    [string]$Policy = 'PROXY'
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Source)) { throw "找不到源文件：$Source" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$rules = @()
foreach ($line in [System.IO.File]::ReadAllLines($Source, [System.Text.Encoding]::UTF8)) {
    $s = $line.Trim()
    if (-not $s -or $s.StartsWith('#')) { continue }
    $rules += $s
}
if ($rules.Count -eq 0) { throw '源文件里没有规则' }

# ---- 1. RULE-SET：把第三段（策略组名）换成客户端认识的名字，保留 no-resolve 这类选项
$listLines = @(
    '# Claude Code / Anthropic 分流规则集'
    "# 生成自 claude-rules.txt，共 $($rules.Count) 条；策略默认 $Policy"
)
foreach ($r in $rules) {
    $p = $r.Split(',')
    $opt = if ($p.Count -ge 4) { $p[3..($p.Count - 1)] -join ',' } else { '' }
    $line = $p[0] + ',' + $p[1] + ',' + $Policy
    if ($opt) { $line += ',' + $opt }
    $listLines += $line
}
[System.IO.File]::WriteAllLines((Join-Path $OutDir 'claude-rules.list'), $listLines, (New-Object System.Text.UTF8Encoding($false)))

# ---- 2. Clash rule-provider：behavior: classical 的 payload 里不带策略，只留规则 + 选项
$yamlLines = @(
    '# Claude Code / Anthropic —— Clash / Stash rule-provider'
    '# 用法：rule-providers 里 behavior: classical，rules 里写 RULE-SET,claude,🤖 Claude'
    'payload:'
)
foreach ($r in $rules) {
    $p = $r.Split(',')
    $opt = if ($p.Count -ge 4) { $p[3..($p.Count - 1)] -join ',' } else { '' }
    $item = $p[0] + ',' + $p[1]
    if ($opt) { $item += ',' + $opt }
    $yamlLines += '  - ' + $item
}
[System.IO.File]::WriteAllLines((Join-Path $OutDir 'claude-rules.yaml'), $yamlLines, (New-Object System.Text.UTF8Encoding($false)))

# ---- 3. 纯域名清单
$plainLines = @('# Claude Code / Anthropic 域名 + IP 段（纯清单）')
foreach ($r in $rules) { $plainLines += $r.Split(',')[1] }
[System.IO.File]::WriteAllLines((Join-Path $OutDir 'claude-rules.txt'), $plainLines, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "[OK] $($rules.Count) 条规则 ->" -ForegroundColor Green
foreach ($f in 'claude-rules.list', 'claude-rules.yaml', 'claude-rules.txt') {
    $path = Join-Path $OutDir $f
    Write-Host ("     {0}  ({1} 行)" -f $f, (Get-Content $path).Count) -ForegroundColor DarkGray
}
