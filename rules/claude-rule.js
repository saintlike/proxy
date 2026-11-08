/**
 * Claude Code 分流 —— Shadowrocket「类型: rule」脚本
 * 引擎: jsc    超时: 10
 *
 * 用法：把它挂成一条 SCRIPT 规则，命中就按这条规则配置的策略走代理。
 * 规则内容和 clash-claude-routing/claude-rules.txt 保持一致（36 条）。
 *
 * 可选参数（填在脚本的「参数」里，逗号分隔）：
 *   done=object   返回 $done({matched:true/false})，Shadowrocket / Surge 默认写法（推荐）
 *   done=bool     返回 $done(true/false)，个别老版本/兼容层用这个
 *   cidr=1        额外用 IP 段兜底（默认 1，需要运行环境能给出目标 IP）
 *   debug=1       在 Proxy Log 里打印每次命中情况
 *
 * 示例：done=object,cidr=1,debug=0
 */

var CLAUDE_SUFFIX = [
  'anthropic.com', 'claude.ai', 'claude.com', 'clau.de',
  'claudemcpclient.com', 'claudemcpcontent.com', 'claudeusercontent.com',
  'claude.app', 'claude.dev', 'claude.new', 'claude.site',
  'claudeacademy.com', 'claudepages.dev', 'claudestudio.com',
  'chatbotclaude.com', 'anthropic.team', 'ant.dev', 'antspace.dev',
  'sentry.io', 'statsigapi.net', 'statsig.com', 'sift.com', 'siftscience.com',
  'intercom.io', 'intercomcdn.com', 'intercomassets.com'
];

var CLAUDE_EXACT = [
  'servd-anthropic-website.b-cdn.net',
  'anthropic.com.cdn.cloudflare.net',
  'anthropic.auth0.com',
  'anthropic-com.ghost.io',
  'browser-intake-us5-datadoghq.com',
  'cdn.usefathom.com'
];

var CLAUDE_KEYWORD = ['datadog'];

var CLAUDE_IPV4 = ['160.79.104.0/21'];
var CLAUDE_IPV6 = ['2607:6bc0::/32'];

// ---------------------------------------------------------------- 参数
function parseArgs(raw) {
  var out = { done: 'object', cidr: true, debug: false };
  if (!raw || typeof raw !== 'string') return out;
  raw.split(',').forEach(function (kv) {
    var i = kv.indexOf('=');
    var k = (i < 0 ? kv : kv.slice(0, i)).trim().toLowerCase();
    var v = (i < 0 ? '1' : kv.slice(i + 1)).trim().toLowerCase();
    if (k === 'done') out.done = v;
    else if (k === 'cidr') out.cidr = !(v === '0' || v === 'false' || v === 'no');
    else if (k === 'debug') out.debug = (v === '1' || v === 'true' || v === 'yes');
  });
  return out;
}

// ---------------------------------------------------------------- 工具
function hostMatches(host) {
  for (var i = 0; i < CLAUDE_SUFFIX.length; i++) {
    var d = CLAUDE_SUFFIX[i];
    if (host === d || host.slice(-(d.length + 1)) === '.' + d) return 'suffix:' + d;
  }
  for (var j = 0; j < CLAUDE_EXACT.length; j++) {
    if (host === CLAUDE_EXACT[j]) return 'exact:' + CLAUDE_EXACT[j];
  }
  for (var k = 0; k < CLAUDE_KEYWORD.length; k++) {
    if (host.indexOf(CLAUDE_KEYWORD[k]) >= 0) return 'keyword:' + CLAUDE_KEYWORD[k];
  }
  return '';
}

function ipv4ToInt(ip) {
  var p = ip.split('.');
  if (p.length !== 4) return null;
  var n = 0;
  for (var i = 0; i < 4; i++) {
    var v = parseInt(p[i], 10);
    if (isNaN(v) || v < 0 || v > 255) return null;
    n = n * 256 + v;
  }
  return n;
}

function inCidr4(ip, cidr) {
  var bits = cidr.split('/');
  var base = ipv4ToInt(bits[0]);
  var cur = ipv4ToInt(ip);
  if (base === null || cur === null) return false;
  var mask = bits.length > 1 ? parseInt(bits[1], 10) : 32;
  if (isNaN(mask) || mask < 0 || mask > 32) mask = 32;
  var shift = 32 - mask;
  if (shift === 32) return true;
  return Math.floor(base / Math.pow(2, shift)) === Math.floor(cur / Math.pow(2, shift));
}

function ipMatches(ip) {
  if (!ip) return '';
  if (ip.indexOf(':') >= 0) {
    for (var i = 0; i < CLAUDE_IPV6.length; i++) {
      // 只做前缀判断，够覆盖 2607:6bc0::/32
      var prefix = CLAUDE_IPV6[i].split('/')[0].replace(/:0+$/, '').replace(/::$/, '');
      if (prefix && ip.toLowerCase().indexOf(prefix.toLowerCase()) === 0) return 'ip6:' + CLAUDE_IPV6[i];
    }
    return '';
  }
  for (var j = 0; j < CLAUDE_IPV4.length; j++) {
    if (inCidr4(ip, CLAUDE_IPV4[j])) return 'ip4:' + CLAUDE_IPV4[j];
  }
  return '';
}

// ---------------------------------------------------------------- 主逻辑
function main() {
  var args = parseArgs(typeof $argument === 'string' ? $argument : '');

  var req = (typeof $request !== 'undefined' && $request) ? $request : {};
  var host = String(req.hostname || req.host || '').toLowerCase();
  if (!host && req.url) {
    var m = String(req.url).match(/^[a-z]+:\/\/([^\/:?#]+)/i);
    if (m) host = m[1].toLowerCase();
  }

  var hit = host ? hostMatches(host) : '';

  if (!hit && args.cidr) {
    var dst = req.dstIP || req.address || req.dst || '';
    if (dst) hit = ipMatches(String(dst));
  }

  if (args.debug) {
    console.log('[claude-rule] host=' + host + ' matched=' + (hit || '-') + ' args=' + JSON.stringify(args));
  }

  var matched = !!hit;
  if (args.done === 'bool') {
    $done(matched);
  } else {
    $done({ matched: matched });
  }
}

main();
