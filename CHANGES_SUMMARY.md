# CloudRedirect — Current Changes Summary

> **Purpose:** Explain what the uncommitted changes in this repo do and why, informed by the code diff, the opencode session `ses_f78eb253cffeW083A66SgUJ0wj` ("Steam cloud redirect save detection issues", 360 messages, ~4.3M input tokens), and the repo context.

---

## Overview

CloudRedirect (CR) is an open-source project that provides "Steam Cloud" sync for games that lack native cloud support, primarily on Linux via Proton/Wine prefixes. It intercepts Steam Cloud API calls and redirects save file reads/writes to a configurable local folder or a cloud storage provider (S3, R2, etc.).

The current uncommitted changes fix **two related bugs** discovered while debugging save detection for specific games on a native Linux Steam install with multiple Steam libraries.

---

## The Two Bugs

### Bug 1 — Save files not detected for games in non-default Steam libraries (`autocloud_scan.cpp`)

**Symptom:** Expedition 33 (app 1903340) was never detected, even though its Proton prefix and save files existed in the correct location. Ball x Pit (2062430) in the same library worked fine.

**Root cause:** The compatdata path was hardcoded to the **default** Steam library:

```cpp
// BEFORE (broken):
std::string compatdataBase = steamPath + "/steamapps/compatdata/" + std::to_string(appId);
// steamPath = "/home/jacob/.local/share/Steam" (default library)
// But E33's prefix actually lives at:
// /home/jacob/Games/Steam Lib/steamapps/compatdata/1903340
```

The user has 3+ Steam libraries (default `~/.local/share/Steam`, `~/Games/Steam Lib`, `~/Shared/Steam`, plus mounted ones). E33 was installed in `~/Games/Steam Lib` — a non-default library whose path contains a space. CR always searched the default library, so it never found the prefix.

**Additional complications:**

1. **UE games and placeholder SteamIDs:** Some UE games (e.g. Clair Obscur: Expedition 33, Cronos) resolve their save directory from a fixed placeholder SteamID instead of the logged-in account. The actual save files sit in a sibling `765611988...` directory while the token-expanded root stays empty.

2. **Modern vs legacy AppData paths:** Modern Proton prefixes use `AppData/Local` and `AppData/Roaming` directories, but older or Wine-specific setups may only have the legacy junctions `Local Settings/Application Data` and `Application Data` (Wine creates these but they may be empty). CR was hardcoding legacy paths, missing saves that only exist in modern locations.

### Bug 2 — Synced files landing in the wrong folder (`cloud_hooks.cpp`, `cli.cpp`, `backend.cpp`)

**Symptom:** The user configured the sync folder as `/home/jacob/Games/SteamCloudRedirect` via the CR UI, but save data was being stored in `~/.config/CloudRedirect/tokens_folder.json/` — a directory that was somehow created where a file should be.

**Root cause:** When the provider is `"folder"` (or `"local"`), the Linux cloud hooks called `ResolveProviderTokenPath()` which resolved to `~/.config/CloudRedirect/tokens_folder.json`. `LocalDiskProvider` then treated this as a storage root and created it as a directory, storing blobs there instead of the configured sync path. The `folder` provider should use `sync_path`/`sync_folder_path` from config — not the token resolution path — because `tokens_folder.json` is meant for credential files, not storage.

---

## What Each Changed File Does

### `src/common/autocloud_scan.cpp` (+168 lines, −25 lines)

**The main fix.** Three additions:

1. **`FindCompatdataBase(steamPath, appId)`** — Searches **every** configured Steam library for `steamapps/compatdata/<appId>`, returning the first match. Falls back to the default steamPath if not found anywhere. This replaces all hardcoded `steamPath + "/steamapps/compatdata/" + appId` calls. Used in 3 places: `DetectEffectivePlatform()`, `GetFileList()`, and `GetRootTokenDirectories()`.

2. **`PickExistingPrefixDir(pfxBase, modern, legacy)`** — Checks whether the modern path (e.g., `pfx/drive_c/users/steamuser/AppData/Local/`) exists as a directory; if so, uses it. Otherwise falls back to the legacy junction (e.g., `Local Settings/Application Data/`). Replaces hardcoded legacy path strings in `GetFileList()` and `GetRootTokenDirectories()`.

3. **Sibling SteamID directory scanning** — After the primary scan root is set, checks if the scan root leaf name looks like a SteamID (`7656119...`, 17 digits). If so, scans all sibling directories in the parent, and for each matching sibling, also scans it with the cloud path adjusted to use that sibling's SteamID. This handles UE games that namespace saves under a different SteamID than the logged-in account.

   The directory iteration logic (recursive/non-recursive) was refactored to iterate over the `scanTargets` vector (primary + siblings) instead of a single `scanRoot`.

### `src/common/cli.cpp` (+11 lines, −4 lines)

`ReadSyncPath()` now:
- First tries `sync_path` (if present and non-empty) — the key the native side reads
- Falls back to `sync_folder_path` — the legacy key the Linux UI used to write

This ensures the CLI can read configs written by either the new or old UI.

### `src/platform/linux/cloud_hooks.cpp` (+50 lines, −8 lines)

During `EnsureInitialized()`, when the provider is `"folder"` or `"local"`:
- Reads `sync_path` from config (falls back to `sync_folder_path`)
- Appends `/` if missing
- Passes this as the init path directly — **never** calls `ResolveProviderTokenPath()` for folder providers
- Logs use "path" instead of "credentials path"

For non-folder providers (S3, R2, etc.), behavior is unchanged.

### `ui-linux/src/backend.cpp` (+47 lines, −5 lines)

Three changes:

1. **`loadConfig()`**: Reads `sync_path` first, falls back to `sync_folder_path` (mirror of CLI fix).

2. **`saveConfig()`**: Now writes `sync_path` in addition to the legacy `sync_folder_path`, so the native side will read the right key even on a fresh config.

3. **`switchActiveProvider()`**: For folder/local providers:
   - Does **not** call `resolveTokenPath()` (no credential file for these providers)
   - **Removes** any stale entry from `token_paths` in config.json, so the resolver never sees `tokens_folder.json` as a credential path
   - Removes `token_path` key
   For non-folder providers: unchanged.

---

## Untracked Files

### `verify_sync.sh`

A diagnostic shell script to verify CR sync state. Compares Proton-prefix save files against the cloud provider folder (blobs + `state.cloudredirect` manifest). For each save file, reports:
- **OK** — local matches cloud manifest and blob exists, local is newer
- **STALE** — local older than cloud, or content differs (may be overwritten on next sync)
- **NEW/MISSING** — not yet uploaded to cloud
- **CLOUD-ONLY** — in manifest but absent locally

Usage: `./verify_sync.sh [appid]` (default: 1903340). Includes a SteamID env var override.

### `build32/`, `build32b/`, `build32c/`, `build32d/`

Four build directories created during testing of the fixes. Contain CMake build artifacts (Makefiles, CMakeCache, compiled `cloud_redirect.so` and `cloud_redirect_cli` binaries). These are build outputs, not source changes. They should not be committed.

---

## How These Fixes Relate to the Session History

The session `ses_f78eb253cffeW083A66SgUJ0wj` documented the full debugging journey:

1. **Aug 30, 2026** — User reported E33 saves not detected + wrong save location
2. **Subagents** explored repo structure, configs, logs, and Steam paths in parallel
3. **Root causes identified** — the two bugs described above, with log evidence and on-disk verification
4. **Fixes implemented** across all 4 modified files
5. **Testing** — user ran `verify_sync.sh`, deleted stale data in prefix for clean rerun, tested with E33 and Ball x Pit
6. **User concern** — asked whether code changes could result in account flagging (no risk: no Steam API changes, only path resolution logic)
7. **Ongoing debugging** — session also covered troubleshooting VPN/protonvpn connectivity issues on a separate home server system, and various game-specific save detection edge cases

A detailed `ISSUES_REPORT.md` was created during the session (not committed) documenting the debugging log with environment details, log excerpts, and root cause analysis.

---

## Context from Git History

The repo is at commit `bc5e38a`. Recent relevant history:
- `bc5e38a` — Removed the SteamTools patcher (no longer needed)
- `870afdb` — Ignored release output folders, set 2.6.5 release date
- `75b87cf` — Started removing SteamTools features (achievement fetch removed for OST)
- `6971e39` — Preserve stats cache when Steam/network is unreliable
- `ea671c8` — Smarter SLSSteam config watching
- `784a506` — Fix last played stuff on Linux

The project is at v2.6.5 (per `Version.props`), running on Linux with native Steam (not Flatpak), 32-bit client + 64-bit webhelper, glibc 2.44, GCC 16.2.1.
