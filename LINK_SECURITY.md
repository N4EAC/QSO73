# Checked message links

Click-only web opening on both clients. HTTPS only, no userinfo, non-443 explicit ports, control characters, IP literals, reserved/private hostnames, IDNs/punycode or ambiguous labels. No automatic requests are made for URLs just because they arrive.

Free malware-filtering DoH services: Cloudflare `security.cloudflare-dns.com`, Quad9 `dns.quad9.net`. Query A and AAAA in DNS wire format; verify TLS, HTTP status/MIME, DNS ID/question, lengths/compression and public addresses. Blocked/unresolvable/private/malformed responses or transport failure stop browser launch. Both providers must return a usable public resolution. macOS retries transient network errors (Quad9 can use its official 9.9.9.9 HTTPS endpoint); Windows explicitly enables WinHTTP HTTP/2 because Quad9 disabled HTTP/1.1. No TLS validation is weakened. No system DNS configuration is modified.

Only hostnames are sent to the security providers, not message contents or URL paths/query strings. Checks run independently of CAT/modem/audio work and cannot cause RF transmission. Cancellation/new clicks invalidate old results; only the latest successful user-click check opens the default browser. Windows uses Rich Edit CFE_LINK with a controlled parent handler; macOS overrides SwiftUI OpenURLAction. Neither uses an unchecked browser action.

Limits: domain reputation cannot verify full URL paths, page contents, new malicious domains, redirects, browser/system DNS differences or later DNS changes. Passing means not flagged/resolvable at check time, never a guarantee of safety.

Tests: structural URI rejection; private/malware IPv4/IPv6; positive, empty, NXDOMAIN, truncated, wrong-question and compressed-loop DNS replies; matching macOS/Windows DNS question bytes; live Cloudflare/Quad9 positive lookup without page fetching/browser opening.

References: https://developers.cloudflare.com/1.1.1.1/setup/ and https://docs.quad9.net/services/ and https://docs.quad9.net/FAQs/ and https://docs.quad9.net/Setup_Guides/Miscellaneous/Cloudflared_and_Quad9/
