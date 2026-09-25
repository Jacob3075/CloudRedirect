#!/bin/bash
# Verify CloudRedirect sync: compares Proton-prefix saves against the cloud
# provider folder (blobs + state.cloudredirect manifest).
# Usage: verify_sync.sh [appid]   (default: 1903340)

APPID="${1:-1903340}"
ACCOUNT="929878890"
STEAMID="${STEAMID:-76561198890144618}"
PREFIX="/home/jacob/Games/Steam Lib/steamapps/compatdata/$APPID/pfx/drive_c/users/steamuser/AppData/Local"
GAMEDIR="$PREFIX/Sandfall/Saved/SaveGames/$STEAMID"
TARGET="/home/jacob/Games/SteamCloudRedirect/$ACCOUNT/$APPID"
STATE="$TARGET/state.cloudredirect"

if [ ! -d "$GAMEDIR" ]; then echo "Prefix dir not found: $GAMEDIR"; exit 1; fi
if [ ! -f "$STATE" ]; then echo "Manifest not found: $STATE"; exit 1; fi

echo "=== CloudRedirect sync check for app $APPID ==="
printf "%-28s %-8s %-10s %s\n" "FILE" "STATUS" "SIZE" "NOTE"
ok=0; stale=0; missing=0; extra=0

# Check every local save file against manifest + blobs
while IFS= read -r f; do
    rel="${f#$PREFIX/}"
    sha=$(sha1sum "$f" | cut -d' ' -f1)
    size=$(stat -c %s "$f")
    mtime=$(stat -c %Y "$f")

    # Manifest SHA + timestamp for this file
    msha=$(python3 -c "
import json,sys
state=json.load(open('$STATE'))
files=state.get('files', state)
e=files.get('$rel')
print(e['sha'] if e else 'MISSING_FROM_MANIFEST')
" 2>/dev/null)

    blob="$TARGET/blobs/$rel/$sha"
    if [ "$msha" = "MISSING_FROM_MANIFEST" ]; then
        printf "%-28s %-8s %-10s not on cloud yet (will upload at exit)\n" "${rel##*/}" "NEW" "$size"
        missing=$((missing+1))
    elif [ "$sha" = "$msha" ]; then
        if [ -f "$blob" ]; then
            mts=$(python3 -c "
import json,datetime
state=json.load(open('$STATE'))
print(int(state.get('files', state)['$rel']['ts']))")
            if [ "$mtime" -lt "$mts" ]; then
                printf "%-28s %-8s %-10s local OLDER than cloud (%s) - may be overwritten!\n" \
                    "${rel##*/}" "OK" "$size" "$(date -d @$mts '+%m-%d %H:%M')"
                stale=$((stale+1))
            else
                printf "%-28s %-8s %-10s local=cloud\n" "${rel##*/}" "OK" "$size"
                ok=$((ok+1))
            fi
        else
            printf "%-28s %-8s %-10s manifest OK but blob file missing\n" "${rel##*/}" "WARN" "$size"
            missing=$((missing+1))
        fi
    else
        printf "%-28s %-8s %-10s differs from cloud (uploads at next exit sync)\n" "${rel##*/}" "CHANGED" "$size"
        stale=$((stale+1))
    fi
done < <(find "$GAMEDIR" -type f -name "*.sav")

# Manifest files with no local copy
python3 -c "
import json
state=json.load(open('$STATE'))
files=state.get('files', state)
for k in files:
    if not __import__('os').path.exists('$PREFIX/'+k):
        print('%-28s %-8s %-10s in cloud, absent locally' % (k.split('/')[-1], 'CLOUD-ONLY', files[k]['size']))
"

echo
echo "Summary: ok=$ok changed/older=$stale new/missing=$missing"
echo "Manifest CN: $(cat "$TARGET/cn.cloudredirect" 2>/dev/null)"
