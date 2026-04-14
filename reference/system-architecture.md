# HealthOS Installer — System Architecture

**Purpose:** Reference for any Claude instance working on this codebase. Read this before touching anything. Explains every file's role, the full install flow, and how the installer reaches customers.
**Last mapped:** 2026-04-14

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
When this file is updated, copy it to `outputs/healthos-sales/setup-guide.html` and push both repos. Do not edit `setup-guide.html` in the healthos-sales repo directly — always edit the installer copy first.

The `images/` folder is also shared. If any image is added or changed in `HealthOS-Installer/images/`, copy it to `outputs/healthos-sales/images/` as well.

---

## Deployment Structure

How the installer reaches customers and how updates get published.

```
GitHub: yostai/HealthOS-Installer
    → Netlify auto-deploys on every push
    → Serves: HealthOS-Setup-Guide.html (online instructions)
    → Serves: download-page.html (customer download page with ?code= link)

S3 bucket
    → Holds: health-installer.zip (the installer customers actually download)
    → Customers reach it via the Netlify download page link

Customer purchase flow:
    Stripe purchase → email with download link
        → Netlify download-page.html?code=...
        → Download link → pulls health-installer.zip from S3
        → Customer unzips, opens in Claude desktop, runs /install
```

**Two separate update actions are required when the installer changes:**

| What changed | Action required |
|---|---|
| `HealthOS-Setup-Guide.html` (online instructions) | Commit + push to `yostai/HealthOS-Installer` → Netlify auto-deploys |
| Any script, `INSTALL.md`, or any file inside the ZIP | Rebuild `/tmp/healthos-installer.zip` → upload to S3 |
| Both | Do both |

Pushing to GitHub does NOT update what customers download. Uploading to S3 does NOT update the online instructions. They are independent.

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

This is the **development copy** of the HealthOS Installer — the place where changes are made, tested, and tracked before being ported to the customer-facing distribution copy.

**Do not confuse with:**
- `module-installs/healthos-installer/` — the distribution copy. What goes into the S3 ZIP customers download. Must stay clean, tested, and customer-ready.
- `yostai/HealthOS-Installer` on GitHub — the remote for *this* dev workspace.

**Change flow:**
```
HealthOS-Installer/ (this workspace — dev)
    → changes made + tested here
    → ported manually to module-installs/healthos-installer/
    → ZIP rebuilt → uploaded to S3 (customer download)
```

Changes in this workspace do NOT automatically appear in the customer ZIP. Porting is a deliberate manual step.

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
| Phase 0 | Instance name, read GitHub URL from config, init state file | None |
| Phase 1 | Mac preflight: check AWS CLI, verify credentials | `01-preflight.sh` |
| Human Step 2 | User creates IAM user + access key in AWS Console | None |
| Phase 2 | Lightsail instance, SSH key, static IP, SSH config | `02-aws.sh` |
| Phase 3A | S3 backup bucket + IAM backup user + access key | `03-backup-infra.sh` |
| Phase 3B | Capture Telegram bot token + group ID | `03-telegram.sh` |
| Phase 4 | Clone HealthOS from GitHub, write `.env` on server | `04-workspace.sh` |
| Phase 5 | apt update/upgrade, base packages, swap, reboot | `05-server-a.sh` |
| Phase 6 | Node.js, Claude Code, Python venv, crontab, systemd | `06-server-b.sh` |
| Phase 7 | 13-point verification suite + Telegram confirmation | `07-verify.sh` |
| Complete | Completion message, write install log | None |

**Note:** This dev copy INSTALL.md says "13 checks" in Phase 7. The distribution copy still says "11 checks" — not yet ported.

---

## Full File Map

### `scripts/01-preflight.sh`
**When:** Phase 1
**What it does:** Checks AWS CLI installed, checks `~/.aws/` credentials exist, calls `aws sts get-caller-identity` to validate. If AWS CLI missing, downloads the `.pkg` and instructs user to install (requires sudo — cannot be automated). Outputs `PREFLIGHT_OK=true` and `AWS_ACCOUNT_ID` which Claude uses to derive the backup bucket name.
**Identical to distribution copy.**

---

### `scripts/02-aws.sh`
**When:** Phase 2
**What it does:** Creates Lightsail SSH key pair (`.pem` → `~/.ssh/`), creates Lightsail instance (Ubuntu 24.04, 1GB, us-east-1a), waits for running state, allocates + attaches static IP, closes port 80, writes SSH config entry, waits for SSH.
**Outputs:** `STATIC_IP`, `PEM_PATH`, `SSH_HOST`, `INSTANCE_NAME`
**Idempotent:** Every creation step guards "already exists."
**Identical to distribution copy.**

---

### `scripts/03-backup-infra.sh`
**When:** Phase 3A
**What it does:** Creates S3 backup bucket (public access blocked), creates IAM backup user, attaches `AmazonS3FullAccess` policy, creates access key.
**Robustness fix (2026-04-08):** Before creating access key, checks existing key count. If 2 exist (IAM limit), auto-deletes the oldest. User never sees `LimitExceeded` on resume.
**Outputs:** `S3_BUCKET`, `AWS_BACKUP_KEY_ID`, `AWS_BACKUP_SECRET`
**Differs from distribution copy:** Distribution copy lacks the IAM key auto-delete guard.

---

### `scripts/03-telegram.sh`
**When:** Phase 3B
**What it does:** Calls Telegram `getUpdates` API, parses JSON to find a group chat ID (negative number), retries 3× with 10s waits. Calls `getMe` for bot @username.
**Outputs:** `TELEGRAM_GROUP_ID`, `BOT_USERNAME`
**Identical to distribution copy.**

---

### `scripts/04-workspace.sh`
**When:** Phase 4
**What it does:** Installs git on server if missing, clones HealthOS from GitHub (URL from session memory — read from `installer-config.txt` in Phase 0), writes `.env` to server via SSH heredoc, `chmod 600`, updates backup script with bucket name, verifies 5 key files present.
**URL quoting fix (2026-04-06):** `$GITHUB_REPO_URL` assigned to `REPO_URL` inside the remote shell string — prevents early quote termination if token contains shell-special characters.
**Both copies have this fix.**

---

### `scripts/05-server-a.sh`
**When:** Phase 5
**What it does:** `apt update` + `apt upgrade`, installs base packages (Python 3.12 venv, build tools, Pango/GDK for Playwright, curl, wget, awscli), creates 2GB swap file, reboots, waits for SSH.
**Robustness fix (2026-04-08):** Swap creation wrapped in `if [ ! -f /swapfile ]` — idempotent on resume, prints SKIP instead of failing.
**Outputs:** `SERVER_A_OK=true`
**Differs from distribution copy:** Distribution copy lacks swap guard.

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
**Differs significantly from distribution copy** (`05-server-b.sh`): distribution lacks Node.js pipe fix, auto-retry, and 60s wait.

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
**Differs significantly from distribution copy** (`06-verify.sh` with 11 checks): distribution lacks swap check (9), has combined __main__.py check instead of split (10+11), uses `health_notify.py --mode morning` for Telegram test instead of direct `sendMessage`.

---

### `scripts/reboot_healthos.py`
**When:** Post-install, on demand — not part of the install flow
**What it does:** Lets Paul (or a customer) reboot their Lightsail instance from their Mac without opening the AWS Console.
1. Reads instance name from `install-state-{name}.json` automatically
2. If not found, prompts for instance name
3. Calls `aws lightsail reboot-instance`
4. Polls instance state every 10s for up to 100 seconds, reports when running
**Uses:** AWS credentials already configured during install (`~/.aws/credentials`)
**Not present in distribution copy.**

---

### `INSTALLER-DEV-NOTES.md`
**Role:** Issue tracker for the installer. Each known bug or improvement is documented with: what happens to the user, auto-recovery potential, proposed solution, and status (Open/Resolved).
**Not a customer-facing file** — dev reference only.
**Not present in distribution copy.**

---

### `CHANGELOG.md`
**Role:** Running log of changes made to this dev workspace, most recent at top.
**Not a customer-facing file** — dev reference only.
**Not present in distribution copy** (distribution has its own CHANGELOG created 2026-04-13).

---

### `categories-preferences-data.txt`
**Role:** Reference data for the HealthOS onboarding interview — full branching logic for diet types, workout preferences, mental health categories, complications, motivation styles, and check-in schedule options.
**Used by:** The onboarding interview agent in HealthOS-TEST, not directly by the installer scripts.
**Why it's here:** Kept alongside the installer workspace for reference during onboarding-related installer development. Mirrors the copy in `HealthOS-TEST/onboarding/reference/`.
**Not present in distribution copy.**

---

### `install-state.json`
**Role:** Template for per-install state file. Copied at Phase 0 to `install-state-{instance-name}.json`. Tracks completed phases and non-secret config values.
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

Phase 0:
    → Claude reads installer-config.txt → GITHUB_REPO_URL loaded
    → Instance name collected, state file initialized

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
    → Claude shows completion message with Telegram /setup instruction
    → install-log-{name}.md written
```

---

## Data Layer

| Data store | Contents | Written by | Read by |
|---|---|---|---|
| `installer-config.txt` (gitignored) | GitHub PAT in repo URL | Paul manually | Claude (Phase 0) |
| `install-state-{name}.json` | Completed phases, non-secret config | Claude (each phase) | Claude (resume) |
| `~/.aws/credentials` (Mac) | Installer IAM credentials | Claude + aws configure | All AWS scripts |
| `~/.ssh/{key}.pem` (Mac) | Lightsail SSH private key | `02-aws.sh` | All server SSH scripts |
| `~/.ssh/config` (Mac) | SSH alias entry | `02-aws.sh` | Claude, user |
| `/home/ubuntu/healthos/.env` (server) | All runtime credentials | `04-workspace.sh` | HealthOS bot |
| `~/.aws/credentials` (server) | S3 backup credentials | `06-server-b.sh` | Cron backup job |
| `install-log-{name}.md` | Post-install resource record | Claude (completion) | Paul (support) |

---

## Dev vs. Distribution Copy — Differences

This table shows what exists in this dev copy vs. the distribution copy (`module-installs/healthos-installer/`). Items marked **not ported** need to be manually ported before the next ZIP build.

| Area | Dev Copy | Distribution Copy | Status |
|---|---|---|---|
| `03-backup-infra.sh` | IAM key auto-delete guard | No guard | **Not ported** |
| `05-server-a.sh` | Swap existence guard | No guard | **Not ported** |
| `06-server-b.sh` | Node.js pipefail + auto-retry, 60s bot wait | No fix, 15s wait | **Not ported** |
| `07-verify.sh` / `06-verify.sh` | 13 checks, swap check, split __main__ checks, direct sendMessage | 11 checks, combined check, health_notify | **Not ported** |
| Script numbering | `06-server-b.sh`, `07-verify.sh` | `05-server-b.sh`, `06-verify.sh` | Distribution uses old names |
| `reboot_healthos.py` | Present | Absent | Not intended for distribution |
| `INSTALLER-DEV-NOTES.md` | Present | Absent | Dev-only |
| `CHANGELOG.md` | Dev changelog | Distribution changelog (created 2026-04-13) | Separate files, separate histories |
| `categories-preferences-data.txt` | Present | Absent | Dev reference only |
| `INSTALL.md` completion screen | Original (SSH command present, no /setup) | Updated (SSH removed, /setup added) | **Distribution is ahead here** |
| `INSTALL.md` version | 1.0 (header) | 0.4.1 | **Distribution is ahead here** |
| `VERSION` file | Absent | Present (0.4.1) | **Not ported** |
| `reference/system-architecture.md` | This file | Present | Both have architecture docs |

---

## Architectural Notes

### This workspace receives changes first
All installer improvements are made and tested here. The distribution copy is a deliberate, curated snapshot. Never update the distribution copy directly without first verifying in this workspace.

### installer-config.txt is gitignored — always
The GitHub PAT must never be committed. `.gitignore` excludes it. If it ever appears in a `git status` as a tracked file, something has gone wrong. Verify the `.gitignore` is present and working before any commit.

### Two script numbering schemes coexist
This dev copy uses `06-server-b.sh` and `07-verify.sh` (renumbered 2026-04-08 to match phase numbers). The distribution copy still uses `05-server-b.sh` and `06-verify.sh`. When porting changes, don't rename files in the distribution copy unless also updating all references in its `INSTALL.md`.

### The Telegram verify check changed from agent to API
Before 2026-04-06, check 10/12 ran `health_notify.py --mode morning` via SSH — a live Claude agent call that cost ~$0.10 and sent an uncontrolled coaching message as a side effect of verification. Now it calls the Telegram `sendMessage` API directly. No agent, no cost, controlled message. The distribution copy has not received this fix — it still uses `health_notify.py`.

### reboot_healthos.py is a post-install maintenance tool
Not part of the install flow. Reads the install state file to find the instance name automatically. Intended for situations where the Lightsail instance needs a reboot (e.g., after a HealthOS update). Not distributed to customers.

---

## What Lives Where — Quick Reference

| Concern | File |
|---|---|
| Install trigger | `.claude/commands/install.md` |
| Full install orchestration | `INSTALL.md` |
| Install state template | `install-state.json` |
| GitHub PAT / repo URL | `installer-config.txt` (gitignored) |
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
| Visual setup guide | `HealthOS-Setup-Guide.html` |
| UI screenshots | `images/` |
| Customer-facing README | `README.md` |
| Claude workspace orientation | `CLAUDE.md` |
