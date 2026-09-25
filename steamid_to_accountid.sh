#!/usr/bin/env bash
# Convert a SteamID64 (17 digits) to the 32-bit Account ID used by
# RUNE / CODEX emulators:  accountid = steamid64 - 76561197960265728
#
# Usage:
#   ./steamid_to_accountid.sh [steamid64]
#   (no argument = auto-detect the real account from loginusers.vdf)

STEAMID64_BASE=76561197960265728
LOGINUSERS="$HOME/.local/share/Steam/config/loginusers.vdf"

if [ $# -ge 1 ]; then
    SID="$1"
else
    # Current user: SteamID64 key whose block contains "mostrecent" "1"
    SID=$(awk '
        /^[[:space:]]*"7656[0-9]{13}"[[:space:]]*$/ { gsub(/["\t ]/,""); sid=$0 }
        /^[[:space:]]*"mostrecent"[[:space:]]*"1"/ { print sid; exit }
    ' "$LOGINUSERS" 2>/dev/null)
    # Fallback: first SteamID64 in the file
    [ -z "$SID" ] && SID=$(grep -oP '7656[0-9]{13}' "$LOGINUSERS" 2>/dev/null | head -1)
fi

# Validate: 17 digits starting with 76561
if ! [[ "$SID" =~ ^7656[0-9]{13}$ ]]; then
    echo "error: '$SID' is not a valid SteamID64" >&2
    exit 1
fi

ACCOUNTID=$((SID - STEAMID64_BASE))

echo "SteamID64:     $SID"
echo "Account ID:    $ACCOUNTID"
echo "Steam3 form:   [U:1:$ACCOUNTID]"