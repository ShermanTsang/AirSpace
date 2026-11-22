# AirSpace project instructions

## Testing a DV build while the stable app is installed

A **DV build** means any locally built developer/debug binary or local release candidate, for example:

- `./run-debug.sh` / `.debug/AirSpaceApp` (bundle id `com.github.shermantsang.airspace.debug`)
- Xcode `AirSpace-Debug.app`
- a locally built `AirSpace.app` that is not the stable app in `/Applications`

The stable app is `/Applications/AirSpace.app` by default (override with `AIRSPACE_STABLE_APP`).

### Required sequence

1. **Detect the stable app before starting the DV build.**
   - Check the exact stable process, not just any process named `AirSpace`:
     ```bash
     stable_app="${AIRSPACE_STABLE_APP:-/Applications/AirSpace.app}"
     stable_pid="$(pgrep -f "${stable_app}/Contents/MacOS/AirSpace" | head -n1 || true)"
     stable_sock="/tmp/com.github.shermantsang.airspace-$(id -un).sock"
     ```
   - A live stable server also has `stable_sock` and answers through the stable CLI (`~/.local/bin/airspace`).
   - Do not treat a stale socket file as proof that the app is running.

2. **If the stable app is running, quit it gracefully before launching the DV build.**
   - Record that it was running:
     ```bash
     stable_was_running=0
     if [[ -n "$stable_pid" ]]; then
       stable_was_running=1
       kill -TERM "$stable_pid"
       for _ in {1..50}; do
         kill -0 "$stable_pid" 2>/dev/null || break
         sleep 0.1
       done
       kill -0 "$stable_pid" 2>/dev/null && kill -KILL "$stable_pid"
     fi
     ```
   - Wait until the stable socket disappears before starting DV:
     ```bash
     for _ in {1..50}; do
       [[ ! -S "$stable_sock" ]] && break
       sleep 0.1
     done
     ```
   - Never start the DV build while the stable server is still running.

3. **Start the DV build only after the stable server is gone.**
   - Prefer the Debug identity (`./run-debug.sh`), which uses the separate debug socket.
   - Do not run two processes that share the stable bundle id or the stable socket. If a DV release candidate uses the stable bundle id, it must not run concurrently; use the Debug identity or a separate identity/socket, and still stop/restore stable explicitly.

4. **Always restore the stable app after testing.**
   - Quit the DV build first and wait for its process/socket to stop.
   - If `stable_was_running=1`, relaunch the exact stable path:
     ```bash
     open "$stable_app"
     for _ in {1..100}; do
       [[ -S "$stable_sock" ]] && break
       sleep 0.1
     done
     ~/.local/bin/airspace --version
     ~/.local/bin/airspace list-monitors
     ```
   - If the stable app was not running before the test, leave it stopped.
   - If it was running but intentionally disabled before the test, restore that state rather than forcing `enable on`.

### Do not rely on the built-in debug toggle

The app has a best-effort debug-only handoff:

- `Sources/AppBundle/initAppBundle.swift` sends `enable off` to the stable socket when a Debug build starts.
- `Sources/AppBundle/util/appBundleUtil.swift` sends `enable on` when the Debug build exits cleanly.

It is not a substitute for this rule. It does not remember whether the stable app was running or enabled, it only works in one direction at startup, and a crash, `SIGKILL`, launch-order change, or protocol mismatch can leave the stable app disabled. The explicit stop/restore sequence above is the source of truth.

### References

- `Sources/Common/appMetadata.swift` — stable vs Debug bundle ids and names
- `Sources/Common/util/commonUtil.swift` — socket path
- `Sources/AppBundle/server.swift` — `toggleReleaseServerIfDebug`
- `Sources/AppBundle/initAppBundle.swift` — startup order; the socket starts only after Accessibility is granted
