# proxy

Claude Code / Anthropic 的分流规则集。一份源文件，三种订阅格式，自动生成。

**公开仓库，可直接订阅：**

| 客户端 | 订阅地址 |
|---|---|
| Shadowrocket / Surge | `https://raw.githubusercontent.com/saintlike/proxy/main/rules/claude-rules.list` |
| Clash / Stash | `https://raw.githubusercontent.com/saintlike/proxy/main/rules/claude-rules.yaml` |
| Shadowrocket 脚本 | `https://raw.githubusercontent.com/saintlike/proxy/main/rules/claude-rule.js` |

走 jsDelivr CDN（国内通常更快，更新有几分钟延迟）：

```
https://cdn.jsdelivr.net/gh/saintlike/proxy@main/rules/claude-rules.list
https://cdn.jsdelivr.net/gh/saintlike/proxy@main/rules/claude-rules.yaml
```

## 里面有什么

| 文件 | 用途 |
|---|---|
| `claude-rules.txt` | **源文件**（36 条规则，唯一事实来源） |
| `rules/claude-rules.list` | Shadowrocket / Surge 的 `RULE-SET` 规则集（策略 `PROXY`） |
| `rules/claude-rules.yaml` | Clash / Stash 的 `rule-provider`（`behavior: classical` 的 payload） |
| `rules/claude-rules.txt` | 纯域名/IP 清单（其它客户端兜底） |
| `rules/claude-rule.js` | Shadowrocket 的「类型 = rule」脚本 |
| `scripts/gen-ruleset.ps1` | 从源文件重新生成上面三种格式 |
| `scripts/publish.ps1` | 生成 + 提交 + push + 刷新备用 gist |

规则内容：核心域名 18 条、监控/遥测 6 条、客服 widget 3 条、精确域名 6 条，
外加 `IP-CIDR 160.79.104.0/21` / `IP-CIDR6 2607:6bc0::/32` / `IP-ASN 399358` 兜底。

## 用法

### Shadowrocket / Surge

设置 → 规则 → ➕ → 类型 `RULE-SET` → 值粘贴上面的 `.list` 地址 → 策略 `PROXY` → 保存后**拖到规则列表最前面**。

### Clash / Stash

```yaml
rule-providers:
  claude:
    behavior: classical
    format: yaml
    url: https://raw.githubusercontent.com/saintlike/proxy/main/rules/claude-rules.yaml
    interval: 86400

rules:
  - RULE-SET,claude,🤖 Claude     # 有自定义分组时
  - RULE-SET,claude,PROXY         # 没有自定义分组时用这条
```

## 改规则

1. 编辑 `claude-rules.txt`（一行一条，`TYPE,PATTERN[,GROUP]`，`#` 开头是注释）
2. `pwsh -File scripts/gen-ruleset.ps1` —— 生成三种格式
3. `pwsh -File scripts/publish.ps1` —— 提交并推送，顺便刷新备用 gist 并打印地址

> 仓库已经是 public，订阅直接读 GitHub raw 即可。`publish.ps1` 里还保留了一份 secret gist，
> 作为 raw CDN 抽风时的备用源（`.gist-id` 记录着它的 id）。

## 为什么规则里没有 geosite

`geosite:anthropic` 依赖客户端自带的 geo 数据库；某次数据更新丢掉这个类别，整份配置会加载失败。
显式域名没有这个风险，代价只是多几十行。

## 为什么 sift 写成两条后缀

`DOMAIN-KEYWORD,sift` 会误伤 `gifts.*` / `shift.*` 一类域名，所以拆成
`DOMAIN-SUFFIX,sift.com` 和 `DOMAIN-SUFFIX,siftscience.com`。
