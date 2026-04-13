# HealthOS Installer — Development Notes

**Purpose:** Tracks known issues, improvement opportunities, and design decisions for the installer.
**Source:** Dry run 2026-04-08 + post-dry-run UX review.
**Principle:** The installer should require as little user interaction as possible. Errors should auto-recover silently where possible. If auto-recovery is not possible, the installer fixes the problem itself — it does not instruct the user to fix it.

**Platform note:** The installer as designed runs inside Claude Code (desktop app, Code tab). This requires Mac or Windows. iOS and Android do not support Claude Code. Mobile install support is a future consideration — see FUTURE section below.

---

## Open Issues

---

### ISSUE-1: IAM access key — no guard on second run
**File:** `scripts/03-backup-infra.sh` ~line 62
**What happens to user:** On resume after a Phase 3A interruption, `create-access-key` fails with a raw AWS error: `LimitExceeded: Cannot exceed quota for AccessKeysPerUser: 2`. Script exits. Install stops. User has no idea why.
**Auto-recovery potential:** High — fully solvable with no user involvement.
**Proposed solution:** Before calling `create-access-key`, check existing key count. If 2 keys exist, auto-delete the oldest one, then create fresh. User never sees it.
```bash
KEY_COUNT=$(aws iam list-access-keys --user-name "$IAM_USER" \
    --query 'length(AccessKeyMetadata)' --output text)
if [ "$KEY_COUNT" -ge 2 ]; then
    OLDEST_KEY=$(aws iam list-access-keys --user-name "$IAM_USER" \
        --query 'sort_by(AccessKeyMetadata, &CreateDate)[0].AccessKeyId' \
        --output text)
    aws iam delete-access-key --user-name "$IAM_USER" --access-key-id "$OLDEST_KEY"
    echo "  OK: Removed oldest key to make room for new one"
fi
```
**Status:** Resolved

---

### ISSUE-2: Swap file — fails if already exists on second run
**File:** `scripts/05-server-a.sh` ~line 50
**What happens to user:** On resume, `fallocate -l 2G /swapfile` fails because the file already exists. `set -e` exits the script. User sees an SSH error and the install stops mid-phase.
**Auto-recovery potential:** Trivial — one guard line makes it invisible.
**Proposed solution:**
```bash
if [ ! -f /swapfile ]; then
    sudo fallocate -l 2G /swapfile && \
    sudo chmod 600 /swapfile && \
    sudo mkswap /swapfile && \
    sudo swapon /swapfile && \
    grep -q '/swapfile' /etc/fstab || \
        echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab > /dev/null
    echo "  OK: 2GB swap active and persistent"
else
    echo "  SKIP: swapfile already exists"
fi
```
**Status:** Resolved

---

### ISSUE-3: Node.js setup pipe masks failure silently — fix pipe first, then retry
**File:** `scripts/06-server-b.sh` ~line 29
**What happens to user:** If the nodesource CDN setup fails (network issue, CDN down), `tail -3` at the end of the pipe returns exit 0 regardless. `apt install nodejs` then installs the Ubuntu system version (v18 or older, not v22). Script continues happily. User sees "HealthOS is live!" but the bot never responds in Telegram. No error, no explanation, user has a broken install and no idea why.
**Auto-recovery potential:** High — fully automated. Two attempts, only stops the install if both fail.
**Root cause (per development principles):** The pipe itself is broken — `| tail -3` always exits 0, so failures are invisible on attempt 1. Fix the pipe first. Retry on top of a broken pipe just adds complexity on top of a broken foundation.
**Proposed solution:** Fix the pipe using `set -o pipefail` so a CDN failure actually propagates. Then add a version check + single auto-retry if something still goes wrong. Only exit with an error if the second attempt also fails — with a "try again in a few minutes" message, not a fix command for the user:
```bash
# Replace current nodesource curl | sudo bash | tail -3 with:
echo "--- Installing Node.js 22..."
ssh $SSH_OPTS ubuntu@"$SERVER_IP" \
    "set -o pipefail; curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - 2>&1 | tail -3"
ssh $SSH_OPTS ubuntu@"$SERVER_IP" \
    "sudo apt install -y nodejs 2>&1 | tail -3"

# Version check — auto-retry if wrong
NODE_MAJOR=$(ssh $SSH_OPTS ubuntu@"$SERVER_IP" \
    "node --version 2>/dev/null | sed 's/v//' | cut -d. -f1 || echo 0")
if [ "$NODE_MAJOR" -lt 22 ]; then
    echo "  Node.js v22 not found (got v${NODE_MAJOR}) — auto-retrying..."
    ssh $SSH_OPTS ubuntu@"$SERVER_IP" "sudo apt remove -y nodejs 2>/dev/null || true"
    ssh $SSH_OPTS ubuntu@"$SERVER_IP" \
        "set -o pipefail; curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - 2>&1 | tail -3"
    ssh $SSH_OPTS ubuntu@"$SERVER_IP" "sudo apt install -y nodejs 2>&1 | tail -3"
    NODE_MAJOR=$(ssh $SSH_OPTS ubuntu@"$SERVER_IP" \
        "node --version 2>/dev/null | sed 's/v//' | cut -d. -f1 || echo 0")
    if [ "$NODE_MAJOR" -lt 22 ]; then
        echo "  ERROR: Node.js v22 could not be installed after two attempts."
        echo "  This is usually a temporary network issue. Wait a minute and re-run Phase 6."
        exit 1
    fi
fi
echo "  OK: Node.js v${NODE_MAJOR}"
```
**Status:** Resolved

---

### ISSUE-4: Bot startup wait too short (15 seconds)
**File:** `scripts/06-server-b.sh` ~line 119 (`BOT_MAX=5`, sleep 3s)
**What happens to user:** If Claude Code's first-launch initialization takes longer than 15 seconds (npm cache miss, slow network, agent SDK cold start), Phase 6 exits with `ERROR: healthos-bot status: activating after 5 attempts`. Install stops near the finish line. User doesn't know if HealthOS is broken or just slow.
**Auto-recovery potential:** High — just increase the ceiling. 60 seconds costs nothing if the bot starts in 10.
**Proposed solution:** Increase `BOT_MAX` from 5 to 20 (60 seconds total at 3s intervals). Print a message to the user *before* the wait loop begins so they aren't staring at silence:
```bash
BOT_MAX=20  # 60 seconds max
echo "  Starting your HealthOS bot — this may take up to 60 seconds on first launch..."
```
Also consider increasing `RestartSec` awareness — if the bot crashes immediately and systemd is in a restart backoff, `is-active` may show `activating` for longer than expected.
**Status:** Resolved

---

### ISSUE-5: Verify check 10 — `|| true` defeats import test (logic gate)
**File:** `scripts/07-verify.sh` ~line 93
**What happens to user:** Silent false positive — user sees `OK  apps.command module loadable` even if the Python import fails. If a missing dependency breaks the import chain, the bot crashes at runtime and the user doesn't know why — they just see the bot not responding.
**Auto-recovery potential:** High — fix the logic gate. Transparent to user.
**Proposed solution:** Split into two checks: one for file existence (fast), one for import success (meaningful):
```bash
check "apps/command/__main__.py exists" \
    "ssh $SSH_OPTS ubuntu@$SERVER_IP 'test -f /home/ubuntu/healthos/apps/command/__main__.py'" \
    "Check: ssh $SSH_ALIAS && ls ~/healthos/apps/command/__main__.py"

check "apps.command module importable" \
    "ssh $SSH_OPTS ubuntu@$SERVER_IP 'cd /home/ubuntu/healthos && .venv/bin/python3 -c \"import apps.command; print(\\\"OK\\\")\" 2>&1 | grep -q OK'" \
    "Run: ssh $SSH_ALIAS && cd healthos && .venv/bin/python3 -c \"import apps.command\" to see the error"
```
**Status:** Resolved

---

### ISSUE-6: git clone URL unquoted in SSH string
**File:** `scripts/04-workspace.sh` ~line 46
**What happens to user:** Safe in practice with standard GitHub tokens (format: `ghp_XXXX` — no shell-special characters). If a future token format contains `$`, `!`, or spaces, the shell parsing breaks with a cryptic error mid-SSH. Low probability but zero-cost fix.
**Auto-recovery potential:** Trivial — fix quoting. Transparent.
**Root cause (per development principles):** The URL is embedded directly in the SSH double-quoted string, causing the quotes to close early. First proposed fix (SSH env var passthrough with `bash -c` inside single quotes) was rejected — single-quoted strings don't expand variables, so `$GITHUB_URL` would never be seen on the remote.
**Proposed solution:** Assign the URL to a local variable inside the remote shell string. The URL expands locally into a single-quoted literal, which is assigned on the remote and then used safely — no special characters in the expanded value can break the outer double-quoted string:
```bash
ssh $SSH_OPTS ubuntu@"$SERVER_IP" "
    REPO_URL='$GITHUB_REPO_URL'
    if [ -d /home/ubuntu/healthos/.git ]; then
        cd /home/ubuntu/healthos && git pull
    else
        git clone \"\$REPO_URL\" /home/ubuntu/healthos
    fi
"
```
**Status:** Resolved

---

### ISSUE-7: Resume flow doesn't reload derived values from state file
**File:** `INSTALL.md` — State Tracking / Resume section
**What happens to user:** On resume in a new Claude session, the instructions say to re-ask for secrets (API key, token, GitHub URL, backup credentials) but don't explicitly instruct Claude to reload derived non-secret values from the state file: `server_ip`, `pem_path`, `bucket_name`. Claude may ask the user for these (confusing: "I thought you set that up?") or proceed with empty values (wrong commands).
**Auto-recovery potential:** High — write all derived values to state immediately when known; add explicit state-file read step to resume instructions.
**Proposed solution — two parts:**
1. Add explicit writes to state file at the moment each value is derived:
   - After Phase 1: write `bucket_name` to state
   - After Phase 2: write `server_ip`, `pem_path` to state (INSTALL.md already says this, but resume flow doesn't say to read it)
   - After Phase 3B: write `bot_username` to state
2. Add to resume instructions: "Read `install-state-{name}.json` and reload `server_ip`, `pem_path`, `bucket_name`, `iam_user`, `bot_username` into session before continuing."
**Status:** Resolved

---

### ISSUE-8: requirements.txt contains AIOS workspace packages (unrelated to HealthOS)
**File:** `HealthOS-TEST/requirements.txt`
**What happens to user:** `google-analytics-data` and `google-auth` (AIOS DataOS dependencies) get installed on the Lightsail server. Completely invisible — install takes ~20 extra seconds and two unneeded packages land on the server. No errors, no user impact.
**Auto-recovery potential:** N/A — just fix the file.
**Proposed solution:** Remove `google-analytics-data` and `google-auth` from `HealthOS-TEST/requirements.txt`. Keep only what HealthOS actually needs. The `06-server-b.sh` explicit pip list already covers all runtime dependencies; requirements.txt should either be empty or contain only legitimate HealthOS-specific packages not in the explicit list.
**Status:** Resolved

---

## Design Decisions

*(Record key architectural choices here as they're made — rationale for future reference)*

- **State file is per-instance** (`install-state-{name}.json`) to support multiple installs without conflicts.
- **Secrets never written to Mac disk** — API keys, bot token, GitHub token held session-only; backup credentials go directly to server `.env` via SSH heredoc.
- **`__main__.py` entry point** — added 2026-04-08. Required for `python3 -m apps.command` (systemd service invocation). Three lines: `import asyncio`, `from apps.command.main import main`, `asyncio.run(main())`.
- **Script numbering** — scripts renumbered 2026-04-08 to match phase numbers: `06-server-b.sh` (was `05-server-b.sh`), `07-verify.sh` (was `06-verify.sh`).

---

## Future Considerations

### FUTURE-1: Cross-platform install state (mobile support)
**Context:** The installer currently writes `install-state-{name}.json` to the customer's Mac (or Windows). This works for desktop Claude Code. It does not work for iOS or Android, which don't run Claude Code.
**Question raised:** Could browser cookies replace the Mac-local state file, enabling the same installer to work across Mac/Windows/iOS/Android?
**Assessment:** Browser cookies are domain-scoped and browser-specific — they can't be read by a Claude Code session running outside the browser. Not a direct replacement.
**Better paths to investigate when mobile install becomes a priority:**
- Web-based installer (hosted page) that stores state in localStorage or a short-lived server-side session
- A stripped-down mobile install flow that does less client-side work (most phases SSH to the server anyway — the only Mac-dependent steps are AWS CLI and the state file)
- The server itself as the state store (once Phase 2 completes, write install state to the Lightsail instance)
**Priority:** Low — Mac/Windows covers the current market. Revisit when mobile install is a product requirement.

---

## Completed / Resolved

| Issue | Resolution | Date |
|---|---|---|
| `apps/command/__main__.py` missing (hard blocker) | Created — 3-line asyncio entry point | 2026-04-08 |
| Script numbering mismatch vs phase numbers | Renamed `05-server-b.sh` → `06-server-b.sh`, `06-verify.sh` → `07-verify.sh` | 2026-04-08 |
| Verify check count wrong (said 11, had 12) | Updated INSTALL.md to "12 checks" | 2026-04-08 |
| Duplicate `# 10.` label in verify script | Fixed — Telegram check now `# 11.`, Node.js check `# 12.` | 2026-04-08 |
| ISSUE-1: IAM key auto-delete | Auto-checks key count; deletes oldest if 2 exist before creating new | 2026-04-08 |
| ISSUE-2: Swap existence guard | Wrapped in `if [ ! -f /swapfile ]` — idempotent, SKIP message on second run | 2026-04-08 |
| ISSUE-3: Node.js pipe fix + auto-retry | Fixed pipe with `set -o pipefail`; version check + single auto-retry | 2026-04-08 |
| ISSUE-4: Bot startup wait | BOT_MAX 5→20 (60s); user-facing message added before wait loop | 2026-04-08 |
| ISSUE-5: Verify check 10 logic gate | Split into two checks: file existence + import test; labels updated 10–13 | 2026-04-08 |
| ISSUE-6: git clone URL quoting | Remote-side REPO_URL variable assignment; no unquoted URL in shell string | 2026-04-08 |
| ISSUE-7: Resume state reload | State writes added for bucket_name (Phase 1) and bot_username (Phase 3B); resume instructions updated | 2026-04-08 |
| ISSUE-8: Wrong requirements.txt | Removed google-analytics-data and google-auth from HealthOS-TEST/requirements.txt | 2026-04-08 |
