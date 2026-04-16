# HealthOS Installer — System Architecture

**Purpose:** Reference for any Claude instance working on this codebase. Read this before touching anything. Explains every file's role, the full install flow, and how the installer reaches customers.
**Last mapped:** 2026-04-16

## GitHub Repositories — What Each One Is

Three repos. They are completely separate and serve different purposes.

| Repo | Purpose | What auto-deploys from it | Local path |
|---|---|---|---|
| `yostai/HealthOS-Sales` | Customer-facing download site. Hosts the code-gated download page, validate-code.js Netlify function, and setup guide. | Netlify → `startling-biscuit-e614db.netlify.app` | `/Users/pyost/PY Clients/Yost Advantage Inc/HealthOS/HealthOS-Sales` |
| `yostai/HealthOS-Installer` | Dev workspace for the installer. Where installer changes are made, tested, and tracked. Source of truth for INSTALL.md, scripts, and setup guide HTML. | Nothing — changes must be manually ZIPped and uploaded to S3 | `/Users/pyost/PY Clients/Yost Advantage Inc/HealthOS/HealthOS-Installer` (this folder) |
| `yostai/HealthOS-Clean` | Production copy of the HealthOS application (the AI health coach bot that runs on the customer's Lightsail server). Pushed to this repo triggers GitHub Actions → deploys to Paul's Lightsail instance. | GitHub Actions → Lightsail (auto-deploys on push) | `/Users/pyost/PY Clients/Yost Advantage Inc/HealthOS/HealthOS-Cloud` |

**Common confusion points:**
- `HealthOS-Installer` and `HealthOS-Clean` are different things. The installer deploys *onto* a Lightsail server; `HealthOS-Clean` is the app code *running on* that server.
- `HealthOS-Sales` is entirely separate from both — it's the pre-purchase web property, not part of the installer or the app.
- Pushing to `HealthOS-Installer` does not deploy anything. Only `HealthOS-Sales` (→ Netlify) and `HealthOS-Clean` (→ Lightsail) have auto-deploy pipelines.

---

## Who Does What — Roles After a Change

**Claude does** (all coding, commits, and pushes — with Paul's explicit approval before any push):
- All code modifications: `INSTALL.md`, scripts, `validate-code.js`, HTML files, config templates, documentation
- Building the installer ZIP (bash command run locally)
- Pushing to `yostai/HealthOS-Sales` → Netlify auto-deploys from there
- Pushing to `yostai/HealthOS-Installer` (version control / record keeping)
- Pushing to `yostai/HealthOS-Clean` → GitHub Actions auto-deploys to Lightsail

**Paul does** (actions that require external system access Claude doesn't have):
- Upload the rebuilt `healthos-installer.zip` to S3 (AWS Console or CLI)
- Modify Make scenarios (Make account access required)

**Auto-happens** (no action required from either):
- Netlify deploys after every push to `yostai/HealthOS-Sales`
- GitHub Actions deploys to Lightsail after every push to `yostai/HealthOS-Clean`

### Change Playbooks

**When `validate-code.js` or download page changes:**
1. Claude edits files in `HealthOS-Sales/`
2. Paul approves → Claude commits + pushes to `yostai/HealthOS-Sales`
3. Netlify auto-deploys ✓

**When `INSTALL.md`, scripts, or any installer file changes:**
1. Claude edits files in `HealthOS-Installer/`
2. Claude deletes any existing ZIP first (`rm /tmp/healthos-installer.zip`), then rebuilds clean — `zip -r` updates an existing ZIP and can leave stale files in place
3. ⚠️ **Paul uploads the ZIP to S3** (replaces existing `healthos-installer.zip`) — **customers run the old installer until this is done**
4. Paul approves git push → Claude commits + pushes to `yostai/HealthOS-Installer`

**When `HealthOS-Setup-Guide.html` changes:**
1. Claude edits `HealthOS-Installer/HealthOS-Setup-Guide.html` (source of truth)
2. Claude copies to `HealthOS-Sales/setup-guide.html`
3. Paul approves → Claude pushes both repos
4. Netlify auto-deploys the updated guide ✓

**When Make scenarios need changes:**
1. Paul updates the scenario in Make directly
2. No code changes required unless webhook URLs change (update `installer-config.txt` if so)

---

## ⚠️ SINGLE SOURCE OF TRUTH

**There is ONE installer source:**
```
/Users/pyost/PY Clients/Yost Advantage Inc/HealthOS/HealthOS-Installer
```
All changes go here. All ZIPs are built from here. Do not look for, create, or port to any other copy. Any references in this document to a "distribution copy" or `module-installs/healthos-installer/` are outdated and wrong — ignore them.

**This includes the customer-facing setup guide HTML:**
```
HealthOS-Installer/HealthOS-Setup-Guide.html  ← single source of truth
```
When this file is updated, copy it to `HealthOS-Sales/setup-guide.html` and push both repos. Do not edit `setup-guide.html` in the HealthOS-Sales repo directly — always edit the installer copy first.

The `images/` folder is also shared. If any image is added or changed in `HealthOS-Installer/images/`, copy it to `HealthOS-Sales/images/` as well.

---

## ⚠️ CRITICAL — ZIP Must Be Rebuilt After Any Installer Change

**The S3 ZIP is what customers actually download and run. It is NOT updated automatically.**

Pushing to `yostai/HealthOS-Installer` does NOT update the customer ZIP. Changing `INSTALL.md`, any script, or any installer file only takes effect for customers after:
1. The ZIP is rebuilt from this folder
2. Paul uploads it to S3 (replaces the existing `healthos-installer.zip`)

**If you skip this, customers run the old installer.** Changes to `INSTALL.md` — including security gates like the download code validation — will be completely absent from what customers execute.

This has caused at least one live incident (2026-04-16): download code gate was implemented in INSTALL.md but ZIP was never rebuilt, so customers downloaded and ran the old installer without the gate.

**Every time any of these files change, the ZIP must be rebuilt:**
- `INSTALL.md`
- Any file in `scripts/`
- `installer-config.txt`
- `install-state.json`
- `CLAUDE.md` (installer copy)
- `README.md`
- `.claude/commands/install.md`

---

## Deployment Structure

How the installer reaches customers and how updates get published.

**There are two separate GitHub repos and two separate deployment targets:**

```
GitHub: yostai/HealthOS-Sales
    → Netlify auto-deploys on every push
    → Live URL: https://startling-biscuit-e614db.netlify.app
    → Serves: download-page.html (code-gated customer download page)
    → Serves: setup-guide.html (visual setup instructions)
    → Runs: netlify/functions/validate-code.js (serverless download gate)
    → Local copy: /Users/pyost/PY Clients/Yost Advantage Inc/HealthOS/HealthOS-Sales

GitHub: yostai/HealthOS-Installer (this workspace)
    → NOT connected to Netlify — source of truth for the installer only
    → Changes here require manual ZIP rebuild + S3 upload to reach customers

S3 bucket
    → Holds: healthos-installer.zip (the installer customers download)
    → URL generated on-demand as a signed URL by validate-code.js (1-hour expiry)
    → Direct S3 URL is never exposed to customers
```

**Three separate update actions are required when things change:**

| What changed | Action required |
|---|---|
| `HealthOS-Setup-Guide.html` (visual guide) | 1. Edit in `HealthOS-Installer/` (source of truth) → 2. Copy to `HealthOS-Sales/setup-guide.html` → 3. Push `yostai/HealthOS-Sales` → Netlify auto-deploys |
| `download-page.html` or `validate-code.js` | Edit in `HealthOS-Sales/` → push `yostai/HealthOS-Sales` → Netlify auto-deploys |
| Any script, `INSTALL.md`, or any file in the installer | Rebuild `healthos-installer.zip` → upload to S3 |

Pushing to `yostai/HealthOS-Installer` does NOT update anything customer-facing. Only `yostai/HealthOS-Sales` pushes trigger Netlify.

---

## HealthOS-Sales Customer Site

**What it is:** The customer-facing web property. Handles everything from purchase to download hand-off. Completely separate from the installer codebase.

**Local path:** `/Users/pyost/PY Clients/Yost Advantage Inc/HealthOS/HealthOS-Sales`
**GitHub:** `yostai/HealthOS-Sales`
**Netlify URL:** `https://startling-biscuit-e614db.netlify.app`

**Files:**

| File | Purpose |
|---|---|
| `download-page.html` | Customer-facing download page. Accepts `?code=` URL param (auto-fills input). Calls `validate-code.js` on submit. On success: triggers ZIP download + shows setup guide link. |
| `setup-guide.html` | Visual setup instructions. Copied from `HealthOS-Installer/HealthOS-Setup-Guide.html` — do not edit here directly. |
| `netlify/functions/validate-code.js` | Serverless Netlify function. Validates download code against Airtable, checks expiry + download count, generates a signed S3 URL (1-hour expiry). Returns `{ url: signedUrl }` on success. |
| `images/` | UI screenshots shared with the installer setup guide. |

**Airtable Licenses table** (used by `validate-code.js` and Make webhooks):

| Field | Type | Purpose |
|---|---|---|
| `Code` | Text | The download code (UUID format) |
| `Status` | Text | `active` / `inactive` — set by Make |
| `Expires At` | Date | Optional expiry date — checked by validate-code.js |
| `Downloads` | Number | Count of successful installs — incremented by Make INCREMENT webhook |
| `MaxDownloads` | Number | Per-license install limit — used by validate-code.js instead of hardcoded limit |
| `EULA Accepted At` | DateTime | ⚠️ **Not yet implemented.** Recommended: capture timestamp when customer completes purchase. Set by Make at purchase time alongside Code/Status. Provides auditable proof of EULA acceptance tied to the specific license record. |

**What `validate-code.js` does NOT do:**
- Does not increment the `Downloads` counter (the installer handles this at install completion via Make)
- Does not check `Status` field (Make's CONFIRM webhook handles status; Airtable may not update Status on expiry)

---

## Complete Purchase-to-Install Flow

```
1. Customer completes Stripe purchase
       ↓
2. Stripe fires webhook → Make scenario (PY HealthOS Purchase)
       → Creates new record in Airtable Licenses table
         (Code = UUID, Status = active, MaxDownloads = 3, Expires At = +90 days)
       → Sends customer email with download link:
         https://startling-biscuit-e614db.netlify.app/download-page.html?code={uuid}
       ↓
3. Customer opens download link in browser
       → download-page.html loads, auto-fills code from ?code= param
       → Customer clicks "Download Installer"
       ↓
4. validate-code.js (Netlify function) runs
       → Looks up code in Airtable
       → Checks: code exists / not expired / Downloads < MaxDownloads
       → Generates signed S3 URL (1-hour expiry)
       → Returns { url: signedUrl } to browser
       ↓
5. Browser triggers download of healthos-installer.zip from S3
       → Customer unzips, opens folder in Claude desktop, runs /install
       ↓
6. INSTALL.md Phase 0 Step 1 — Second validation gate (installer-side)
       → Claude prompts for download code
       → Calls MAKE_CONFIRM_WEBHOOK (read-only) with the code
       → Make looks up Airtable: returns { status, reason, downloads, max }
       → If status = "ok": installation proceeds
       → If status = "deny": installation stops with reason shown to customer
       ↓
7. Install proceeds through Phases 1–7
       ↓
8. Install Complete — increment call (fire-and-forget)
       → Claude calls MAKE_INCRDOWNLOADS_WEBHOOK with the code
       → Make increments Downloads counter in Airtable
       → Install outcome is NOT gated on this succeeding
```

**Two-layer gate architecture:**

| Layer | Where | What it checks | What it controls |
|---|---|---|---|
| Layer 1 — Download Gate | Netlify `validate-code.js` | Code exists, not expired, Downloads < MaxDownloads | Access to the installer ZIP |
| Layer 2 — Install Gate | `INSTALL.md` Phase 0 via Make CONFIRM | Code status (active/inactive/expired/limit) | Whether installation actually proceeds |

A customer who downloads the ZIP but doesn't complete install is not counted. Only successful installs increment the counter.

---

### ZIP Build — Include/Exclude List

ZIP filename: `healthos-installer.zip`
Built from: `/Users/pyost/PY Clients/Yost Advantage Inc/HealthOS/HealthOS-Installer`

**Excluded from ZIP:**

| File/Folder | Reason |
|---|---|
| `.git/` | Git internals — not needed by customers |
| `.gitignore` | Dev tooling only |
| `INSTALLER-DEV-NOTES.md` | Internal issue tracker — not for customers |
| `categories-preferences-data.txt` | Dev reference — not used during install |
| `reference/` | Internal dev docs |
| `scripts/reboot_healthos.py` | Post-install maintenance tool — not part of install flow |

**Everything else is included**, including `installer-config.txt` (customers need the GitHub URL to clone HealthOS during install).

---

## What This Workspace Is

This is the **source workspace** for the HealthOS Installer — the place where all changes are made, tested, and tracked. The customer ZIP is built from here and uploaded to S3.

**Do not confuse with:**
- `yostai/HealthOS-Sales` on GitHub — the customer-facing Netlify site (download page, validate-code.js, setup guide). Completely separate repo. Local copy: `HealthOS-Sales/`.
- `yostai/HealthOS-Installer` on GitHub — the remote for *this* dev workspace. Not connected to Netlify.

**Change flow:**
```
HealthOS-Installer/ (this workspace — dev)
    → changes made + tested here
    → ZIP rebuilt → uploaded to S3 (customer download)
```

Changes in this workspace do NOT automatically appear in the customer ZIP. ZIP rebuild and S3 upload are deliberate manual steps.

---

## What the Installer Does

Claude-orchestrated setup that deploys a personal AI health coach onto the customer's own AWS Lightsail server. The customer opens this folder in Claude desktop, types `/install`, and Claude drives the entire setup — running bash scripts, collecting credentials, configuring AWS, and deploying the bot — without the customer ever opening a terminal.

**Result:** Ubuntu 24.04 server on AWS Lightsail ($7/month) running a Telegram bot as a systemd service, with cron jobs for health check-ins and nightly S3 backup.

---

## Entry Point

### `/install` slash command
**File:** `.claude/commands/install.md`
**Trigger:** User types `/install` in Claude desktop Code tab
**What it does:** Tells Claude to read `INSTALL.md` in full and execute it from the beginning. Confirms user has Telegram and Anthropic API key before starting.
**Hands off to:** `INSTALL.md`

---

## Orchestration Layer

### `INSTALL.md`
**Role:** The brain of the installer. Claude reads this as a script and follows it step by step. Not executable code — a structured natural language document that Claude treats as authoritative instructions.

**Phases in order:**

| Phase | What happens | Script |
|---|---|---|
| Pre-Install Steps | Telegram, Anthropic key, AWS account — interactive, one at a time | None |
| Phase 0 Step 1 | Download code validation via Make CONFIRM webhook — gate before any install work | None (curl) |
| Phase 0 | Instance name, read GitHub URL from config, init state file (includes `download_code`) | None |
| Phase 1 | Mac preflight: check AWS CLI, verify credentials | `01-preflight.sh` |
| Human Step 2 | User creates IAM user + access key in AWS Console | None |
| Phase 2 | Lightsail instance, SSH key, static IP, SSH config | `02-aws.sh` |
| Phase 3A | S3 backup bucket + IAM backup user + access key | `03-backup-infra.sh` |
| Phase 3B | Capture Telegram bot token + group ID | `03-telegram.sh` |
| Phase 4 | Clone HealthOS from GitHub, write `.env` on server | `04-workspace.sh` |
| Phase 5 | apt update/upgrade, base packages, swap, reboot | `05-server-a.sh` |
| Phase 6 | Node.js, Claude Code, Python venv, crontab, systemd | `06-server-b.sh` |
| Phase 7 | 13-point verification suite + Telegram confirmation | `07-verify.sh` |
| Complete | Fire-and-forget increment via Make INCREMENT webhook, completion message, write install log | None (curl) |

**Note:** This workspace's INSTALL.md has 13 checks in Phase 7. The customer ZIP may have fewer if it hasn't been rebuilt recently — see Dev vs. Customer ZIP table below.

---

## Full File Map

### `scripts/01-preflight.sh`
**When:** Phase 1
**What it does:** Checks AWS CLI installed, checks `~/.aws/` credentials exist, calls `aws sts get-caller-identity` to validate. If AWS CLI missing, downloads the `.pkg` and instructs user to install (requires sudo — cannot be automated). Outputs `PREFLIGHT_OK=true` and `AWS_ACCOUNT_ID` which Claude uses to derive the backup bucket name.
**In customer ZIP:** Yes (as of last ZIP build).

---

### `scripts/02-aws.sh`
**When:** Phase 2
**What it does:** Creates Lightsail SSH key pair (`.pem` → `~/.ssh/`), creates Lightsail instance (Ubuntu 24.04, 1GB, us-east-1a), waits for running state, allocates + attaches static IP, closes port 80, writes SSH config entry, waits for SSH.
**Outputs:** `STATIC_IP`, `PEM_PATH`, `SSH_HOST`, `INSTANCE_NAME`
**Idempotent:** Every creation step guards "already exists."
**In customer ZIP:** Yes (as of last ZIP build).

---

### `scripts/03-backup-infra.sh`
**When:** Phase 3A
**What it does:** Creates S3 backup bucket (public access blocked), creates IAM backup user, attaches `AmazonS3FullAccess` policy, creates access key.
**Robustness fix (2026-04-08):** Before creating access key, checks existing key count. If 2 exist (IAM limit), auto-deletes the oldest. User never sees `LimitExceeded` on resume.
**Outputs:** `S3_BUCKET`, `AWS_BACKUP_KEY_ID`, `AWS_BACKUP_SECRET`
**In customer ZIP:** Missing the IAM key auto-delete guard — not yet included in a ZIP build.

---

### `scripts/03-telegram.sh`
**When:** Phase 3B
**What it does:** Calls Telegram `getUpdates` API, parses JSON to find a group chat ID (negative number), retries 3× with 10s waits. Calls `getMe` for bot @username.
**Outputs:** `TELEGRAM_GROUP_ID`, `BOT_USERNAME`
**In customer ZIP:** Yes (as of last ZIP build).

---

### `scripts/04-workspace.sh`
**When:** Phase 4
**What it does:** Installs git on server if missing, clones HealthOS from GitHub (URL from session memory — read from `installer-config.txt` in Phase 0), writes `.env` to server via SSH heredoc, `chmod 600`, updates backup script with bucket name, verifies 5 key files present.
**URL quoting fix (2026-04-06):** `$GITHUB_REPO_URL` assigned to `REPO_URL` inside the remote shell string — prevents early quote termination if token contains shell-special characters.
**In customer ZIP:** Yes (as of last ZIP build).

---

### `scripts/05-server-a.sh`
**When:** Phase 5
**What it does:** `apt update` + `apt upgrade`, installs base packages (Python 3.12 venv, build tools, Pango/GDK for Playwright, curl, wget, awscli), creates 2GB swap file, reboots, waits for SSH.
**Robustness fix (2026-04-08):** Swap creation wrapped in `if [ ! -f /swapfile ]` — idempotent on resume, prints SKIP instead of failing.
**Outputs:** `SERVER_A_OK=true`
**In customer ZIP:** Missing swap guard — not yet included in a ZIP build.

---

### `scripts/06-server-b.sh`
**When:** Phase 6 — must run after Phase 5 (post-reboot)
**What it does:** Installs Node.js 22, Claude Code, Python venv + all dependencies (anthropic, claude-agent-sdk, aiogram, python-telegram-bot, requests, python-dotenv, playwright, aiohttp, aiofiles), Playwright Chromium, sets timezone, configures `~/.aws/credentials` on server, installs crontab, installs + starts `healthos-bot` systemd service.

**Robustness fixes (2026-04-08):**
- Node.js pipe: added `set -o pipefail` — CDN failures now propagate instead of silently exiting 0
- Node.js version check: if not v22+ after install, auto-removes, retries once; fails loudly if both attempts fail with "try again in a few minutes" — no user action required
- Bot startup wait: `BOT_MAX` 5 → 20 (15s → 60s total); user-facing message before wait loop

**Outputs:** `SERVER_B_OK=true`
**Named `06-server-b.sh`** (was `05-server-b.sh` — renumbered 2026-04-08 to match phase number).
**In customer ZIP:** Missing Node.js pipe fix, auto-retry, and 60s bot wait — not yet included in a ZIP build. ZIP copy still named `05-server-b.sh`.

---

### `scripts/07-verify.sh`
**When:** Phase 7
**What it does:** Runs 13 checks, prints pass/fail table, prints exact fix commands for failures.

| Check | What it verifies |
|---|---|
| 1 | SSH connection |
| 2 | Python imports: anthropic, aiogram, dotenv |
| 3 | Claude Code installed |
| 4 | Timezone = America/New_York |
| 5 | Port 80 closed |
| 6 | `healthos-bot` systemd service active |
| 7 | 6+ crontab entries installed |
| 8 | `.env` exists with 600 permissions |
| 9 | Swap: 2GB active (`swapon --show`) |
| 10 | `apps/command/__main__.py` exists |
| 11 | `apps.command` module importable |
| 12 | Telegram: bot connected + sends install confirmation message |
| 13 | Node.js 22+ installed |

**Check 12 (Telegram):** Sends `sendMessage` API call directly — no agent, no cost. Message: "✅ HealthOS is installed and connected. Congratulations on your new HealthOS Coach. When you are ready to set up your coach, please type 'setup' here." Validates token + group ID connectivity and gives customer visible proof.

**Named `07-verify.sh`** (was `06-verify.sh` — renumbered 2026-04-08).
**In customer ZIP:** Missing swap check, split __main__ checks, and direct sendMessage — not yet included in a ZIP build. ZIP copy still named `06-verify.sh` with 11 checks and uses `health_notify.py` for Telegram test.

---

### `scripts/reboot_healthos.py`
**When:** Post-install, on demand — not part of the install flow
**What it does:** Lets Paul (or a customer) reboot their Lightsail instance from their Mac without opening the AWS Console.
1. Reads instance name from `install-state-{name}.json` automatically
2. If not found, prompts for instance name
3. Calls `aws lightsail reboot-instance`
4. Polls instance state every 10s for up to 100 seconds, reports when running
**Uses:** AWS credentials already configured during install (`~/.aws/credentials`)
**Not included in customer ZIP** — dev/internal only.

---

### `INSTALLER-DEV-NOTES.md`
**Role:** Issue tracker for the installer. Each known bug or improvement is documented with: what happens to the user, auto-recovery potential, proposed solution, and status (Open/Resolved).
**Not a customer-facing file** — dev reference only.
**Not included in customer ZIP** — dev/internal only.

---

### `CHANGELOG.md`
**Role:** Running log of changes made to this dev workspace, most recent at top.
**Not a customer-facing file** — dev reference only.
**Not included in customer ZIP** — dev/internal only. Customer ZIP has its own CHANGELOG (created 2026-04-13).

---

### `categories-preferences-data.txt`
**Role:** Reference data for the HealthOS onboarding interview — full branching logic for diet types, workout preferences, mental health categories, complications, motivation styles, and check-in schedule options.
**Used by:** The onboarding interview agent in HealthOS-TEST, not directly by the installer scripts.
**Why it's here:** Kept alongside the installer workspace for reference during onboarding-related installer development. Mirrors the copy in `HealthOS-TEST/onboarding/reference/`.
**Not included in customer ZIP** — dev/internal only.

---

### `install-state.json`
**Role:** Template for per-install state file. Copied at Phase 0 to `install-state-{instance-name}.json`. Tracks completed phases and non-secret config values, including `download_code` (first field in config section — persists code for resume validation).
**Identical in both copies.**

---

### `HealthOS-Setup-Guide.html`
**Role:** Visual step-by-step guide for non-technical users — Claude desktop download, Code tab, workspace folder selection, bypass permissions, always-allow dialogs.
**Not part of the install logic** — customer reads it before starting.
**Identical in both copies** (as of last sync).

---

### `CLAUDE.md`
**Role:** Loaded automatically when folder is opened in Claude desktop. Orients Claude: "This workspace installs HealthOS. Type `/install`." Three sentences.
**Identical in both copies.**

---

### `README.md`
**Role:** Human-facing 3-step overview: install Claude desktop → open folder → type `/install`.
**Identical in both copies.**

---

## End-to-End Install Flow

```
User opens folder in Claude desktop
    → CLAUDE.md loads

User types /install
    → .claude/commands/install.md fires
    → Claude reads INSTALL.md in full

Pre-Install Steps (interactive):
    → Telegram confirmed
    → Anthropic API key validated via curl to api.anthropic.com
    → AWS account confirmed

Phase 0 Step 1 — Download code gate:
    → Claude prompts for download code
    → Reads MAKE_CONFIRM_WEBHOOK from installer-config.txt
    → POSTs code to Make CONFIRM webhook (read-only Airtable lookup)
    → Response: { status, reason, downloads, max }
    → status = "ok": proceed  |  status = "deny": stop + show reason
    → status = anything else: stop + show "validation failed" message

Phase 0:
    → Claude reads installer-config.txt → GITHUB_REPO_URL loaded
    → Instance name collected, state file initialized (download_code written)

Phase 1: 01-preflight.sh
    → AWS CLI confirmed, credentials valid
    → Account ID → bucket name derived: healthos-backup-{account-id}

[Human Step 2 if needed]:
    → User creates IAM installer user in AWS Console
    → Pastes keys → Claude runs aws configure → Phase 1 re-run

Phase 2: 02-aws.sh
    → SSH key, Lightsail instance, static IP, SSH config
    → Server IP confirmed, SSH working

Phase 3A: 03-backup-infra.sh
    → S3 bucket, IAM backup user, access key (shown once only)

Phase 3B: 03-telegram.sh
    → Bot token provided → group ID + bot username captured

Phase 4: 04-workspace.sh
    → HealthOS cloned from GitHub → .env written on server

Phase 5: 05-server-a.sh
    → System updated, swap created, reboot, SSH confirmed back up

Phase 6: 06-server-b.sh
    → Node.js 22 (with auto-retry), Claude Code, Python venv
    → Crontab installed, systemd service started, 60s wait for active

Phase 7: 07-verify.sh
    → 13-point checks run
    → Telegram confirmation message sent to customer's group

Install Complete:
    → Claude fires MAKE_INCRDOWNLOADS_WEBHOOK (fire-and-forget, > /dev/null)
    → Make increments Downloads counter in Airtable Licenses table
    → Claude shows completion message with Telegram /setup instruction
    → install-log-{name}.md written
```

---

## Data Layer

| Data store | Contents | Written by | Read by |
|---|---|---|---|
| `installer-config.txt` (gitignored) | GitHub PAT in repo URL, Make webhook URLs | Paul manually | Claude (Phase 0, Install Complete) |
| `install-state-{name}.json` | Completed phases, non-secret config including `download_code` | Claude (each phase) | Claude (resume) |
| Airtable Licenses table | Code, Status, Expires At, Downloads, MaxDownloads | Make (purchase), Make INCREMENT webhook | `validate-code.js` (download gate), Make CONFIRM webhook (install gate) |
| Make CONFIRM webhook | Read-only Airtable lookup → returns `{ status, reason, downloads, max }` | n/a (webhook endpoint) | INSTALL.md Phase 0 Step 1 |
| Make INCREMENT webhook | Increments Airtable `Downloads` field for a given code | n/a (webhook endpoint) | INSTALL.md Install Complete |
| S3 bucket (installer) | `healthos-installer.zip` | Paul manually (ZIP rebuild) | `validate-code.js` (generates signed URL) |
| `~/.aws/credentials` (Mac) | Installer IAM credentials | Claude + aws configure | All AWS scripts |
| `~/.ssh/{key}.pem` (Mac) | Lightsail SSH private key | `02-aws.sh` | All server SSH scripts |
| `~/.ssh/config` (Mac) | SSH alias entry | `02-aws.sh` | Claude, user |
| `/home/ubuntu/healthos/.env` (server) | All runtime credentials | `04-workspace.sh` | HealthOS bot |
| `~/.aws/credentials` (server) | S3 backup credentials | `06-server-b.sh` | Cron backup job |
| `install-log-{name}.md` | Post-install resource record | Claude (completion) | Paul (support) |

---

## Dev Workspace vs. Customer ZIP — Differences

This table tracks what's in this workspace vs. what was last included in the customer ZIP on S3. Items marked **needs ZIP rebuild** will not reach customers until the ZIP is rebuilt and uploaded.

⚠️ The ZIP was last rebuilt before 2026-04-15. All changes since then (including the download code gate) require a ZIP rebuild.

| Area | This Workspace | Last Customer ZIP | Status |
|---|---|---|---|
| `INSTALL.md` Phase 0 Step 1 | Download code gate present | Absent | **Needs ZIP rebuild** |
| `install-state.json` | `download_code` field present | Absent | **Needs ZIP rebuild** |
| `installer-config.txt` | CONFIRM + INCREMENT webhook URLs present | Absent | **Needs ZIP rebuild** |
| `03-backup-infra.sh` | IAM key auto-delete guard | No guard | **Needs ZIP rebuild** |
| `05-server-a.sh` | Swap existence guard | No guard | **Needs ZIP rebuild** |
| `06-server-b.sh` | Node.js pipefail + auto-retry, 60s bot wait | No fix, 15s wait | **Needs ZIP rebuild** |
| `07-verify.sh` | 13 checks, direct sendMessage | 11 checks (`06-verify.sh`), health_notify | **Needs ZIP rebuild** |
| Script numbering | `06-server-b.sh`, `07-verify.sh` | `05-server-b.sh`, `06-verify.sh` | ZIP uses old names |
| `reboot_healthos.py` | Present | Absent | Dev/internal only — intentional |
| `INSTALLER-DEV-NOTES.md` | Present | Absent | Dev-only — intentional |
| `CHANGELOG.md` | Dev changelog | Separate ZIP changelog (2026-04-13) | Separate histories — intentional |
| `categories-preferences-data.txt` | Present | Absent | Dev reference only — intentional |
| `reference/system-architecture.md` | This file | Present | Both have architecture docs |

---

## Architectural Notes

### All changes go here first
All installer improvements are made and tested in this workspace. The customer ZIP is a snapshot of this workspace at the time of the last ZIP build. Never hand-edit the ZIP — always change the source here, then rebuild.

### installer-config.txt is gitignored — always
The GitHub PAT must never be committed. `.gitignore` excludes it. If it ever appears in a `git status` as a tracked file, something has gone wrong. Verify the `.gitignore` is present and working before any commit.

### Two script numbering schemes exist
This workspace uses `06-server-b.sh` and `07-verify.sh` (renumbered 2026-04-08 to match phase numbers). The last customer ZIP still uses `05-server-b.sh` and `06-verify.sh` (old names). A ZIP rebuild will bring the naming in sync.

### The Telegram verify check changed from agent to API
Before 2026-04-06, check 10/12 ran `health_notify.py --mode morning` via SSH — a live Claude agent call that cost ~$0.10 and sent an uncontrolled coaching message as a side effect of verification. Now it calls the Telegram `sendMessage` API directly. No agent, no cost, controlled message. The last customer ZIP has not received this fix.

### reboot_healthos.py is a post-install maintenance tool
Not part of the install flow. Reads the install state file to find the instance name automatically. Intended for situations where the Lightsail instance needs a reboot (e.g., after a HealthOS update). Not distributed to customers.

---

## What Lives Where — Quick Reference

| Concern | File / Location |
|---|---|
| Install trigger | `.claude/commands/install.md` |
| Full install orchestration | `INSTALL.md` |
| Install state template | `install-state.json` |
| GitHub PAT / repo URL / Make webhook URLs | `installer-config.txt` (gitignored) |
| Known issues + improvement tracker | `INSTALLER-DEV-NOTES.md` |
| Dev changelog | `CHANGELOG.md` |
| Onboarding reference data | `categories-preferences-data.txt` |
| Mac preflight / AWS CLI | `scripts/01-preflight.sh` |
| AWS infrastructure creation | `scripts/02-aws.sh` |
| S3 bucket + IAM backup user | `scripts/03-backup-infra.sh` |
| Telegram group ID capture | `scripts/03-telegram.sh` |
| GitHub clone + .env deploy | `scripts/04-workspace.sh` |
| Server update + swap + reboot | `scripts/05-server-a.sh` |
| Node.js + Claude Code + Python + systemd | `scripts/06-server-b.sh` |
| 13-point verification suite | `scripts/07-verify.sh` |
| Post-install Lightsail reboot | `scripts/reboot_healthos.py` |
| Visual setup guide (source of truth) | `HealthOS-Setup-Guide.html` |
| UI screenshots | `images/` |
| Customer-facing README | `README.md` |
| Claude workspace orientation | `CLAUDE.md` |
| Customer download page | `HealthOS-Sales/download-page.html` (via `yostai/HealthOS-Sales`) |
| Download code validation function | `HealthOS-Sales/netlify/functions/validate-code.js` |
| Setup guide (Netlify copy — do not edit directly) | `HealthOS-Sales/setup-guide.html` |
| Airtable Licenses table | External — Make + validate-code.js read/write |
| Make CONFIRM webhook (install gate) | External — URL in `installer-config.txt` |
| Make INCREMENT webhook (downloads counter) | External — URL in `installer-config.txt` |
