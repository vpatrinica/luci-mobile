# RUTOS Support & Debugging Walkthrough

This document summarizes the findings, fixes, and recommended workflows for the LuCI -> RUTOS-related work and the runtime crash that was observed during development.

## Summary
- Goal: add robust RUTOS support and fix runtime crashes caused by varying API shapes (Map vs List) returned by devices.
- Outcome: Normalization in `lib/services/api_service.dart` and defensive parsing in UI (`lib/screens/dashboard_screen.dart`, `lib/screens/interfaces_screen.dart`, `lib/state/app_state.dart`) removed the TypeError crash. Builds succeed after AGP/NDK bumps.

## Key Findings
- RUTOS endpoints sometimes return arrays where LuCI returned objects (and vice-versa). Code that indexed JSON with string keys sometimes operated on Lists, causing "type 'String' is not a subtype of type 'int' of 'index'".
- Self-signed certificates and HTTP->HTTPS redirects required the HTTP client to accept certs and follow/normalize redirects.
- Some Android Gradle/AAR metadata required upgrading the Android Gradle Plugin (AGP) and NDK versions.

## Files Changed (important)
- [lib/services/api_service.dart](lib/services/api_service.dart) — added normalization for RUTOS responses (token parsing, response shape normalization).
- [lib/state/app_state.dart](lib/state/app_state.dart) — added helpers to extract interface lists safely.
- [lib/screens/dashboard_screen.dart](lib/screens/dashboard_screen.dart) — replaced fragile wireless parsing with a helper `addInterface()` and guarded UCI access.
- [lib/screens/interfaces_screen.dart](lib/screens/interfaces_screen.dart) — made wireless and UCI parsing resilient to Map/List shapes; improved key generation for interface scrolling.
- [lib/main.dart](lib/main.dart) — added global uncaught-exception logging to `luci_error_log.txt` using `path_provider`.
- `android/settings.gradle.kts`, `android/app/build.gradle.kts` — bumped AGP and `ndkVersion` to satisfy build-time requirements.

## Reproduction & Verification Steps

1) Build and install debug APK on a connected device (example device id shown earlier):

```bash
flutter clean
flutter pub get
flutter build apk --debug
adb -s <device-id> install -r build/app/outputs/flutter-apk/app-debug.apk
flutter run -d <device-id>
```

2) Reproduce the original flow that crashed (open Dashboard). Verify no TypeError appears in the `flutter run` output or `adb logcat`.

3) If still crashing, capture logs:

```bash
adb logcat -d -v time | grep -E "Flutter|Dart|Exception|ERROR|FATAL" > flutter_error_log.txt
```

4) Check `luci_error_log.txt` (app-specific persisted logs) if present:

```bash
adb shell run-as com.cogwheel.LuCIMobile cat files/luci_error_log.txt
```

If `run-as` fails due to non-debuggable install, use `adb logcat` output instead.

## Router Diagnostic Commands (useful during testing)

- Ping:
```bash
ping -c 4 192.168.1.1
```

- SSH and check uptime / reboot history:
```bash
ssh root@192.168.1.1 uptime
ssh root@192.168.1.1 'cat /proc/uptime'
ssh root@192.168.1.1 'last -x | grep reboot | head -n 5'
ssh root@192.168.1.1 'logread | grep -i reboot | tail -n 50'
```

- RUTOS/ubus probe (if available):
```bash
ssh root@192.168.1.1 'ubus call system board'
```

- HTTP probe to the router web UI:
```bash
curl -I http://192.168.1.1
curl -k -I https://192.168.1.1
```

## Why the crash happened (concise)

Code assumed `wireless` and `uci` structures were always Maps with predictable keys. When remote router returned a List (or different nesting), indexing with string keys failed. Fixes use:
- runtime type checks (is Map / is List)
- helpers that normalize or safely extract values
- prefer `int.tryParse(...)` when `signal`/`channel` may be string

## Testing Checklist
- Run `flutter analyze` after edits.
- Run unit or widget tests (if present). This repo includes a `test/` folder with a few tests; run `flutter test`.
- Install debug APK and manually exercise Dashboard and Interfaces screens with devices using LuCI and RUTOS.

## Next Recommended Steps
- Audit additional JSON-access sites across the codebase (search for `[...]` or `['...']` patterns operating on network responses) and add defensive checks.
- Add small unit tests for the parsing helpers in `lib/state/app_state.dart` to ensure Map/List shapes are handled.
- Consider adding a temporary debug endpoint or developer toggle that dumps normalized JSON shapes into app logs for faster troubleshooting of remote device variations.

## Notes & Lessons Learned
- Defensive parsing beats assumptions for networked firmware that may vary across vendors or OS versions.
- Keep the HTTP layer responsible for normalization; the UI should operate on normalized structures.
- When upgrading build toolchain (AGP/NDK), coordinate with native plugin requirements.

If you want, I can:
- add unit tests for the new parsing helpers,
- update `README.md` with a short Troubleshooting section linking this doc,
- or prepare a small PR description for merging these changes.

— End
