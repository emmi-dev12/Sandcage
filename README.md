# Sandcage

**Inspect and constrain macOS app behavior in real time.**

Sandcage runs applications inside `sandbox-exec` profiles and shows you exactly what they try to do — file reads and writes, network calls, process spawning — as it happens. When you've seen enough, turn what you observed into a tighter policy with one click.

> Requires **macOS 13 Ventura or later**.

---

## The core loop

```
Drop app → pick preset → run → watch violations stream in → Build Profile → re-run
```

1. **Drop** any `.app` or binary onto the window
2. **Pick** a security preset (Read Only, No Network, Full Lockdown)
3. **Run** it — violations appear live as the app executes
4. When the run finishes, click **Build Tighter Profile**
5. Review the auto-generated SBPL rules, tweak if needed, save — and repeat

You're not just watching a sandbox. You're building one.

---

## Features

- **Live violation feed** — every denied and reported operation shown in real time, per process, with operation type, resource path or hostname, and timestamp
- **Build Profile from violations** — auto-generates SBPL deny rules from what you observed; opens in the editor pre-seeded and ready to save
- **Copy SBPL Rule** — right-click any violation to copy its exact rule to the clipboard for manual tuning
- **Three built-in security presets** as starting points:

  | Preset | What it constrains |
  |---|---|
  | Read Only | All writes, network, and child processes |
  | No Network | All inbound and outbound network traffic |
  | Full Lockdown | Everything except an isolated temp directory |

- **Custom profiles** — write or edit SBPL directly in a built-in editor with syntax validation
- **Run history** — every sandbox run stored with its full violation log, stdout, and stderr
- **Menu bar integration** — active sandboxes and live violation counts at a glance
- **Drop-zone UX** — drag any `.app` or binary straight onto the window; no config required

---

## Install

### From source

```bash
git clone https://github.com/emmi-dev12/sandcage.git
cd sandcage
make install
```

Builds a release `.app` bundle and copies it to `/Applications`. You'll need Xcode Command Line Tools installed (`xcode-select --install`).

### Makefile targets

| Target | What it does |
|---|---|
| `make` / `make bundle` | Release build → `Sandcage.app` in the project directory |
| `make install` | Build and install to `/Applications` |
| `make uninstall` | Remove from `/Applications` |
| `make build` | Debug build for development (no app bundle) |
| `make clean` | Remove build artifacts and local `Sandcage.app` |

### Requirements

- macOS 13 Ventura or later
- Xcode Command Line Tools
- `/usr/bin/sandbox-exec` present (ships with macOS)

---

## How it works

Sandcage wraps your target binary in `sandbox-exec` with the SBPL profile you choose, and simultaneously streams `com.apple.sandbox` log events via `log stream --predicate`. Violation events are parsed by PID and surfaced in the UI in real time.

When you click **Build Tighter Profile**, `SBPLGenerator` groups the observed deny violations by operation type and emits explicit deny rules — file-write denials keyed to parent directories, file-reads to literal paths, network calls to hostnames, process launches to binary paths — layered on top of a permissive base that allows the app to load at all. The result opens in the profile editor so you can review, adjust, and save before the next run.

---

## Honest limitations

`sandbox-exec` is powerful but imperfect:

- **Deprecation risk.** Apple hasn't announced removal, but the API is undocumented and can change at any macOS release. Use Sandcage for inspection and development hardening, not as a production security boundary.
- **Child processes** spawned before the profile loads may escape containment.
- **GPU / Metal operations** are not covered by SBPL.
- **Log-based monitoring** can miss violations under very high event throughput or when the system log is under pressure.
- **Not App Store distributable.** Sandcage itself cannot be App Sandbox'd because it needs to spawn arbitrary subprocesses (`sandbox-exec`, `log`). Distribute as a notarized Developer ID application.

---

## Technical notes

- Built with **SwiftUI** and **Swift Package Manager** — no Xcode project required to build
- Violation monitoring uses `log stream --style ndjson` filtered on the `com.apple.sandbox` subsystem
- Custom profiles saved to `~/Library/Application Support/Sandcage/Profiles/`
- Run history saved to `~/Library/Application Support/Sandcage/Runs/`
- Hardened Runtime enabled; codesign with a Developer ID certificate before distributing

---

## License

MIT
