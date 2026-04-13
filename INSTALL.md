# HealthOS Cloud — INSTALL.md

**Version:** 0.4.1
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

## Pre-Install Steps (Interactive — One at a Time)

Walk through these three steps one at a time. Complete each fully and get confirmation before moving to the next. Do not present all three at once.

---

### Pre-Install Step 1: Telegram

Greet the user warmly. Then ask:

> "First things first — do you have Telegram installed on your phone or desktop?"

- **Yes** → "Perfect! We'll set up your health coach bot inside Telegram later. On to Step 2."
- **No** → Give these instructions and wait for confirmation:

---
Telegram is the app your health coach will use to check in with you every day. It's free and takes about 2 minutes to set up.

1. On your phone: download **Telegram** from the App Store (iPhone) or Google Play (Android)
   — or on desktop: go to **telegram.org** and download the app
2. Create an account with your phone number
3. Once you're in, let me know and we'll move on!
---

Wait for the user to confirm Telegram is installed before proceeding.

---

### Pre-Install Step 2: Anthropic API Key

Ask:

> "Next — do you have an Anthropic API key? This is what lets your health coach use Claude's AI."

- **Yes** → "Great — go ahead and paste it now so I can verify it's working."
  - Validate immediately:
    ```bash
    curl -s -o /dev/null -w "%{http_code}" \
      https://api.anthropic.com/v1/models \
      -H "x-api-key: THEIR_KEY" \
      -H "anthropic-version: 2023-06-01"
    ```
    - `200` → valid, store in session memory, continue
    - `401` → "That key doesn't seem valid — can you double-check it at console.anthropic.com and paste it again?"
    - Other → network issue, warn and proceed with caution
- **No** → Give these instructions:

---
No problem — here's how to get one. It's free to start.

1. Go to **console.anthropic.com** and sign up (or log in if you already have an account)
2. Click **Manage** in the left sidebar → then **API Keys**
3. Click **Create Key** — give it any name, like "HealthOS"
4. Copy the key — it starts with `sk-ant-api03-...`

⚠️ **Important:** You only get one chance to copy this key. Once you leave that page, it's gone forever. Paste it into your Notes app right now to save it.

Once you have it, paste it here and I'll verify it's working.
---

Wait for the user to paste and validate the key before proceeding. Store in session memory only.

---

### Pre-Install Step 3: AWS Account

Ask:

> "Last one before we dive in — do you already have an AWS account?"

- **Yes** → "Great — we'll use that. One heads-up: when you go to sign in, AWS may show you an 'IAM user sign in' page. If you see that, click **'Sign in using root user email'** at the bottom instead — that's the one you want. Go ahead and sign in and let me know when you're in the AWS Console."
- **No** → Give these instructions and wait for confirmation:

---
AWS is the cloud platform where your health coach will run 24/7. Your first 3 months are completely free, then about $7/month.

1. Go to **aws.amazon.com** → click **"Create an AWS Account"**
2. Enter your email and choose an account name (e.g., "My HealthOS")
3. **Verify your email address** — AWS will send you a code, enter it to continue
4. Create a password
5. Choose **"Personal"** account type
6. Enter your contact info
7. Enter a credit card (required, but won't be charged for 90 days)
8. Verify your phone number
9. Choose **"Basic support — Free"**
10. Sign in to the AWS Console

When you're in, let me know and we'll keep going!
---

Wait for confirmation before proceeding.

---

## Phase 0: Collect Remaining Inputs

**Goal:** Gather the last details needed before starting AWS work. All three pre-install steps must be complete first.

1. **Instance name:** Suggest `healthos-personal`. Ask if they want to change it.
   Derived names (tell the user these will be used):
   - Key: `{instance-name}-key`
   - Static IP: `{instance-name}-static-ip`
   - IAM backup user: `{instance-name}-backup`

2. **S3 bucket name:** Will be set after AWS is configured. Use `healthos-backup` as placeholder for now.

3. **GitHub repo URL:** Read from `installer-config.txt` in this folder (line: `GITHUB_REPO_URL=...`). Do not ask the user for it. Store in session memory only.

Copy `install-state.json` to `install-state-{instance-name}.json`. Write instance name, key name, static IP name, IAM user to the config section.

Tell the user:
> "Perfect — I've got everything I need to get started. Give me just a moment while I check your system and make sure everything is ready before we touch your AWS account."

Mark `phase-0-inputs` complete.

---

## HOW AUTOMATED PHASES WORK

You are running inside Claude Code (the Code tab of the Claude desktop app), which has full bash access. Run all scripts directly — no Terminal windows, no helper files, no user interaction needed.

**Timeout note:** Some phases take 5–8 minutes. When running long phases, use a 600000ms timeout (10 minutes) in your bash call.

---

## Phase 1: Mac Preflight

**What this does:** Checks if AWS CLI is installed (installs it if missing) and verifies AWS credentials.

Run directly (timeout: 5 min):
```bash
bash scripts/01-preflight.sh
```

Tell the user: "Checking your system — just a moment..."

Read the output:
- If `PREFLIGHT_OK=true`: note the AWS Account ID, update S3 bucket name to `healthos-backup-{account-id}`, proceed to Phase 2
- If `credentials not configured`: proceed to Human Step 2
- If AWS CLI was missing and installed: re-run Phase 1

Mark `phase-1-preflight` complete.

---

## HUMAN STEP 2: AWS Access Key (~3 min)

**Skip if:** Phase 1 output showed `PREFLIGHT_OK=true`.

Tell the user:

---
Now we need to give the installer permission to set up your cloud server. Here's what to do — it takes about 3 minutes:

1. In the AWS Console, search **"IAM"** at the top → click IAM
2. In the left sidebar, click **Users** → click **Create user**
3. Username: `healthos-installer` → click Next
4. Select **"Attach policies directly"** → search for and check **AdministratorAccess** → click Next → Create user
5. Click on the user you just created → click the **"Security credentials"** tab
6. Scroll to "Access keys" → click **"Create access key"**
7. Choose **"Command Line Interface (CLI)"** → check the confirmation box → Next
   *(The next screen asks for an optional description — skip it and just click **"Create access key"**)*
8. You're now on the **"Retrieve access keys"** screen — **copy both values:**
   - Access Key ID (starts with AKIA...)
   - Secret Access Key (long string — only shown once!)

**Then paste both values here in the chat** and I'll take care of the rest.
---

Once the user pastes their Access Key ID and Secret Access Key, run these directly (substituting their actual values):
```bash
aws configure set aws_access_key_id "THEIR_ACCESS_KEY_ID"
aws configure set aws_secret_access_key "THEIR_SECRET_ACCESS_KEY"
aws configure set default.region us-east-1
aws configure set default.output json
```

Do not print the key values in your response. Tell the user: "Saving your credentials..." Then re-run Phase 1 to confirm `PREFLIGHT_OK=true`.

---

## Phase 2: AWS Infrastructure

**What this does:** Creates your cloud server — SSH key, Lightsail instance (Ubuntu 24.04, 1GB RAM), static IP, firewall. Takes 3–5 minutes.

Run directly (timeout: 10 min), substituting actual INSTANCE_NAME, KEY_NAME, STATIC_IP_NAME from Phase 0:
```bash
bash scripts/02-aws.sh "INSTANCE_NAME" "KEY_NAME" "STATIC_IP_NAME"
```

Tell the user: "Setting up your cloud server — this takes about 3–5 minutes. Hang tight..."

Read the output and extract:
- `STATIC_IP=` → server's public IP
- `PEM_PATH=` → SSH key location

Update install-state with `server_ip` and `pem_path`. Mark `phase-2-aws` complete.

**If Phase 2 fails with a Lightsail 403 / access error**, tell the user:

---
There's a small hiccup — before Lightsail will work, your AWS account needs two things:

**Step 1 — Upgrade to a paid AWS plan** (required to access Lightsail)
1. Go to **https://console.aws.amazon.com** and sign in
2. In the search bar, type **"Lightsail"** and click it
3. If you see a page saying *"There might be a problem with your access to Lightsail"*, click **"Upgrade plan"** and follow the steps to add a payment method
4. Once upgraded, come back here and let me know

**Step 2 — Activate Lightsail** (takes about 1 minute)
1. After upgrading, go back to the Lightsail page at **https://console.aws.amazon.com**
2. Click **"Let's get started"** or **"Create instance"** — you don't need to finish creating one, just clicking starts the activation
3. Let me know when done and I'll retry

Note: The $7/month Lightsail plan is selected automatically by the installer — you do not need to choose it manually.
---

Once the user confirms both steps are done, re-run Phase 2.

---

## Phase 3: S3 Backup + Telegram

### Part A — S3 Backup

**What this does:** Creates a secure storage bucket for your daily health data backups.

Run directly (timeout: 5 min), substituting BUCKET_NAME and IAM_BACKUP_USERNAME:
```bash
bash scripts/03-backup-infra.sh "BUCKET_NAME" "IAM_BACKUP_USERNAME"
```

Tell the user: "Setting up your backup storage — just a moment..."

Read the output and extract:
- `AWS_BACKUP_KEY_ID=`
- `AWS_BACKUP_SECRET=`
- `S3_BUCKET=`

Hold these in session memory for Phase 4. Do not print them in your response.

**Important:** These credentials are shown once only. If this session is interrupted before Phase 4 runs, see the recovery note in State Tracking above.

Mark `phase-3-backup` complete.

### Part B — Telegram Setup

Tell the user:

---
Now let's connect Telegram. This takes about 5 minutes.

**On your phone:**

**Part A — Create your bot:**
1. Open Telegram and search for **@BotFather** — tap **Open** (not Start)
2. Tap **"+ Create a New Bot"**
3. Enter a name for your bot (e.g., "HealthOS") — copy this name into Notes or somewhere safe, then tell me what you named it
4. Enter a username for your bot (e.g., `healthos_yourname_bot`) — **must end in `_bot`**, and use `_` only (no `-` allowed)
5. Tap **Create Bot**
6. BotFather sends you a token like `8672576295:AAEf...` — **copy it and paste it into Notes** to keep it safe, then paste it here

*(Note your bot's name and token — I'll use them in the next step.)*

**Part B — Create a group:**
1. Tap the **new message button** (top right) → tap **New Group** → if Telegram asks for access to contacts, tap **Next**
2. Tap **Add Members** → search for your bot's @username (e.g., `@{BOT_USERNAME}`) → tap the checkmark (bottom right) to add it → tap Next → name the group (e.g., "HealthOS") → tap Create
3. Tap the group name → Edit → Administrators → Add Admin → select your bot → confirm
4. Go back to the group message screen and **send any message** (just type "hello")

*(Desktop Telegram works similarly but menus may look slightly different — I can help if you get stuck.)*

**When done:** Let me know the bot name you chose and paste your bot token here — I'll connect everything automatically.
---

Store the bot name the user provides in session memory. Once user provides token, run directly (timeout: 3 min), substituting BOT_TOKEN:
```bash
bash scripts/03-telegram.sh "BOT_TOKEN"
```

Tell the user: "Connecting your Telegram bot — just a moment..."

Read the output and extract:
- `TELEGRAM_GROUP_ID=` (a negative number — that's correct)
- `BOT_USERNAME=`

Store `BOT_USERNAME` for the completion summary. Mark `phase-3-telegram` complete.

---

## Phase 4: Deploy HealthOS to Server

**What this does:** Copies your credentials to your server and sets up HealthOS. Takes 2–3 minutes.

Run directly (timeout: 10 min), substituting all values collected above:
```bash
bash scripts/04-workspace.sh \
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

Tell the user: "Deploying HealthOS to your server — give it a couple of minutes..."

Read the output and verify it contains `All key files present on server`. Mark `phase-4-workspace` complete.

---

## Phase 5: Server Setup — Part A

**What this does:** Updates server software and installs base packages. Server will reboot once — that's normal. Takes 3–5 minutes.

Run directly (timeout: 10 min), substituting SERVER_IP and PEM_PATH:
```bash
bash scripts/05-server-a.sh "SERVER_IP" "PEM_PATH"
```

Tell the user: "Setting up your server — it will reboot once during this step, which is normal. Takes about 3–5 minutes..."

Read the output and verify `SERVER_A_OK=true`. Mark `phase-5-server-a` complete.

---

## Phase 6: Server Setup — Part B

**What this does:** Installs the full HealthOS software stack and starts your bot as a background service. Takes 5–8 minutes.

Run directly (timeout: 10 min), substituting SERVER_IP and PEM_PATH:
```bash
bash scripts/05-server-b.sh "SERVER_IP" "PEM_PATH"
```

Tell the user: "Installing your health coach software — this is the longest step, about 5–8 minutes. I'll let you know when it's done..."

Read the output and verify `SERVER_B_OK=true` and bot status `active (running)`. Mark `phase-6-server-b` complete.

---

## Phase 7: Verify Everything

**What this does:** Runs checks on your server and sends a test message to your Telegram group.

Run directly (timeout: 5 min), substituting all values:
```bash
bash scripts/06-verify.sh \
    "SERVER_IP" \
    "PEM_PATH" \
    "TELEGRAM_BOT_TOKEN" \
    "TELEGRAM_GROUP_ID" \
    "INSTANCE_NAME"
```

Tell the user: "Running final checks — just a minute. Check your Telegram group when I give the all-clear."

Read the output. If all checks pass, proceed to Install Complete. If any check fails, the output will show the exact fix — run the fix command directly, then re-run Phase 7.

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

**Next:** Open your Telegram group and type `/setup` — your health coach will walk you through a quick onboarding to personalize your check-ins. After that, your first real check-in will arrive tonight or tomorrow morning.
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
| Lightsail 403 / access denied on Phase 2 | Free AWS plan or Lightsail not activated | See Phase 2 error handler above — upgrade plan, then activate Lightsail |
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
