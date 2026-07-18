#!/bin/bash
# SysAdminHCP AI Spam Filter — qmail delivery wrapper
# Placed in .qmail-default (domain-wide) or .qmail-{user} (per-user) by SysAdminHCP.
# Reads the email from stdin, calls sync-filter.php, delivers to .Quarantine (spam)
# or hands off to vdelivermail (ham). Adds X-AI-JRA-Spam-Class and
# X-AI-JRA-Spam-Confidence headers to every processed email.

# Derive install dir from the script's own location — no hardcoded path needed
FILTER_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && cd .. && pwd)"
PHP="/usr/bin/php"
VDELIVERMAIL="/home/vpopmail/bin/vdelivermail"
QUARANTINE_FOLDER=".Quarantine"

# Load config from .env so PHP inherits QMAIL_MAILBOX_ROOT and provider settings
if [ -f "${FILTER_DIR}/.env" ]; then
    set -a
    # shellcheck disable=SC1090
    source "${FILTER_DIR}/.env" 2>/dev/null
    set +a
fi

# MAILBOX_ROOT comes from .env (QMAIL_MAILBOX_ROOT); fall back to vpopmail default
MAILBOX_ROOT="${QMAIL_MAILBOX_ROOT:-/home/vpopmail/domains}"

# Determine recipient from qmail environment variables
# qmail sets EXT (local part) and HOST (domain) during delivery
if [ -n "$EXT" ] && [ -n "$HOST" ]; then
    RECIPIENT="${EXT}@${HOST}"
elif [ -n "$1" ]; then
    RECIPIENT="$1"
else
    # Cannot determine recipient — fail open (deliver normally)
    exec "$VDELIVERMAIL" '' bounce-no-mailbox
    exit $?
fi

# Write stdin to a temp file (we need to read it twice: once for analysis, once for delivery)
TEMP_FILE=$(mktemp /tmp/saf-XXXXXX.eml)
cat <&0 > "$TEMP_FILE"

if [ ! -s "$TEMP_FILE" ]; then
    rm -f "$TEMP_FILE"
    exit 0
fi

# Run synchronous AI analysis
RESULT=$($PHP "$FILTER_DIR/bin/sync-filter.php" "$TEMP_FILE" "$RECIPIENT" 2>/dev/null)

# Extract fields from JSON result
IS_SPAM=$($PHP -r '$d=json_decode(file_get_contents("php://stdin"),true); echo ($d["is_spam"]??false) ? "true":"false";' <<< "$RESULT" 2>/dev/null)
CONFIDENCE=$($PHP -r '$d=json_decode(file_get_contents("php://stdin"),true); echo round(($d["confidence"]??0)*100);' <<< "$RESULT" 2>/dev/null)
IS_SPAM="${IS_SPAM:-false}"
CONFIDENCE="${CONFIDENCE:-0}"

# Prepend spam classification headers to the email (before existing headers)
TAGGED_FILE=$(mktemp /tmp/saf-tagged-XXXXXX.eml)
{
    printf "X-AI-JRA-Spam-Class: %s\r\n" "$IS_SPAM"
    printf "X-AI-JRA-Spam-Confidence: %s%%\r\n" "$CONFIDENCE"
    cat "$TEMP_FILE"
} > "$TAGGED_FILE"
rm -f "$TEMP_FILE"

if [ "$IS_SPAM" = "true" ]; then
    # ── Build one-click whitelist approve link ────────────────────────────────
    APPROVE_LINK=""
    if [ -n "${PANEL_URL}" ] && [ -n "${WHITELIST_SECRET}" ]; then
        # Extract sender email from From: header
        SENDER=$($PHP -r "
\$content = file_get_contents('$TAGGED_FILE');
preg_match('/^From:.*?([a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,})/mi', \$content, \$m);
echo isset(\$m[1]) ? strtolower(\$m[1]) : '';
" 2>/dev/null)
        if [ -n "$SENDER" ]; then
            EXPIRY=$(( $(date +%s) + 604800 ))  # 7 days from now
            TOKEN=$($PHP -r "echo hash_hmac('sha256','approve|${SENDER}|${RECIPIENT}|${EXPIRY}',getenv('WHITELIST_SECRET'));" 2>/dev/null)
            if [ -n "$TOKEN" ]; then
                ENC_SENDER=$($PHP -r "echo rawurlencode('${SENDER}');" 2>/dev/null)
                ENC_RECIP=$($PHP -r "echo rawurlencode('${RECIPIENT}');" 2>/dev/null)
                APPROVE_LINK="${PANEL_URL}/wl-approve?sender=${ENC_SENDER}&recipient=${ENC_RECIP}&expiry=${EXPIRY}&token=${TOKEN}"
            fi
        fi
    fi

    # ── Inject approve notice into the quarantine email ───────────────────────
    FINAL_FILE=$(mktemp /tmp/saf-final-XXXXXX.eml)
    if [ -n "$APPROVE_LINK" ]; then
        $PHP - <<PHPCODE > "$FINAL_FILE" 2>/dev/null
<?php
\$content = file_get_contents('$TAGGED_FILE');
\$link    = '$APPROVE_LINK';
\$notice  = "\r\n-- \r\n[SysAdminHCP Spam Filter] This email was quarantined.\r\nIf it is legitimate, click the link below to whitelist the sender:\r\n\$link\r\n";
// Find header/body separator and inject notice into body
\$pos = strpos(\$content, "\r\n\r\n");
if (\$pos !== false) {
    // HTML email: inject before </body> if present
    \$headers = substr(\$content, 0, \$pos + 4);
    \$body    = substr(\$content, \$pos + 4);
    if (stripos(\$body, '</body>') !== false) {
        \$htmlNotice = "<hr style='margin:20px 0;border:1px dashed #ccc'><p style='font-size:12px;color:#555;font-family:sans-serif'><strong>SysAdminHCP Spam Filter:</strong> This email was quarantined as spam.<br>If it is legitimate, <a href='\$link'>click here to whitelist the sender</a>.</p>";
        \$body = str_ireplace('</body>', \$htmlNotice . '</body>', \$body);
    } else {
        \$body .= \$notice;
    }
    echo \$headers . \$body;
} else {
    echo \$content . \$notice;
}
PHPCODE
        if [ ! -s "$FINAL_FILE" ]; then
            # PHP failed — fall back to original
            cp "$TAGGED_FILE" "$FINAL_FILE"
        fi
    else
        cp "$TAGGED_FILE" "$FINAL_FILE"
    fi
    rm -f "$TAGGED_FILE"

    # ── Deliver to Quarantine folder ──────────────────────────────────────────
    DOMAIN="${RECIPIENT#*@}"
    USER="${RECIPIENT%@*}"
    QUARANTINE_DIR="$MAILBOX_ROOT/$DOMAIN/$USER/Maildir/$QUARANTINE_FOLDER"

    # Create Maildir++ quarantine folder if it doesn't exist yet
    if [ ! -d "$QUARANTINE_DIR/new" ]; then
        mkdir -p "$QUARANTINE_DIR/new" "$QUARANTINE_DIR/cur" "$QUARANTINE_DIR/tmp"
        touch "$QUARANTINE_DIR/maildirfolder"
        chown -R vpopmail:vchkpw "$QUARANTINE_DIR" 2>/dev/null
        chmod 700 "$QUARANTINE_DIR" 2>/dev/null
    fi

    # Deliver with a unique Maildir filename
    FILENAME="$(date +%s).P$$.$(hostname -s 2>/dev/null || echo host)"
    cp "$FINAL_FILE" "$QUARANTINE_DIR/new/$FILENAME"
    chown vpopmail:vchkpw "$QUARANTINE_DIR/new/$FILENAME" 2>/dev/null
    chmod 600 "$QUARANTINE_DIR/new/$FILENAME" 2>/dev/null
    rm -f "$FINAL_FILE"
    exit 0
else
    # ── Deliver normally via vdelivermail ────────────────────────────────────
    "$VDELIVERMAIL" '' bounce-no-mailbox < "$TAGGED_FILE"
    DELIVER_EXIT=$?
    rm -f "$TAGGED_FILE"
    exit $DELIVER_EXIT
fi
