#!/usr/bin/env bash
# One-time Cloudflare setup for sachivalaya.org.
# Run this once before running add-mp.sh for the first time.
#
# Prerequisites:
#   npm install -g wrangler
#   wrangler login
#   brew install azure-cli   (for az, needed by add-mp.sh)

set -euo pipefail

WORKER_DIR="$(cd "$(dirname "$0")/../cloudflare-worker" && pwd)"

echo "=== sachivalaya: Cloudflare one-time setup ==="
echo ""
read -rsp "Cloudflare API Token (dash.cloudflare.com → My Profile → API Tokens): " CF_API_TOKEN
echo ""
read -rp "Cloudflare Account ID (dash.cloudflare.com → right sidebar): " CF_ACCOUNT_ID
read -rp "Cloudflare Zone ID   (dash.cloudflare.com → sachivalaya.org → Overview): " CF_ZONE_ID
read -rp "GitHub org or username (e.g. meroDigitalNepal): " GITHUB_ORG

# 1. Create KV namespace
echo ""
echo "→ [1/3] Creating KV namespace..."
KV_OUTPUT=$(wrangler kv namespace create "gunaso-mp-fqdns" 2>&1)
echo "$KV_OUTPUT"
KV_NAMESPACE_ID=$(echo "$KV_OUTPUT" | grep -oE '"id": "[^"]+"' | head -1 | grep -oE '[0-9a-f]{32}')
if [[ -z "$KV_NAMESPACE_ID" ]]; then
  echo ""
  echo "Could not auto-detect KV namespace ID from output above."
  read -rp "Paste the KV namespace ID manually: " KV_NAMESPACE_ID
fi
echo "   KV namespace ID: $KV_NAMESPACE_ID"

# 2. Patch wrangler.toml
echo ""
echo "→ [2/3] Updating wrangler.toml..."
sed -i.bak \
  -e "s|REPLACE_WITH_KV_NAMESPACE_ID|${KV_NAMESPACE_ID}|g" \
  -e "s|REPLACE_WITH_GITHUB_ORG|${GITHUB_ORG}|g" \
  "${WORKER_DIR}/wrangler.toml"
rm "${WORKER_DIR}/wrangler.toml.bak"
echo "   Done."

# 3. Add apex domain A record (proxied — Cloudflare intercepts before the IP is hit)
echo ""
echo "→ [3/4] Adding sachivalaya.org A record..."
DNS_RESULT=$(curl -s -X POST \
  "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H "Content-Type: application/json" \
  --data '{"type":"A","name":"@","content":"192.0.2.1","proxied":true,"comment":"Apex — Cloudflare Worker intercepts before this IP is reached"}')
echo "$DNS_RESULT" | python3 -c "
import sys, json
r = json.load(sys.stdin)
if r.get('success'):
    print('   A record created for sachivalaya.org.')
else:
    errs = r.get('errors', [])
    if any('already exists' in str(e) for e in errs):
        print('   (A record already exists, skipping)')
    else:
        print('   Warning:', errs)
"

# 4. Deploy Worker
echo ""
echo "→ [4/4] Deploying Cloudflare Worker..."
(cd "$WORKER_DIR" && wrangler deploy)

echo ""
echo "✅ Cloudflare setup complete."
echo ""
echo "Save these in your password manager — needed by add-mp.sh:"
echo "  CF_ACCOUNT_ID     : $CF_ACCOUNT_ID"
echo "  CF_ZONE_ID        : $CF_ZONE_ID"
echo "  CF_KV_NAMESPACE_ID: $KV_NAMESPACE_ID"
echo ""
echo "Export them before running add-mp.sh:"
echo "  export CF_ACCOUNT_ID=$CF_ACCOUNT_ID"
echo "  export CF_ZONE_ID=$CF_ZONE_ID"
echo "  export CF_KV_NAMESPACE_ID=$KV_NAMESPACE_ID"
echo ""
echo "Next: enable GitHub Pages on this repo in Settings → Pages → Deploy from branch: main"
