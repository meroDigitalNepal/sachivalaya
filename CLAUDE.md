# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`sachivalaya.org` is a per-MP (Member of Parliament) web presence for Nepal. Each MP gets a subdomain (`<mp>.sachivalaya.org`) serving a static info page plus a `/gunaso/` ("grievance") web app. The apex domain serves a directory landing page.

There is no build system, package manager, or test suite — the site is hand-written static HTML served from GitHub Pages, fronted by a Cloudflare Worker that does host- and path-based routing.

## Architecture

The request path is: **browser → Cloudflare (DNS + Worker) → {GitHub Pages | Azure Container App}**.

`cloudflare-worker/worker.js` is the single routing brain. For every request it derives the MP from the hostname (`<mp>.sachivalaya.org` → `mp`; the apex `sachivalaya.org` → `home`), then:
- `/gunaso` or `/gunaso/*` → reverse-proxies to that MP's Azure Container App. The Azure FQDN is looked up at runtime from the `MP_FQDNS` KV namespace (key = MP name). Returns 404 if the MP has no KV entry.
- `/_debug` → returns JSON of `{hostname, mp, kvValue}` for troubleshooting routing.
- everything else → reverse-proxies to GitHub Pages, rewriting the path to `/<repo>/pages/<mp>/...` (root `/` becomes `/index.html`). So `sasmit.sachivalaya.org/photo.jpg` serves `pages/sasmit/photo.jpg` from the repo.

This means a subdomain's static content lives at `pages/<mp>/` in this repo, while its dynamic gunaso backend lives in a **separate `gunaso` repo/infra** (referenced by the scripts but not present here).

`pages/` layout:
- `pages/home/index.html` — apex landing page; contains a hardcoded `.mp-card` grid that must be edited by hand when MPs are added.
- `pages/_template/index.html` — copied verbatim to create each new MP page. Self-contained (inline `<style>`, no shared assets). The `/gunaso/` CTA link and `photo.jpg` convention are baked in.
- `pages/<mp>/index.html` — one per MP (e.g. `pages/sasmit/`).

`.nojekyll` disables Jekyll processing on GitHub Pages.

## Adding a new MP

`scripts/add-mp.sh <mp-name>` is the primary workflow. It: (1) copies `_template` to `pages/<mp>/`, (2) commits and pushes to `main` (GitHub Pages auto-deploys), (3) looks up the MP's Azure Container App FQDN via `az` and writes it to Cloudflare KV, (4) creates a proxied CNAME DNS record. Run the corresponding `gunaso/infra/add-mp.sh` **first** so the Azure Container App exists.

After running it, manually edit `pages/<mp>/index.html` (and add a card to `pages/home/index.html`).

Required env vars: `CF_API_TOKEN`, `CF_ZONE_ID`, `CF_KV_NAMESPACE_ID`.

## Commands

```bash
# One-time Cloudflare setup (KV namespace, apex DNS, worker deploy). Prompts interactively.
./scripts/provision-cloudflare.sh

# Add an MP (see "Adding a new MP" above).
./scripts/add-mp.sh <mp-name>

# Deploy the worker after editing worker.js or wrangler.toml.
cd cloudflare-worker && wrangler deploy

# Inspect / set KV mappings manually.
cd cloudflare-worker && wrangler kv key list   --namespace-id="$CF_KV_NAMESPACE_ID"
cd cloudflare-worker && wrangler kv key put    --namespace-id="$CF_KV_NAMESPACE_ID" <mp> <azure-fqdn>
```

Prerequisites: `wrangler` (Cloudflare), `az` (Azure CLI), and `wrangler login` / `az login`.

## Conventions & gotchas

- Static pages are intentionally dependency-free: inline CSS, no JS frameworks, no shared stylesheet. Keep new pages self-contained and derived from `_template`.
- The KV namespace `id` in `wrangler.toml` is environment-specific. `provision-cloudflare.sh` patches the `REPLACE_WITH_*` placeholders; a populated `id` means setup has already run.
- The apex MP grid in `pages/home/index.html` is not generated — it must be updated by hand.
- Worker `[vars]` (`GITHUB_PAGES_HOST`, `GITHUB_PAGES_REPO`) define where static content is fetched from; changing the repo name or org requires updating both `wrangler.toml` and any DNS CNAME targets.
