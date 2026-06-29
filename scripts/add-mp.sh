#!/usr/bin/env bash
# Add a new MP to sachivalaya.org.
# Run this after gunaso/infra/add-mp.sh has been run for the same MP.
#
# Usage:
#   ./scripts/add-mp.sh <mp-name>
#
# Example:
#   ./scripts/add-mp.sh john
#
# Required env vars (set once, e.g. in ~/.zshrc):
#   CF_API_TOKEN       — Cloudflare API token (Zone:Edit + Workers KV:Edit)
#   CF_ZONE_ID         — Zone ID for sachivalaya.org
#   CF_KV_NAMESPACE_ID — KV namespace ID from provision-cloudflare.sh
#
# What this script does:
#   1. Creates pages/<mp>/ from the template
#   2. Commits and pushes (GitHub Pages auto-updates)
#   3. Registers the Azure Container App FQDN in Cloudflare KV
#   4. Adds a proxied CNAME DNS record in Cloudflare

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <mp-name>"
  echo "  Example: $0 john"
  exit 1
fi

MP="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ─── Check required env vars ─────────────────────────────────────────────────
for var in CF_API_TOKEN CF_ZONE_ID CF_KV_NAMESPACE_ID; do
  if [[ -z "${!var:-}" ]]; then
    echo "Error: \$$var is not set."
    echo "Run provision-cloudflare.sh first, then export these vars."
    exit 1
  fi
done

# ─── Must match gunaso/infra/provision-shared.sh ─────────────────────────────
AZURE_RESOURCE_GROUP="gunaso-rg"
AZURE_CONTAINER_APP="gunaso-${MP}"
# ─────────────────────────────────────────────────────────────────────────────

echo "=== Adding MP page: ${MP}.sachivalaya.org ==="
echo ""

# 1. Create pages/<mp>/ from template ─────────────────────────────────────────
echo "→ [1/4] Creating pages/${MP}/..."
PAGES_DIR="${REPO_ROOT}/pages/${MP}"
if [[ -d "$PAGES_DIR" ]]; then
  echo "   (already exists, skipping)"
else
  cp -r "${REPO_ROOT}/pages/_template" "$PAGES_DIR"
  echo "   Created from template. Edit pages/${MP}/index.html with this MP's details."
fi

# 2. Commit and push ──────────────────────────────────────────────────────────
echo "→ [2/4] Committing and pushing..."
cd "$REPO_ROOT"
git add "pages/${MP}"
git diff --cached --quiet && echo "   (no changes to commit)" || \
  git commit -m "add page for ${MP}"
git push origin main

# 3. Register Azure FQDN in Cloudflare KV ─────────────────────────────────────
echo "→ [3/4] Looking up Azure Container App FQDN..."
AZURE_FQDN=$(az containerapp show \
  --name "$AZURE_CONTAINER_APP" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query "properties.configuration.ingress.fqdn" -o tsv 2>/dev/null || true)

if [[ -z "$AZURE_FQDN" ]]; then
  echo "   Warning: Container App '$AZURE_CONTAINER_APP' not found."
  echo "   Run gunaso/infra/add-mp.sh first, or set the FQDN manually:"
  read -rp "   Azure Container App FQDN: " AZURE_FQDN
fi
echo "   FQDN: $AZURE_FQDN"

echo "   Writing to Cloudflare KV..."
curl -s -X PUT \
  "https://api.cloudflare.com/client/v4/accounts/$(wrangler whoami 2>/dev/null | grep -oE 'account ID "[^"]+"' | grep -oE '[0-9a-f-]{36}' || echo 'unknown')/storage/kv/namespaces/${CF_KV_NAMESPACE_ID}/values/${MP}" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -d "$AZURE_FQDN" \
  --output /dev/null
# Fallback: use wrangler if curl account ID lookup fails
(cd "${REPO_ROOT}/cloudflare-worker" && \
  wrangler kv key put --namespace-id="$CF_KV_NAMESPACE_ID" "$MP" "$AZURE_FQDN" 2>/dev/null) || true

# 4. Add Cloudflare DNS CNAME ─────────────────────────────────────────────────
echo "→ [4/4] Adding Cloudflare DNS record..."
GITHUB_PAGES_HOST=$(grep 'GITHUB_PAGES_HOST' "${REPO_ROOT}/cloudflare-worker/wrangler.toml" \
  | grep -oE '"[^"]+"' | tr -d '"')

DNS_RESULT=$(curl -s -X POST \
  "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H "Content-Type: application/json" \
  --data "{\"type\":\"CNAME\",\"name\":\"${MP}\",\"content\":\"${GITHUB_PAGES_HOST}\",\"proxied\":true}")

echo "$DNS_RESULT" | python3 -c "
import sys, json
r = json.load(sys.stdin)
if r.get('success'):
    print('   DNS record created.')
else:
    errs = r.get('errors', [])
    if any('already exists' in str(e) for e in errs):
        print('   (DNS record already exists, skipping)')
    else:
        print('   Warning:', errs)
"

echo ""
echo "✅ ${MP}.sachivalaya.org is set up."
echo ""
echo "GitHub Pages will update in ~1 minute."
echo "Edit the info page: pages/${MP}/index.html"
echo "Gunaso app:         https://${MP}.sachivalaya.org/gunaso/"
