# HealthOS Cloud — INSTALL.md

**Version:** 1.0
**Installs:** HealthOS on AWS Lightsail (Ubuntu 24.04, 1GB RAM, static IP)
**Human time:** ~20 minutes (new AWS account) or ~10 minutes (existing account)
**Total time:** ~30 minutes

---

## FOR CLAUDE: Behavior Rules

You are driving this install. Read these rules and follow them exactly.

1. **Execute every step in order.** Do not skip phases. Do not reorder.
2. **Verify before proceeding.** After each automated phase, confirm the output is correct before moving to the next phase.
3. **Pause at every HUMAN STEP.** Give exact instructions. Wait for the user to confirm completion. Do not guess or proceed without confirmation.
4. **Write state after every phase.** Update `install-state-{instance-name}.json` after each phase completes.
5. **If a script fails:** Print the error, explain what went wrong in plain English, give the fix command, ask the user to confirm before retrying.
6. **Never proceed to Phase N+1 if Phase N failed.**
7. **Credentials are sacred.** Never print full credential values in your responses — reference by name only (e.g., "Anthropic key: saved"). Credentials are written to `.env` on the server only.
8. **Collect all inputs in Phase 0 before starting any AWS work.**
9. **All scripts are in `scripts/`.** Run them with `bash scripts/XX.sh`.

---

## State Tracking

Use a per-instance state file named `install-state-{instance-name}.json` (e.g., `install-state-healthos-personal.json`).

Copy `install-state.json` to the per-instance name at the start of Phase 0. Read/write the per-instance file throughout.

After completing each phase, add the phase name to `completed_phases`.

**On resume:** If `completed_phases` is non-empty, ask:
> "I see a previous partial install. Would you like to **resume** from where it left off, or **start fresh**?"
- Resume → skip completed phases, then re-ask for ALL of these secrets before continuing:
  1. Anthropic API key
  2. Telegram bot token (if Phase 3B is incomplete or later)
  3. GitHub repo URL — including the token if it's a private repo (never written to state file)
  4. AWS backup key ID + secret (if Phase 3A complete but Phase 4 not yet run — see recovery note below)
- Start fresh → clear the state file and begin from Phase 0

**AWS backup credential recovery:** The backup key ID and secret are only shown once by AWS. If the session was interrupted after Phase 3A but before Phase 4 and the credentials were lost:
```
aws iam delete-access-key --user-name {iam-backup-user} --access-key-id {key-id-from-state-file}
```
Then re-run Phase 3A — the script will skip user and policy creation and create a fresh access key.

---

## Pre-Install Checklist

Before Phase 0, confirm:
- [ ] User has Claude desktop app open with this folder as workspace (Code tab)
- [ ] User has Telegram on their phone or desktop
- [ ] User has an Anthropic API key (or knows they need one)

If anything is missing:
- Claude desktop: "Download it free at claude.ai — then open the Code tab and set this folder as your workspace"
- Telegram: "Download it free from the App Store or Google Play"
- Anthropic API key: "Get one free at console.anthropic.com → sign up → API Keys → Create key"

**Tell the user upfront:**
> "During this install, macOS will pop up permission dialogs. When you see them:
> - **'claude would like to access files in your Downloads folder'** → click **Allow**
> - **'Allow once' / 'Always allow for project (local)'** → click **Always allow for project (local)**
>
> These are expected — Claude needs these to run the installer."

---

## Phase 0: Collect All Inputs

**Goal:** Gather everything needed before starting. No AWS work yet.

**Before asking, tell the user:**
> "I need a few details before we start. Don't do anything yet — just answer the questions. You can answer all at once (e.g., '1. Yes, 2. healthos-personal, 3. sk-ant-...') or one by one. I'll tell you when to take action."

Ask the user the following (can ask all at once in a friendly, conversational message):

1. **AWS Account:** "Do you already have an AWS account?"
   - Yes → skip Human Step 1
   - No → they'll create one in Human Step 1

2. **Instance name:** Suggest `healthos-personal`. Ask if they want to change it.
   Derived names (tell the user these will be used):
   - Key: `{instance-name}-key`
   - Static IP: `{instance-name}-static-ip`
   - IAM backup user: `{instance-name}-backup`

3. **Anthropic API key:** "Please paste your Anthropic API key."
   Validate immediately:
   ```bash
   curl -s -o /dev/null -w "%{http_code}" \
     https://api.anthropic.com/v1/models \
     -H "x-api-key: THEIR_KEY" \
     -H "anthropic-version: 2023-06-01"
   ```
   - `200` → valid, continue
   - `401` → invalid — ask them to check console.anthropic.com and re-paste
   - Other → network issue, warn and proceed with caution

4. **GitHub repo URL:** The HealthOS app code will be cloned from GitHub onto the server.
   "I need the HealthOS GitHub repo URL to install the app on your server. You received this link in your setup instructions email."
   - Format: `https://TOKEN@github.com/yostai/HealthOS-Clean`
   - The token was provided in your setup email — paste the full URL exactly as given.
   Store this in session memory only — never write to install-state.json.

5. **S3 bucket name:** Will be set after AWS is configured. Use `healthos-backup` as placeholder for now.

Copy `install-state.json` to `install-state-{instance-name}.json`. Write instance name, key name, static IP name, IAM user to the config section.

Mark `phase-0-inputs` complete.

---

## HUMAN STEP 1: AWS Account (~5 min)

**Skip if:** User already has an AWS account.

Tell the user:

---
You need an AWS account to host HealthOS. Good news: your first 3 months of server time are **completely free**.

**Steps:**
1. Go to **aws.amazon.com** → click "Create an AWS Account" (may say "Sign up for AWS" — same thing)
2. Enter your email and choose an account name (e.g., "My HealthOS")
3. Create a password
4. Enter your contact info (AWS may skip the account type screen — that's fine)
5. Enter a credit card (required, but won't be charged for 90 days)
6. Verify your phone number
7. Choose the **Free** support plan (may appear as "Basic support — Free" or "Free (6 months)")
8. Sign in to the AWS Console

**When done:** Tell me "AWS account ready" and I'll continue.
---

Wait for confirmation before proceeding.

---

## Phase 1: Mac Preflight (automated)

**What this does:** Checks if AWS CLI is installed. Installs it automatically if missing. Verifies your AWS credentials.

Run:
```bash
bash "scripts/01-preflight.sh"
```

**If AWS CLI is missing:** The script will download it. Tell the user:
"Run this command in your Mac terminal (you'll be asked for your password):"
```
sudo installer -pkg /tmp/AWSCLIV2.pkg -target /
```
Wait for confirmation, then re-run the script.

**If credentials not configured:** Proceed to Human Step 2.

**If `PREFLIGHT_OK=true`:** Show the user the Account ID and **verify it's the right account:**
> "I found existing AWS credentials on your Mac. They point to account: **[ACCOUNT_ID]**
> Is this the AWS account you just created for HealthOS? (yes/no)"

- **Yes** → proceed. Update S3 bucket name to `healthos-backup-{account-id}`.
- **No** → existing CLI is configured for a different account (personal/work). Tell the user:
  > "We need to point the CLI at your new HealthOS account. Go to your new AWS account → IAM → create a user `healthos-installer` with AdministratorAccess → create an access key → run `aws configure` in your terminal and paste the new credentials."
  > "Tell me when done and I'll verify."
  Re-run `01-preflight.sh` and confirm the correct Account ID before proceeding.

Mark `phase-1-preflight` complete only after account is confirmed correct.

---

## HUMAN STEP 2: AWS Access Key (~3 min)

**Skip if:** Preflight showed valid credentials.

Tell the user:

---
Now we need to give the installer permission to set up your cloud server. This takes about 3 minutes.

**Steps:**
1. Go to **console.aws.amazon.com** → search "IAM" at the top → click IAM
2. In the left sidebar, click **Users** → click **Create user**
3. Username: `healthos-installer` → click Next
4. Select **"Attach policies directly"** → search for and check **AdministratorAccess** → click Next → Create user
5. Click on the user you just created → click **"Security credentials"** tab
6. Scroll to "Access keys" → click **"Create access key"**
7. Choose **"Command Line Interface (CLI)"** → check the box → Next → Create access key
8. **Copy both values** — you'll need them in a moment:
   - Access Key ID (starts with AKIA...)
   - Secret Access Key (long string — only shown once)

**Then open your Mac terminal and run:**
```
aws configure
```
When prompted:
- AWS Access Key ID: paste yours
- AWS Secret Access Key: paste yours
- Default region name: `us-east-1`
- Default output format: `json`

**When done:** Tell me "AWS configured" and I'll verify it.
---

After confirmation, re-run:
```bash
bash "scripts/01-preflight.sh"
```

Confirm `PREFLIGHT_OK=true`. Note Account ID, update S3 bucket name.

---

## Phase 2: AWS Infrastructure (automated)

**What this does:** Creates your cloud server — SSH key, Lightsail instance (Ubuntu 24.04, 1GB RAM), static IP address, firewall. Takes 3-5 minutes.

Run (with actual instance-name, key-name, static-ip-name from Phase 0):
```bash
bash "scripts/02-aws.sh" \
    "INSTANCE_NAME" \
    "KEY_NAME" \
    "STATIC_IP_NAME"
```

**Capture from output:**
- `STATIC_IP=` → server's public IP
- `PEM_PATH=` → SSH key location

**Verify:**
```bash
ssh INSTANCE_NAME "echo 'SSH OK'"
```

Update install-state with `server_ip` and `pem_path`. Mark `phase-2-aws` complete.

---

## Phase 3: S3 Backup + Telegram (automated)

### Part A — S3 Backup

**What this does:** Creates a secure storage bucket for your daily health data backups.

Run:
```bash
bash "scripts/03-backup-infra.sh" \
    "BUCKET_NAME" \
    "IAM_BACKUP_USERNAME"
```

**Capture from output:**
- `AWS_BACKUP_KEY_ID=`
- `AWS_BACKUP_SECRET=`
- `S3_BUCKET=`

Hold these in session memory for Phase 4. Do not print them in your response.

**Important:** These credentials are shown once only. If this session is interrupted before Phase 4 runs, see the recovery note in the State Tracking section above.

Mark `phase-3-backup` complete.

### Part B — Telegram Setup

**What this does:** Connects your Telegram to HealthOS so it can send you health check-ins.

Tell the user:

---
Now let's connect Telegram. This takes about 5 minutes.

**Part A — Create your bot:**
1. Open Telegram on your phone or desktop
2. Search for **@BotFather** (use the @ — don't just search "BotFather")
3. Tap Start → type `/newbot`
4. Enter a name for your bot (e.g., "HealthOS")
5. Enter a username ending in "bot" (e.g., `healthos_yourname_bot`)
6. BotFather sends you a token like `8672576295:AAEf...` — **copy it**

**Part B — Create a group:**
1. Create a new Telegram group (tap compose → New Group)
2. Name it "HealthOS" or anything you like
3. Add your bot to the group by its @username
4. Tap group name → Edit → Administrators → Add Admin → select your bot → confirm
5. **Send any message in the group** (just type "hello")

**When done:** Paste your bot token and I'll automatically find the group.
---

After user provides token, run:
```bash
bash "scripts/03-telegram.sh" "BOT_TOKEN"
```

**Capture from output:**
- `TELEGRAM_GROUP_ID=` (a negative number — that's correct)
- `BOT_USERNAME=`

Store `BOT_USERNAME` for the completion summary. Mark `phase-3-telegram` complete.

---

## Phase 4: Deploy HealthOS to Server (automated)

**What this does:** Clones HealthOS from GitHub onto your server and writes your credentials. App code goes from GitHub straight to your server — nothing lands on your Mac.

Run (with all values collected above):
```bash
bash "scripts/04-workspace.sh" \
    "SERVER_IP" \
    "PEM_PATH" \
    "GITHUB_REPO_URL" \
    "TELEGRAM_BOT_TOKEN" \
    "TELEGRAM_GROUP_ID" \
    "ANTHROPIC_API_KEY" \
    "S3_BUCKET" \
    "AWS_BACKUP_KEY_ID" \
    "AWS_BACKUP_SECRET"
```

**Verify output shows:** `All key files present on server`

Mark `phase-4-workspace` complete.

---

## Phase 5: Server Setup — Part A (automated)

**What this does:** Updates the server's software and installs the base packages HealthOS needs. The server will reboot once — that's normal and required. Takes 3-5 minutes.

Run:
```bash
bash "scripts/05-server-a.sh" \
    "SERVER_IP" \
    "PEM_PATH"
```

The script sends the reboot command and waits for the server to come back up automatically.

**Verify output shows:** `SERVER_A_OK=true`

Mark `phase-5-server-a` complete.

---

## Phase 6: Server Setup — Part B (automated)

**What this does:** Installs Node.js, Claude Code, Python environment, and starts your HealthOS bot as a background service. Takes 5-8 minutes.

Run:
```bash
bash "scripts/05-server-b.sh" \
    "SERVER_IP" \
    "PEM_PATH"
```

**Verify output shows:**
- `SERVER_B_OK=true`
- Bot status: `active (running)`

If bot fails to start:
```bash
ssh INSTANCE_NAME "sudo journalctl -u healthos-bot -n 30"
```

Mark `phase-6-server-b` complete.

---

## Phase 7: Verify Everything (automated)

**What this does:** Runs 11 checks and sends a test message to your Telegram group.

Run:
```bash
bash "scripts/06-verify.sh" \
    "SERVER_IP" \
    "PEM_PATH" \
    "TELEGRAM_BOT_TOKEN" \
    "TELEGRAM_GROUP_ID" \
    "INSTANCE_NAME"
```

**Expected result:** All checks pass. A message arrives in your Telegram group.

If any check fails, the script prints the exact fix command. Run the fix, re-run verify.

Mark `phase-7-verify` complete.

---

## Install Complete

When all phases are done and verify passes, tell the user:

---
🎉 HealthOS is live!

**Your health coach is running 24/7 in the cloud.**

Check your Telegram group — a test message should have just arrived from your bot (BOT_USERNAME).

**What's running on your server:**
- Health check-ins: 8 AM, 10 AM, 3 PM, 6 PM, 10 PM Eastern
- Morning data refresh: 6 AM daily
- Nightly backup of your health data: 11:45 PM daily

**Monthly cost:** ~$7 (server) + ~$0.01 (backup storage)
Your first 3 months are FREE on a new AWS account.

**To access your server:**
```
ssh INSTANCE_NAME
```

**Next:** Your bot will send its first real check-in tonight or tomorrow morning. Just reply to it in Telegram to get started.
---

Write `install-log-{instance-name}.md` at the installer root:
- Date of install
- All resource names (instance, key, static IP, S3 bucket, IAM users)
- SSH command
- Bot username
- Credential file location: `.env` on server at `/home/ubuntu/healthos/.env`

Mark `phase-complete` in install-state.

---

## Error Reference

| Error | Likely Cause | Fix |
|---|---|---|
| `aws: command not found` | AWS CLI not installed | Run `sudo installer -pkg /tmp/AWSCLIV2.pkg -target /` |
| `Unable to locate credentials` | `aws configure` not run | Run `aws configure` with your IAM keys |
| `InvalidClientTokenId` | Wrong access key | Re-run `aws configure` |
| `BucketAlreadyExists` | Bucket name taken globally | Add a suffix like `-v2` to the bucket name |
| `Repository not found` | Wrong GitHub URL or bad token | Check the URL and token provided in Phase 0 |
| `Permission denied (publickey)` | SSH key mismatch | Check `PEM_PATH` — confirm it matches the key pair used |
| `No module named apps.command.__main__` | Missing file in GitHub repo | Check that `apps/command/__main__.py` exists in the HealthOS repo |
| Bot not found when adding to group | Searching by display name | Search by @username (with @ prefix) in Telegram |
| `getUpdates` returns no messages | No message sent to group | Send any message in the group, then retry |
| `SERVER_B_OK` not shown | Phase B failed mid-run | Check SSH, re-run `scripts/05-server-b.sh` |
| AWS backup credentials lost on resume | Session interrupted after Phase 3A | Delete + recreate: `aws iam delete-access-key --user-name {iam-user} --access-key-id {key-id}` then re-run Phase 3A |
