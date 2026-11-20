# Flower SS — cross-client policy templates

Three variants: node-independent (minimal group skeleton), preserve-settings (keeps non-secret original Shadowrocket General/Host/Rewrite where applicable), clean (minimal configuration without MITM/Rewrite). All provide Shadowrocket, Mihomo merge/override for Clash Verge / FlClash, and Quantumult X.

**Important:** These are templates, not turnkey subscriptions. All six policy groups initially contain only DIRECT; add your node/provider selections before enabling. Mihomo YAML is a merge/override fragment, not a standalone profile. The preserve-settings variant does NOT include original private MITM certificate or passphrase, and does not preserve original 4000+ rules: it preserves safe general/rewrite settings while replacing routing rules. Quantumult X uses native filter syntax; do not paste Shadowrocket Rewrite or MITM directly.

Policy groups: YouTube, Google, OpenAI, Claude, Streaming, Global. China DIRECT via GEOIP CN (Shadowrocket additionally ChinaDomain list; other clients may need a China-domain provider for CDN accuracy). Service-specific rules precede country matching. No fixed node names.

**Security:** Never commit your original Flower_SS.conf with MITM certificate/passphrase or proxy credentials.

**Validation:** Syntax has not been tested in live clients. Check Quantumult X policy group editing and network logs after importing.