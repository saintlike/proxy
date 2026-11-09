# Claude Code 分流改造 · 开发日志

> 记录一次完整的代理改造：从「Claude 走香港机房」改成「只走台湾家宽、速度优先、可观测、多端可复用」。
> 每一步都附当时的验证结果，方便日后回看为什么这么做、怎么复现。

- 时间：2026-11-05 ～ 2026-11-08
- 平台：Windows + Clash Verge Rev（mihomo v1.19.33）+ FlClash + iPhone Shadowrocket
- 参考：<https://ip.net.coffee/claude/site.html>（Claude 走干净住宅 IP、按域名分流、状态可视）

---

## 1. 起点：改造前的实测现状

用控制器 API 直接查，不靠猜：

| 检查项 | 结果 |
|---|---|
| `claude.ai` 命中哪条规则 | 没有专规则，落到 `MATCH` → `自动选择` → `香港专线 02A` |
| 订阅里跟 Anthropic 有关的规则 | 只有一条 `DOMAIN-KEYWORD,anthropic` |
| 漏掉的域名 | `claude.ai`、`claude.com`、`clau.de`、`api.anthropic.com` 全都没覆盖 |
| `ipv6` | `true`（会导致同一个站点 v4/v6 走不同出口） |
| 控制器 | `127.0.0.1:9097`，mixed-port `7897` |

结论：不是「规则不够全」而是「根本没有 Claude 的专用出口」，模型的 IP 纯净度完全听天由命。

## 2. 技术选型：三件事先做实验再说

改造前用 `mihomo -t` 做了三组对照实验，避免上线后整份配置加载失败：

1. **`geosite:anthropic` 可用吗？**
   自带 `geosite.dat` 确实有 `ANTHROPIC`（19 条，含 `claude.ai` / `claude.com` / `clau.de` / `claude.app`）。
   但实验证明：**未知的 geosite 类别会让整份配置加载失败（exit=1）**，而类别是否随数据库更新存在不可控。
   → **不采用 geosite**，全部写成显式域名。
2. **`IP-ASN,399358` 可用吗？**
   `ASN.mmdb` 命中，`IP-ASN` 规则可用，作为 IP 兜底保留。
3. **规则引用不存在的 proxy/分组会怎样？**
   同样**整份配置加载失败**。这决定了脚本必须「没有台湾节点就不建组、不加规则」，否则换订阅就炸。

被否决的还有：`category-ntp`（对本场景无用）；`DOMAIN-KEYWORD,sift`（会误伤 `gifts.*` / `shift.*`），
改成 `DOMAIN-SUFFIX,sift.com` + `DOMAIN-SUFFIX,siftscience.com` 两条。

## 3. 出口审计：为什么最后只放台湾家宽

用自建审计工具（`D:\Project\dev_ops\proxy-ip-audit`）从 Claude 视角逐节点打分：延迟、吞吐、IP 类型、滥用分、ASN。

| 节点 | 分数 | 吞吐 | 备注 |
|---|---|---|---|
| 台湾专线 02A | 100 | 7.5 Mbps | 最佳 |
| 台湾专线 03A | 100 | 6.8 Mbps | |
| 台湾专线 01A | 100 | 1.7 Mbps | 滥用分 0.0109（略高），慢 |
| 台湾专线 04A | 98 | — | 延迟最低 |
| 香港专线 ×4 | 100 | — | 出口其实是台湾 Hinet `1.164.159.16`，**不是香港 IP** |
| `FS\|` 美国线 | v4 92–96 / v6 72 | — | 同一节点 v6 走机房、v4 走住宅，双栈不一致 |

两个关键发现：

- 「香港专线」名不副实，实际出口是台湾住宅 IP —— 所以不必迷信香港出口。
- 美国线存在 **v4/v6 出口不一致**：Claude 视角下 v6 是机房 IP（72 分），v4 是住宅 IP（92–96 分）。
  这就是把 `ipv6` 关掉的理由：避免模型侧看到「机房 IP」而触发风控。

## 4. 最终形态

### 4.1 两个分组

| 组 | 类型 | 说明 |
|---|---|---|
| `🤖 Claude` | `select` | 默认选 `🤖 Claude-自动`，可手动钉死在某个台湾节点 |
| `🤖 Claude-自动` | `url-test` | url `https://claude.ai/cdn-cgi/trace`、`expected-status: 200`、`interval: 300`、`timeout: 5000`、`tolerance: 20`、`lazy: false`、`hidden: true` |

「只放台湾家宽」的筛选逻辑（脚本现算，不写死节点名）：

```
名字命中 台湾/臺灣/Taiwan/🇹🇼  且  命中 家宽/hinet/住宅/seednet/kbro/动态  → 优先
以上为空  →  退回「全部台湾节点」（例如 Here云 的「台湾专线 01A」，审计已证明是 Hinet 住宅 IP）
仍为空    →  不建组、不加规则（避免悬空引用导致整份配置加载失败）
```

### 4.2 规则集：36 条

| 类别 | 条数 | 例子 |
|---|---|---|
| 核心域名 | 18 | `claude.ai` `claude.com` `clau.de` `api.anthropic.com` `bridge.claudeusercontent.com` |
| 监控 / 遥测 | 6 | `statsig.*`、`sentry.*` 等 |
| 客服 widget | 3 | `intercom.*`、`datadog`（keyword，仅此一处） |
| 精确域名 | 6 | `claude.app` 一类不带子域的情况 |
| IP 兜底 | 3 | `IP-CIDR,160.79.104.0/21`、`IP-CIDR6,2607:6bc0::/32`、`IP-ASN,399358` |

全部规则带 `no-resolve`，避免为了匹配 IP 去触发 DNS 解析。

### 4.3 落地方式：全局脚本注入，不改订阅

订阅是 `type: remote` 的第三方订阅，直接改会被下次更新覆盖。所以：

- Clash Verge：**全局扩展脚本**（`profiles/Script.js`）
- FlClash：**配置 → ⋮ → 覆写 → 覆写模式 = 脚本**

两端入口都是 `main(config)`，所以**同一份脚本通用**。脚本本身幂等：

1. 先删同名分组、再删引用这两个分组的旧规则
2. 按名字现算成员
3. Claude 规则插在规则列表靠前、Cursor 规则压最前（保留原 Cursor 专线逻辑）

## 5. 实施与验证时间线

| 步骤 | 做了什么 | 验证结果 |
|---|---|---|
| 1 | 备份原 `profiles/Script.js`、`Merge.yaml` 到 `backup/` | 可回滚 |
| 2 | 从原脚本抽出 Cursor 三行逻辑，与新 Claude 段拼成 `global-script.js` | 文件生成 |
| 3 | 离线校验：yaml→json → node 跑脚本 → json→yaml → `mihomo -t`（全程 %TEMP%，不碰运行中的客户端） | 4 个订阅全 `test is successful`，每个都生成 36 条规则 |
| 4 | 订阅收缩：苏菲家宽、Flower_Trojan 不再续订 | 只保留 Kitty Network / Flower_SS / Here云 三个参与验证 |
| 5 | 热加载：`PUT /configs` 推 payload | **用 `path` 会被拒**：`400 path is not subpath of home directory or SAFE_PATHS`，必须推 payload 字符串 |
| 6 | 真机验收：规则命中 + 链路 + 出口 | `🤖 Claude → 🤖 Claude-自动 → 台湾专线 04A`；`api.anthropic.com`、`bridge.claudeusercontent.com` 均命中；出口 `118.232.199.98 TW` 98 分 |
| 7 | 组内延迟实测（`/group/<组>/delay`） | 04A 359ms / 01A 744 / 03A 1255 / 02A 1991（自动组按最快选） |
| 8 | 写 `verify.ps1` 固化验收 | 校验 ipv6、分组与链路、36 条规则位置与 hitCount、「改造前建立的旧连接」判 WARN，`-Strict` 才 FAIL |

## 6. 状态条（可观测性）

需求很克制：**只显示节点名和延迟**，贴在任务栏右下角。

- 实现：`status_bar.pyw`（Python + tkinter，无第三方 GUI 依赖），数据来自 `/proxies`、`/rules`、`/configs`，
  再经 mixed-port 真实请求一次 `https://claude.ai/cdn-cgi/trace` 拿延迟与出口 IP。
- 形态：`224×47+1696+950`（`dock=bottom_right`，右边沿贴屏幕、下边沿贴任务栏），宽度自适应。
- 拖动：自维护坐标 + 松手写 `status_bar.json`，下次启动（含开机）沿用。
- 开机自启：启动文件夹 `.lnk`（pythonw，最小化）+ `HKCU\...\Run\ClaudeProxyBar` 双保险。

## 7. 多端复用

### 7.1 手机 Shadowrocket

- 规则集用 `RULE-SET` 直连本仓库，或直接用「类型 = rule」的 `claude-rule.js`（jsc 引擎，支持 `$done`、`cidr`、`debug` 参数，node 单测 9 例通过）。
- 设置路径：设置 → 规则 → ➕ → 类型 `RULE-SET` → 值粘贴订阅地址 → 策略 `PROXY` → **拖到规则最前**。

### 7.2 订阅地址（公开可直接用）

| 用途 | 地址 |
|---|---|
| Shadowrocket / Surge `RULE-SET` | `https://raw.githubusercontent.com/saintlike/proxy/main/rules/claude-rules.list` |
| Clash / Stash `rule-provider` | `https://raw.githubusercontent.com/saintlike/proxy/main/rules/claude-rules.yaml` |
| Shadowrocket 脚本 | `https://raw.githubusercontent.com/saintlike/proxy/main/rules/claude-rule.js` |
| 纯清单兜底 | `https://raw.githubusercontent.com/saintlike/proxy/main/rules/claude-rules.txt` |

jsDelivr（国内通常更快，更新有几分钟延迟）：

```
https://cdn.jsdelivr.net/gh/saintlike/proxy@main/rules/claude-rules.list
https://cdn.jsdelivr.net/gh/saintlike/proxy@main/rules/claude-rules.yaml
```

备用源（secret gist，raw CDN 抽风时用）：
`https://gist.githubusercontent.com/saintlike/a990ebe79e7c98422cc91e608d958b00/raw/`

## 8. 踩过的坑（复现时会再次遇到）

| 坑 | 现象 | 原因 / 解法 |
|---|---|---|
| geosite 类别 | 整份配置 `exit=1` | 数据库不含该类别就整份失败；改用显式域名 |
| 悬空引用 | 整份配置 `exit=1` | 规则/分组引用了不存在的 proxy；脚本改为「没节点就不建组」 |
| 热加载 | `400 path is not subpath of home directory or SAFE_PATHS` | `PUT /configs` 只能推 payload 字符串，不能推路径 |
| 私有仓库订阅 | 匿名 raw 404 | 仓库必须 public，或改用 secret gist |
| `gh gist edit` | 无法传文件 | 改用 `gh api -X PATCH /gists/<id> -F "files[名][content]=@路径"` |
| 浮窗全透明 | 窗口看不见 | 手工加了 `WS_EX_LAYERED` 却没设 alpha；只加 `WS_EX_TRANSPARENT` 才安全 |
| 任务栏矩形为空 | 窗口压到屏幕最底 | 远程桌面/刚登录时 `ABM_GETTASKBARPOS` 可能返回空；加 `FindWindowW("Shell_TrayWnd")` 回退 |
| DPI 缩放 | 窗口位置偏移 | 一切像素计算都要乘缩放比 |
| 托盘图标空白 | 图标不显示 | ctypes 未声明 `argtypes` 时字符串按 ANSI 传，`LoadImageW` 拿到错路径 |
| VBScript 自启 | 弹「缺少对象: 'sh'」 | VBScript 按 ANSI 读文件，UTF-8 中文注释被吞；改纯 ASCII 或直接用 `.lnk` |
| 沙箱杀 GUI 进程 | pythonw 起来就死 | 改用 WMI `Win32_Process.Create()` 以用户身份脱离进程树启动 |

## 9. 回滚

1. `backup/` 里的 `Script.js`、`Merge.yaml` 覆盖回 `%APPDATA%\io.github.clash-verge-rev.clash-verge-rev\profiles\`
2. `PUT /configs` 或用客户端「重新加载配置」
3. 状态条：删掉 `status_bar.json`（位置）、移除启动项 `.lnk` 与 HKCU Run 键

订阅本身从未被修改，回滚不涉及第三方服务。

## 10. 后续可做

- `ipv6` 已在建议中关闭，但**尚未强制**（属于客户端全局设置，不写在脚本里）
- Gemini / ChatGPT 还没做同级别的节点纯净度审计（`proxy-ip-audit --targets chatgpt,gemini` 可直接复用）
- 状态条只做「看」，不做「点一下切节点」（避免误操作）
