# Default iOS test photo library

Validation on 2026-10-20: Apple silicon, Xcode 26.2, iOS Simulator 26.2.

iOS launch requests without an explicit setting receive `SIMRUN_PHOTO_LIBRARY=1` before the App is spawned. The request and the host PID authorization check therefore agree. Explicit values are preserved; `0` disables support and invalid values remain disabled. The watchOS default is unchanged. The library remains at `SIMRUN_DATA/Media`, separate from the Mac Photos library. Usage descriptions and an actual App authorization request are still required.

The unchanged native PhotoTest fixture passed 39 checks against the rebuilt GUI host:

| Case | Checks | Result |
|---|---:|---|
| No supplied flag: request, import, asset fetch, thumbnail and original data | 15 | Pass |
| Same profile after relaunch: authorization and image persist | 5 | Pass |
| Fresh profile before request: backend access denied | 4 | Pass |
| Add-only request: import allowed, read permission withheld | 7 | Pass |
| Explicit `0`: request and backend denied | 4 | Pass |
| Invalid explicit value: request and backend denied | 4 | Pass |

Build: `make core build/apps/PhotoTest.app SIMRUN_DEVICES=1`; strict deep signature verification passed. Local Xcode 26.2 required the already documented build-only SDK compatibility include, which is excluded from the change.

MIT attribution remains unchanged. No private App, photo, SDK header, raw log, account or screenshot is committed. Host screen capture permission and business photo capture are separate acceptance gates.

Refs #16.
