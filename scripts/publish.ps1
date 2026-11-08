<#
.SYNOPSIS
  一键发布：重新生成规则集 → 提交并推送私有仓库 → 刷新 secret gist（真正的订阅源）→ 打印订阅地址。

.DESCRIPTION
  为什么还要 gist：
    Shadowrocket / Clash 的 RULE-SET 拉取是匿名 HTTPS，私有仓库的 raw 地址会 404。
    secret gist 的 raw 地址不需要鉴权，且不出现在搜索/个人主页里，只对拿到链接的人可见。

  首次运行前需要有 gh 登录状态：gh auth status

.EXAMPLE
  pwsh -File .\scripts\publish.ps1
  pwsh -File .\scripts\publish.ps1 -NoGist      # 只推仓库
#>
[CmdletBinding()]
param(
    [string]$GistId = '',        # 已有 gist 的 id；留空则首次自动创建，创建后请填进 scripts/.gist-id
    [switch]$NoGist,
    [string]$Message = "chore: update claude ruleset"
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
function Say($m, $c = 'Gray') { Write-Host $m -ForegroundColor $c }

Push-Location $root
try {
    # 1) 生成
    & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'gen-ruleset.ps1') | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'gen-ruleset.ps1 执行失败' }

    # 2) 提交并推送
    git add -A
    $dirty = (git status --porcelain)
    if ($dirty) {
        git commit -m $Message | Out-Host
        git push origin HEAD | Out-Host
        Say "[OK] 已推送到私有仓库" 'Green'
    } else {
        Say '[--] 仓库没有变化，跳过提交' 'DarkGray'
    }

    if ($NoGist) { return }

    # 3) gist
    $idFile = Join-Path $PSScriptRoot '.gist-id'
    if (-not $GistId -and (Test-Path $idFile)) {
        $GistId = (Get-Content $idFile -Raw).Trim()
    }

    $listPath = Join-Path $root 'rules\claude-rules.list'
    $yamlPath = Join-Path $root 'rules\claude-rules.yaml'
    $jsPath   = Join-Path $root 'rules\claude-rule.js'

    if (-not $GistId) {
        $out = gh gist create --secret --desc 'Claude Code ruleset (Shadowrocket / Clash)' `
            $listPath $yamlPath $jsPath 2>&1
        $url = ($out | Select-String -Pattern 'https://gist\.github\.com/\S+').Matches.Value
        if (-not $url) { throw "创建 gist 失败：$out" }
        $GistId = ($url -split '/')[-1]
        Set-Content -Path $idFile -Value $GistId -Encoding UTF8
        Say "[OK] 已创建 secret gist：$url" 'Green'
    } else {
        gh gist edit $GistId $listPath $yamlPath $jsPath 2>&1 | Out-Host
        Say "[OK] 已更新 gist $GistId" 'Green'
    }

    $user = (gh api user --jq .login)
    $base = "https://gist.githubusercontent.com/$user/$GistId/raw"
    Say ''
    Say '===== 订阅地址 =====' 'Cyan'
    Say ("Shadowrocket / Surge RULE-SET : {0}/claude-rules.list" -f $base) 'White'
    Say ("Clash / Stash rule-provider   : {0}/claude-rules.yaml" -f $base) 'White'
    Say ("Shadowrocket 脚本（类型 rule）  : {0}/claude-rule.js" -f $base) 'White'
    Say ''
    Say ("仓库地址（私有，需登录）        : https://github.com/$user/proxy") 'DarkGray'
}
finally {
    Pop-Location
}
