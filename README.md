# SparkyFitness — Olares App

Unofficial [Olares](https://olares.com) app package for [SparkyFitness](https://github.com/CodeWithCJ/SparkyFitness), a self-hosted, family-friendly tracker for food, exercise, water, sleep and health data — with an AI assistant and an MCP endpoint.

Upstream app: [`CodeWithCJ/SparkyFitness`](https://github.com/CodeWithCJ/SparkyFitness) — images `codewithcj/sparkyfitness` (nginx frontend) and `codewithcj/sparkyfitness_server` (Node backend), version **1.6.4**, multi-arch `amd64` + `arm64`.

> ⚠️ **Licence first, before anything else:** SparkyFitness is *source-available*, not OSI open source. The upstream licence is free for personal and self-hosted use but **restricts commercial hosting**, and derivative works carry the same terms. See [License](#license).

## What you get

- Two workloads behind your Olares entrance at `https://<md5-prefix>.<your-domain>`:
  - `sparkyfitness` — the nginx frontend (the only public entrance; listens on **8080**, because the image switches to its non-root mode under uid 1000)
  - `sparkyfitness-server` — the Node backend on `3010`, reachable in-cluster only (no entrance), proxied by nginx at `/api/`, `/uploads/` and `/mcp`
- **Database on Olares system middleware PostgreSQL** — no bundled Postgres container: the chart declares `middleware.postgres` and wires `.Values.postgres.*` into the server through a Secret. Your data gets platform-managed backups instead of a throwaway volume.
- **Generated secrets, never committed**: `SPARKY_FITNESS_API_ENCRYPTION_KEY` (AES-256-GCM key for stored provider API keys) and `BETTER_AUTH_SECRET` (session signing) are minted on first install with `lookup` + `randAlphaNum` and kept across upgrades/reinstalls (`helm.sh/resource-policy: keep`).
- Uploads, backups and temp uploads persist in the app's userspace Data volume mounted at `/data`, redirected out of the image directory via `SPARKY_FITNESS_CUSTOM_{UPLOADS,BACKUP,TEMP}_DIRECTORY`.
- Login is protected by **SparkyFitness' own auth** (better-auth). The entrance is intentionally `public` so the mobile apps and MCP clients can reach it; nothing behind it is anonymous. `GET /mcp` on the app URL is the agent endpoint, guarded by the app's API keys.
- AI chat streams over SSE and profile/food images are uploaded, so the chart sets `options.apiTimeout: 0` — without it the entrance proxy would cut those requests at its 15s default.

## Prerequisites

- An Olares machine running **Olares 1.12.6+**, logged in with your Olares ID
- [`@olares/cli`](https://www.npmjs.com/package/@olares/cli) installed and logged in:
  ```sh
  npm install -g @olares/cli@latest
  olares-cli profile login --olares-id you@example.com
  ```

## Install

1. **Get the chart package** — download `sparkyfitness-0.0.5.tgz` from this repo's [Releases](https://github.com/abidals/SparkyFitness-Olares/releases/latest), or build it yourself:
   ```sh
   git clone https://github.com/abidals/SparkyFitness-Olares && cd SparkyFitness-Olares
   olares-cli chart package ./sparkyfitness -o .
   ```

2. **Upload and install** — no required prompts; the admin email, time zone and SMTP settings are pre-filled from your Olares profile:
   ```sh
   olares-cli market upload ./sparkyfitness-0.0.5.tgz
   olares-cli market install sparkyfitness -s upload --version 0.0.5 --watch
   ```

3. **Open the app** — find its URL with `olares-cli settings apps get sparkyfitness` (URL column), then create your account. **The first account created becomes the admin.**

4. **Close registration** once every household account exists: Settings → Applications → SparkyFitness → Manage environment variables → set `SPARKY_FITNESS_DISABLE_SIGNUP=true` and save (the app restarts). Do it from the Settings UI — see [Editing environment variables](#editing-environment-variables).

## Configuration (Settings → Applications → Manage environment variables)

| Variable | Default | Purpose |
|---|---|---|
| `SPARKY_FITNESS_ADMIN_EMAIL` | your Olares account email (`OLARES_USER_EMAIL`) | Which email sees the in-app admin panel. Read-only here — change it in Olares profile settings, or override by editing this app's env after install. |
| `TZ` | your Olares time zone (`OLARES_USER_TIMEZONE`) | Day boundaries for check-ins, diary and reports. |
| `SPARKY_FITNESS_DISABLE_SIGNUP` | `false` | **Master** signup blockade. It blocks *all* account creation — including the very first account — so leave it `false` until your accounts exist, then flip it to `true`. |
| `SPARKY_FITNESS_LOG_LEVEL` | `ERROR` | Server log level: `error`, `warn`, `info`, `http`, `debug`. |
| `ALLOW_PRIVATE_NETWORK_CORS` | `false` | Only needed if you reach the app over a LAN address instead of its Olares domain. |
| `SPARKY_FITNESS_EXTRA_TRUSTED_ORIGINS` | empty | Extra comma-separated CORS origins beyond the entrance URL. |
| `SMTP_HOST/PORT/USERNAME/PASSWORD/FROM_ADDRESS/SECURE` | inherited from Olares Settings → SMTP | Outbound email (invites, password reset). Empty keeps mail disabled. |

All editable values use `applyOnChange: true`, so saving restarts the affected workload for you.

### Editing environment variables

Use **Settings → Applications → SparkyFitness → Manage environment variables**. The `valueFrom`-mapped entries (admin email, time zone, SMTP) are read-only by design; `olares-cli settings apps env set` currently re-sends those read-only entries in its update payload and the API rejects the whole request (`app env '…' is not editable`), so edits belong in the UI.

## Notes

- **One database role instead of two.** Upstream wants a migration-owner role (`SPARKY_FITNESS_DB_USER`, needs `CREATEROLE`) plus a restricted app role (`SPARKY_FITNESS_APP_DB_USER`). A system-middleware role has no `CREATEROLE`, so this chart points both at the single injected middleware user. Consequence: that user owns the tables, and since upstream does not set `FORCE ROW LEVEL SECURITY`, its RLS policies act as defence-in-depth only when a non-owner connects — isolation between household accounts is enforced by application queries here. Acceptable for one household on your own box; call it out if you are multi-tenanting.
- **Your data lives in system PostgreSQL, not in the app volume.** Uninstalling the app removes the workloads but not the database or role. Back up from inside SparkyFitness (writes to `/data/backup`) and export your data before uninstalling for good.
- **Garmin Connect sync is deliberately not included.** Upstream ships it as an optional microservice still marked WIP, so this package omits `sparkyfitness-garmin` and never sets `GARMIN_MICROSERVICE_URL`. Other integrations (Apple Health, Health Connect, Fitbit, Withings, Polar, Oura, Hevy, Strava…) work without it.
- **Frontend runs non-root.** uid 1000 makes the image pick port 8080 and stdout/stderr logs; its pid file lands in `/run`, which is not writable for uid 1000, so the chart mounts an `emptyDir` there and prepares it with a root `init-permissions` container.
- Resource envelope: `requiredCpu 300m / limitedCpu 1500m`, `requiredMemory 512Mi / limitedMemory 1600Mi`.

## Updating the app

When upstream ships a new release, bump **all four** places (`image:` tags in both templates, `appVersion` in `Chart.yaml`, and `version` in `Chart.yaml` + `OlaresManifest.yaml` must stay equal), then:

```sh
olares-cli chart lint ./sparkyfitness
olares-cli chart package ./sparkyfitness -o .
olares-cli market upload ./sparkyfitness-<new-version>.tgz
olares-cli market upgrade sparkyfitness -s upload --version <new-version> --watch
```

Your accounts, generated keys and data survive the upgrade. Publish the new package as a GitHub release so others get it too:

```sh
git add -A && git commit -m "bump to <upstream version>" && git push
gh release create v<new-version> ./sparkyfitness-<new-version>.tgz --latest
```

## Repo layout

```
sparkyfitness/            # the Olares chart (OlaresManifest.yaml + templates/)
compose.yml               # upstream docker-compose.prod.yml this chart was ported from
sparkyfitness-0.0.5.tgz   # pre-built chart package (what `market upload` consumes)
```

## License

The SparkyFitness application is **source-available and non-commercial** ([upstream LICENSE](https://github.com/CodeWithCJ/SparkyFitness/blob/main/LICENSE)): free to use, copy, modify and distribute for non-commercial purposes; derivative works carry the same terms and must keep the copyright notice. Commercial hosting requires the author's written permission — see [their explanation](https://codewithcj.github.io/SparkyFitness/features/comparison).

This packaging repo makes no separate licence claim on the application itself, and is intended for personal self-hosting on your own Olares device.
