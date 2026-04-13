# HealthOS Installer — Changelog

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
