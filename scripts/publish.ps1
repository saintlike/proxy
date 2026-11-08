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
        $out = gh gist create --desc 'Claude Code ruleset (Shadowrocket / Clash)' `
            $listPath $yamlPath $jsPath 2>&1
        $url = ($out | Select-String -Pattern 'https://gist\.github\.com/\S+').Matches.Value
        if (-not $url) { throw "创建 gist 失败：$out" }
        $GistId = ($url -split '/')[-1]
        Set-Content -Path $idFile -Value $GistId -Encoding UTF8
        Say "[OK] 已创建 secret gist：$url" 'Green'
    } else {
        # gh gist edit 只能交互打开编辑器，这里直接走 REST：-F key=@file 会读文件内容
        gh api -X PATCH "/gists/$GistId" `
            -F "files[claude-rules.list][content]=@$listPath" `
            -F "files[claude-rules.yaml][content]=@$yamlPath" `
            -F "files[claude-rule.js][content]=@$jsPath" | Out-Null
        Say "[OK] 已更新 gist $GistId" 'Green'
    }

    $user = (gh api user --jq .login)
    $base = "https://gist.githubusercontent.com/$user/$GistId/raw"
    $repoBase = "https://raw.githubusercontent.com/$user/proxy/main/rules"
    Say ''
    Say '===== 订阅地址（主：仓库 raw）=====' 'Cyan'
    Say ("Shadowrocket / Surge RULE-SET : {0}/claude-rules.list" -f $repoBase) 'White'
    Say ("Clash / Stash rule-provider   : {0}/claude-rules.yaml" -f $repoBase) 'White'
    Say ("Shadowrocket 脚本（类型 rule）  : {0}/claude-rule.js" -f $repoBase) 'White'
    Say ''
    Say ("jsDelivr 加速                  : https://cdn.jsdelivr.net/gh/$user/proxy@main/rules/claude-rules.list") 'DarkGray'
    Say '===== 备用（gist，不依赖仓库可见性）=====' 'Cyan'
    Say ("{0}/claude-rules.list" -f $base) 'DarkGray'
    Say ("{0}/claude-rules.yaml" -f $base) 'DarkGray'
    Say ''
    Say ("仓库                            : https://github.com/$user/proxy") 'DarkGray'
}
finally {
    Pop-Location
}
