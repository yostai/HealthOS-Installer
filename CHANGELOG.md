# HealthOS Installer — Changelog
<!-- © 2026 Yost AI. All rights reserved. -->

---

## 2026-04-16 — v0.4.16

### Download code gate + UI updates + system architecture cleanup

#### `INSTALL.md` — Download code validation gate (Phase 0 Step 1)
Added a second validation layer before any install work begins:
- Claude prompts for the customer's download code
- Reads `MAKE_CONFIRM_WEBHOOK` from `installer-config.txt` and POSTs the code
- Make looks up Airtable: returns `{ status, reason, downloads, max }`
- `status = "ok"`: installation proceeds
- `status = "deny"`: installation stops with reason displayed to customer
- Any other status: stops with generic validation failure message
- On resume: `download_code` reloaded from state file and re-validated before any install work continues

#### `INSTALL.md` — Install Complete: download increment webhook
Added fire-and-forget call to `MAKE_INCRDOWNLOADS_WEBHOOK` at install completion. Make increments the `Downloads` counter in Airtable Licenses table. Install outcome is not gated on this succeeding.

#### `install-state.json` — Added `download_code` field
Added `download_code: null` as first field in the config section. Persists the code for resume re-validation.

#### `installer-config.txt` — Added Make webhook URLs
Added `MAKE_CONFIRM_WEBHOOK` and `MAKE_INCRDOWNLOADS_WEBHOOK` entries. Both are live Make webhook URLs pointing to Airtable Licenses table lookups.

#### `HealthOS-Setup-Guide.html` — New Claude desktop UI screenshots
Updated for Anthropic's redesigned desktop app layout:
- Code is now an icon in the top-left corner (not a tab at the top) — added new screenshot, shown first with "or" before the old tabs image
- "Auto accept edits" renamed to "Ask Permissions" — new screenshot added
- "Enable bypass mode" renamed to "Bypass Permissions" — new screenshot added
- "Always allow for project (local)" renamed to "Always allow" — new screenshot added
- Section 5 steps 3 and 4 swapped (Auto accept before Select folder)
- Section 5 step 5: added "Click Open Folder" instruction
- Part 3 reminder updated to match all new button names

#### `VERSION` — Bumped to 0.4.16

#### `reference/system-architecture.md` — Major cleanup
- Added GitHub Repositories section (all 3 repos, purposes, local paths)
- Added Who Does What section with change playbooks
- Added ⚠️ CRITICAL section: ZIP must be rebuilt after any installer change (documents 2026-04-16 incident)
- Added Complete Purchase-to-Install Flow and two-layer gate architecture
- Added HealthOS-Sales Customer Site section (Airtable schema, validate-code.js role)
- Removed all "distribution copy" language — replaced with "customer ZIP" throughout
- Fixed stale `outputs/healthos-sales/` path references
- Renamed "Dev vs. Distribution Copy" → "Dev Workspace vs. Customer ZIP" with updated status tracking

---

## 2026-04-14

### Multi-instance installer support + Playwright removal

#### `install-state.json` — Added `app_slug` field
Added `app_slug` to the config section. Persists the app directory name across session interruptions so resume works correctly when the slug was auto-incremented.

#### `INSTALL.md` — App slug threading
- Phase 0: app slug introduced (defaults to instance name, auto-incremented on collision)
- Phase 4: slug passed as 10th arg; collision handling added
- Phase 6: slug passed as 3rd arg; script name corrected to `06-server-b.sh`
- Phase 7: slug passed as 6th arg; script name corrected to `07-verify.sh`
- Install log: credential path updated from hardcoded `healthos/.env` to `{slug}/.env`
- Resume: `app_slug` added to the values reloaded from state file

#### `04-workspace.sh` — Slug parameterization + collision detection
- Accepts `APP_SLUG` as 10th arg
- Checks for existing `/home/ubuntu/{slug}/` before cloning; exits with `SLUG_EXISTS=true` and `SLUG_SUGGESTED={slug}-N` if collision found (N auto-incremented until a free name is found)
- All `/home/ubuntu/healthos` references replaced with `/home/ubuntu/${APP_SLUG}`

#### `06-server-b.sh` — Shared venv + slug parameterization + crontab append + Playwright removed
- Accepts `APP_SLUG` as 3rd arg
- Shared venv: checks for `/home/ubuntu/.venv/`; creates it on first install, reuses on subsequent installs (~350MB once, not per app)
- Playwright + Chromium install block removed entirely (unused, ~300MB, ~3 min)
- Crontab: switched from replace-all to append with `# BEGIN {slug}` / `# END {slug}` markers; idempotent on re-run; paths substituted at install time (shared venv + app slug)
- Systemd: service copied as `{slug}-bot.service`, patched in-place via two-pass sed (venv path first, then workspace path)
- All `healthos` hardcoded references parameterized

#### `07-verify.sh` — Slug parameterization
- Accepts `APP_SLUG` as 6th arg (defaults to `healthos` for backwards compatibility)
- All path checks, service name checks, and fix commands updated to use `${APP_SLUG}` and `/home/ubuntu/.venv`

---

## 2026-04-13

### Added: Credit propagation delay explanation + Anthropic Auto Reload instructions

#### `HealthOS-Setup-Guide.html` — Credit propagation delay + Auto Reload

**Credit propagation delay:** Added explanation in two places:
- Phase G "Your job" section: user is told they may see a bot message about billing/credits before the ready signal arrives
- Install Complete box: new paragraph explaining that Anthropic credits can take 5–20 minutes to activate on new accounts, and that the bot will self-check and notify when it's ready

**Auto Reload setup:** Added as a new step in the Anthropic account setup section (Step 4), with sub-bullets for exact navigation: Billing → Usage limits → Enable automatic recharge. Explains threshold ($10 trigger, $40 reload) so users understand what they're enabling.

#### `INSTALL.md` — Credit propagation delay + Auto Reload

**Credit propagation delay:** Added "One more thing" note in the Install Complete section — informs the installer that the bot's ready signal may take 5–20 minutes to appear after billing is added.

**Auto Reload instructions:** Pre-Install Step 2 "No" path restructured into three explicit steps:
1. Add billing method
2. Enable Auto Reload (with exact navigation steps and threshold explanation)
3. Create API key

Ensures installers can walk customers through the full Anthropic account setup, not just API key creation.

---

## 2026-04-08

### Robustness pass — 8 issues fixed (dry run + principles review)

#### `apps/command/__main__.py` — Created (hard blocker fix)
**File:** `HealthOS-TEST/apps/command/__main__.py` (new file)
Missing entry point required by systemd service (`python3 -m apps.command`). Without it Phase 4 file verification failed and the bot would never start. Three-line file: `asyncio.run(main())`.

#### Script renaming — phase numbers now match script numbers
`scripts/05-server-b.sh` → `scripts/06-server-b.sh`
`scripts/06-verify.sh` → `scripts/07-verify.sh`
All references in `INSTALL.md` and error table updated.

#### `03-backup-infra.sh` — IAM key auto-delete guard
On resume, `create-access-key` failed with `LimitExceeded` if the IAM user already had 2 keys. Now auto-detects key count and deletes the oldest before creating a new one. User never sees the error.

#### `05-server-a.sh` — Swap file existence guard
`fallocate` failed on resume if `/swapfile` already existed (`set -e` exits). Wrapped creation block in `if [ ! -f /swapfile ]` — idempotent, prints SKIP on second run.

#### `06-server-b.sh` — Node.js pipe fix + auto-retry
`curl | sudo bash | tail -3` always exited 0, masking CDN failures. Wrong Node.js version installed silently. Fixed: added `set -o pipefail` to the pipe. Added version check after install — if not v22+, auto-removes, re-runs nodesource setup, reinstalls. Two attempts before failing loudly with a "try again in a few minutes" message.

#### `06-server-b.sh` — Bot startup wait increased to 60 seconds
`BOT_MAX` increased from 5 to 20 (5 × 3s → 20 × 3s = 60s). Added user-facing message before the wait loop: *"Starting your HealthOS bot — this may take up to 60 seconds on first launch..."*

#### `07-verify.sh` — Check 10 split into two distinct checks
Combined check had `|| true` defeating the Python import test — always passed regardless of import success. Split into: (1) `__main__.py` exists, (2) `apps.command` importable. Labels renumbered sequentially 1–13. INSTALL.md check count updated to 13.

#### `04-workspace.sh` — git clone URL quoting fixed
`$GITHUB_REPO_URL` was unquoted inside the SSH command string — quotes closed early, URL unquoted on remote shell. Fixed: URL now assigned to `REPO_URL` as a local variable inside the remote shell string. Safe against any token format.

#### `INSTALL.md` — Resume flow state reload
Resume instructions now explicitly direct Claude to reload non-secret derived values from the state file (`server_ip`, `pem_path`, `bucket_name`, `iam_user`, `bot_username`) before continuing. Added state-write instructions after Phase 1 (bucket_name) and Phase 3B (bot_username).

#### `HealthOS-TEST/requirements.txt` — Removed unrelated packages
`google-analytics-data` and `google-auth` (AIOS DataOS dependencies) removed. Not used by HealthOS — were being installed on the Lightsail server unnecessarily.

---

## 2026-04-06

### 06-verify.sh — Update Telegram installation confirmation message
**File:** `scripts/06-verify.sh`
Updated the message sent to the customer's Telegram group during verification. Now reads:
"✅ HealthOS is installed and connected. Congratulations on your new HealthOS Coach. When you are ready to set up your coach, please type 'setup' here."
Tested against live bot token — confirmed delivered.

---

### 04-workspace.sh — Quote $GITHUB_REPO_URL variable
**File:** `scripts/04-workspace.sh` line 46
Unquoted variable `$GITHUB_REPO_URL` in `git clone` command. Quoted to prevent word-splitting edge cases.

### 06-verify.sh — Fix misleading comment on check #8
**File:** `scripts/06-verify.sh` line 82
Comment said `# 8. health.db exists` but the check tests `.env` permissions. Comment corrected to match.

### 06-verify.sh — Add swap verification check
**File:** `scripts/06-verify.sh`
Added check #9: verifies 2GB swap is active on the server (`swapon --show | grep -q swapfile`). Corresponds to swap setup added to `05-server-a.sh` on this date. Checks are now numbered 1–12.

---

### 06-verify.sh — Check #10: Replace live agent call with direct Telegram message
**File:** `scripts/06-verify.sh`
**Lines:** 93–99

**Before:** Ran `health_notify.py --mode morning` via SSH — fired a live Claude agent call (~$0.10), sent an uncontrolled coaching message to the customer's Telegram group as a side effect of verification.

**After:** Sends a single explicit confirmation message directly via Telegram `sendMessage` API. Validates token, confirms bot can reach the group, and gives the customer visible proof their bot is connected — no agent, no cost, no side effects.

**Tested:** Confirmed PASS against live bot token. Message delivered to Telegram group.
