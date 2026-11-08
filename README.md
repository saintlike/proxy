# proxy

Claude Code / Anthropic 的分流规则集。一份源文件，三种订阅格式，自动生成。

## 里面有什么

| 文件 | 用途 |
|---|---|
| `claude-rules.txt` | **源文件**（36 条规则，唯一事实来源） |
| `rules/claude-rules.list` | Shadowrocket / Surge 的 `RULE-SET` 规则集 |
| `rules/claude-rules.yaml` | Clash / Stash 的 `rule-provider`（`behavior: classical` 的 payload） |
| `rules/claude-rules.txt` | 纯域名/IP 清单（其它客户端兜底） |
| `rules/claude-rule.js` | Shadowrocket 的「类型 = rule」脚本 |
| `scripts/gen-ruleset.ps1` | 从源文件重新生成上面三种格式 |
| `scripts/publish.ps1` | 生成 + 提交 + push + 更新订阅用的 gist（打印新 URL） |

规则内容：核心域名 18 条、监控/遥测 6 条、客服 widget 3 条、精确域名 6 条，
外加 `IP-CIDR 160.79.104.0/21` / `IP-CIDR6 2607:6bc0::/32` / `IP-ASN 399358` 兜底。

## 订阅地址

> 仓库是 **private**，而 Shadowrocket / Clash 的 `RULE-SET` 拉取是**不带鉴权**的，
> 私有仓库的 raw 地址直接订阅会 404。所以真正给客户端用的是 **secret gist**
> （只有拿到链接的人能看到，不会出现在搜索/个人主页里）。
> 每次改完规则跑 `scripts/publish.ps1` 会同时更新仓库和 gist，并打印最新地址。

- Shadowrocket / Surge：见 `scripts/publish.ps1` 输出的 `RULE-SET` 地址
- Clash / Stash：

```yaml
rule-providers:
  claude:
    behavior: classical
    format: yaml
    url: <publish.ps1 输出的 yaml 地址>
    interval: 86400

rules:
  - RULE-SET,claude,🤖 Claude
  - RULE-SET,claude,PROXY        # 没有自定义分组时用这条
```

## 改规则

1. 编辑 `claude-rules.txt`（一行一条，`TYPE,PATTERN[,GROUP]`，`#` 开头是注释）
2. `pwsh -File scripts/gen-ruleset.ps1` —— 生成三种格式
3. `pwsh -File scripts/publish.ps1` —— 提交并推送，同时刷新 gist，打印订阅地址

## 为什么规则里没有 geosite

`geosite:anthropic` 依赖客户端自带的 geo 数据库；某次数据更新丢掉这个类别，整份配置会加载失败。
显式域名没有这个风险，代价只是多几十行。

## 为什么 sift 写成两条后缀

`DOMAIN-KEYWORD,sift` 会误伤 `gifts.*` / `shift.*` 一类域名，所以拆成
`DOMAIN-SUFFIX,sift.com` 和 `DOMAIN-SUFFIX,siftscience.com`。
