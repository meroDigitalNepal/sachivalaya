# sachivalaya.org

A per-MP (Member of Parliament) web presence for Nepal. Every MP gets a subdomain — `<mp>.sachivalaya.org` — serving a static info page and a `/gunaso/` ("grievance") web app where constituents can submit questions, raise complaints, and track responses. The apex domain `sachivalaya.org` serves a directory of all MPs.

## How it works

```
                          ┌─────────────────────────────┐
  browser ──────────────► │  Cloudflare (DNS + Worker)  │
  <mp>.sachivalaya.org    └──────────────┬──────────────┘
                                          │
                  /gunaso/*               │   everything else
              ┌───────────────────────────┴───────────────────────────┐
              ▼                                                         ▼
   ┌──────────────────────┐                            ┌───────────────────────────┐
   │  Azure Container App  │                            │   GitHub Pages            │
   │  (per-MP gunaso app)  │                            │   pages/<mp>/index.html   │
   └──────────────────────┘                            └───────────────────────────┘
```

A single **Cloudflare Worker** (`cloudflare-worker/worker.js`) routes every request:

- It derives the MP from the hostname (`sasmit.sachivalaya.org` → `sasmit`; the apex → `home`).
- `/gunaso` and `/gunaso/*` are reverse-proxied to that MP's **Azure Container App**. The Azure FQDN is looked up at runtime from a Cloudflare KV namespace (`MP_FQDNS`).
- Everything else is reverse-proxied to **GitHub Pages**, rewriting the path to `pages/<mp>/...`. For example, `sasmit.sachivalaya.org/photo.jpg` serves `pages/sasmit/photo.jpg` from this repo.
- `/_debug` returns JSON (`{hostname, mp, kvValue}`) for troubleshooting routing.

The static MP pages live in **this repo**. The dynamic gunaso backend lives in a separate `gunaso` repo/infrastructure.

## Repository layout

```
cloudflare-worker/
  worker.js          Routing logic (host + path → GitHub Pages or Azure)
  wrangler.toml      Worker config: KV binding, routes, GitHub Pages vars
pages/
  home/index.html    Apex landing page with the MP directory grid
  _template/index.html   Template copied to create each new MP page
  <mp>/index.html    One self-contained static page per MP
scripts/
  provision-cloudflare.sh   One-time Cloudflare setup
  add-mp.sh                 Onboard a new MP
```

Pages are intentionally dependency-free — inline CSS, no JS frameworks, no shared assets. `.nojekyll` disables Jekyll processing on GitHub Pages.

## Prerequisites

- [`wrangler`](https://developers.cloudflare.com/workers/wrangler/) — Cloudflare Workers CLI (`npm install -g wrangler`, then `wrangler login`)
- [`az`](https://learn.microsoft.com/cli/azure/) — Azure CLI (`az login`), needed to look up Container App FQDNs
- A Cloudflare account with the `sachivalaya.org` zone, and GitHub Pages enabled on this repo (Settings → Pages → Deploy from `main`)

## Running locally

There's no single "start" command — this is a static site fronted by a Cloudflare Worker, so how you run it depends on which part you're working on.

### Preview a static MP page

The pages are self-contained HTML with relative asset paths, so you can open one directly:

```bash
open pages/sasmit/index.html       # or pages/home/index.html
```

Or serve the folder over HTTP (closer to production):

```bash
cd pages/sasmit && python3 -m http.server 8000   # visit http://localhost:8000
```

The `/gunaso/` link won't work this way — in production that path is proxied by the Worker to an Azure Container App, which isn't running locally.

### Run the Cloudflare Worker

To exercise the routing logic in `worker.js`:

```bash
cd cloudflare-worker && wrangler dev   # serves at http://localhost:8787
```

Caveats:

- The Worker **proxies** to the live backends — it fetches static content from the deployed GitHub Pages site and `/gunaso/*` from the deployed Azure Container Apps. It does **not** serve your local `pages/` directory.
- Locally the hostname is `localhost`, so the MP resolves to `localhost` rather than a real MP. Hit `/_debug` to see what the Worker derived, and temporarily adjust how `mp` is computed if you need to test a specific MP's routing.

There's no local equivalent of the full stack, since the gunaso backend lives in a separate repo and Azure infrastructure.

## Setup

Run once, before onboarding any MP:

```bash
./scripts/provision-cloudflare.sh
```

This prompts for your Cloudflare credentials, then creates the `MP_FQDNS` KV namespace, patches `wrangler.toml`, adds the apex DNS record, and deploys the Worker. Save the printed `CF_*` values — they're needed by `add-mp.sh`:

```bash
export CF_API_TOKEN=...        # Zone:Edit + Workers KV:Edit
export CF_ZONE_ID=...
export CF_KV_NAMESPACE_ID=...
```

## Adding a new MP

First run the corresponding `gunaso/infra/add-mp.sh` so the MP's Azure Container App exists. Then:

```bash
./scripts/add-mp.sh <mp-name>      # e.g. ./scripts/add-mp.sh sasmit
```

This:

1. Copies `pages/_template/` to `pages/<mp>/`
2. Commits and pushes to `main` (GitHub Pages auto-deploys in ~1 minute)
3. Looks up the Azure Container App FQDN and writes it to Cloudflare KV
4. Adds a proxied CNAME DNS record for `<mp>.sachivalaya.org`

Afterward, edit the new page by hand:

- `pages/<mp>/index.html` — fill in the MP's name, role, bio, and contact details
- `pages/home/index.html` — add an `.mp-card` to the directory grid (this grid is maintained manually)

## Common commands

```bash
# Deploy the Worker after editing worker.js or wrangler.toml
cd cloudflare-worker && wrangler deploy

# Inspect / set KV mappings (subdomain → Azure FQDN)
cd cloudflare-worker && wrangler kv key list --namespace-id="$CF_KV_NAMESPACE_ID"
cd cloudflare-worker && wrangler kv key put  --namespace-id="$CF_KV_NAMESPACE_ID" <mp> <azure-fqdn>

# Debug routing for a host
curl https://<mp>.sachivalaya.org/_debug
```
