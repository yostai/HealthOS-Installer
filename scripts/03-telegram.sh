#!/bin/bash
# 03-telegram.sh — Capture Telegram group ID via getUpdates API
# Usage: bash 03-telegram.sh <bot-token>
# Prerequisites: User must have sent at least one message to the group after adding the bot
#
# Outputs (printed to stdout):
#   TELEGRAM_GROUP_ID=<id>

set -e

BOT_TOKEN="${1}"

if [ -z "$BOT_TOKEN" ]; then
    echo "ERROR: Bot token required"
    echo "Usage: bash 03-telegram.sh <bot-token>"
    exit 1
fi

echo "=== Telegram Group ID Capture ==="
echo ""

MAX_RETRIES=3
RETRY=0

while [ $RETRY -lt $MAX_RETRIES ]; do
    echo "Calling getUpdates API (attempt $((RETRY + 1))/$MAX_RETRIES)..."

    RESPONSE=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getUpdates")

    # Parse group ID with Python (avoids jq dependency)
    GROUP_ID=$(echo "$RESPONSE" | python3 - <<'PYEOF' || true
import sys, json

try:
    data = json.loads(sys.stdin.read())
    if not data.get("ok"):
        print("ERROR: " + str(data.get("description", "API error")))
        sys.exit(1)

    results = data.get("result", [])
    if not results:
        print("NO_MESSAGES")
        sys.exit(0)

    # Find the first group chat message
    for update in reversed(results):
        msg = update.get("message", update.get("channel_post", {}))
        chat = msg.get("chat", {})
        chat_type = chat.get("type", "")
        if chat_type in ("group", "supergroup"):
            print(chat["id"])
            sys.exit(0)

    print("NO_GROUP")
except json.JSONDecodeError:
    print("ERROR: Invalid API response")
    sys.exit(1)
PYEOF
)

    if echo "$GROUP_ID" | grep -q "^-"; then
        # Negative number = valid group ID
        echo "  OK: Group ID captured"

        # Get bot username via getMe
        ME=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getMe")
        BOT_USERNAME=$(echo "$ME" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['result']['username'])" 2>/dev/null || echo "unknown")

        echo ""
        echo "=== Telegram Setup Complete ==="
        echo ""
        echo "TELEGRAM_GROUP_ID=$GROUP_ID"
        echo "BOT_USERNAME=@$BOT_USERNAME"
        exit 0
    elif [ "$GROUP_ID" = "NO_MESSAGES" ]; then
        echo "  No messages found yet."
        if [ $RETRY -lt $((MAX_RETRIES - 1)) ]; then
            echo "  Please send a message in your Telegram group, then waiting 10s..."
            sleep 10
        fi
    elif [ "$GROUP_ID" = "NO_GROUP" ]; then
        echo "  Messages found but no group chat detected."
        echo "  Make sure you sent the message in a GROUP (not a direct message to the bot)."
        if [ $RETRY -lt $((MAX_RETRIES - 1)) ]; then
            echo "  Waiting 10s..."
            sleep 10
        fi
    else
        echo "  ERROR: $GROUP_ID"
        exit 1
    fi

    RETRY=$((RETRY + 1))
done

echo ""
echo "ERROR: Could not capture group ID after $MAX_RETRIES attempts."
echo ""
echo "Troubleshooting:"
echo "  1. Make sure you added the bot to a GROUP (not a channel)"
echo "  2. Make sure you made the bot an ADMIN in the group"
echo "  3. Send a message in the group (any text), then re-run this script"
echo ""
echo "Manual alternative:"
echo "  curl 'https://api.telegram.org/bot${BOT_TOKEN}/getUpdates' | python3 -m json.tool"
echo "  Look for: result[].message.chat.id"
exit 1
