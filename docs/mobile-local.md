# Mobile apps (Flutter): local setup, run, test

How to build and run the two Flutter apps on Android against the local backend. Written for a team with **no prior Flutter experience**.
Companion to [local-dev.md](local-dev.md) (backend + Floci), [admin-portal-local.md](admin-portal-local.md) and [user-portal-local.md](user-portal-local.md) (same "throw-away copy" pattern).

> **Status: written from reading the code, not yet run.** Everything under "Known gaps" is open. Fix this doc as you hit real problems.
>
> **The submodules are never edited.** `scripts/Setup-MobileApps.ps1` builds throw-away copies in `mobile-local/` (git-ignored) and puts all local config there. Delete that folder any time; the script recreates it.

## Contents

1. [The two apps](#1-the-two-apps)
2. [Install the tools (once)](#2-install-the-tools-once)
3. [Pick a device](#3-pick-a-device)
4. [Setup and run](#4-setup-and-run)
5. [How the apps reach the backend](#5-how-the-apps-reach-the-backend)
6. [Flutter in 10 minutes](#6-flutter-in-10-minutes)
7. [Test and debug](#7-test-and-debug)
8. [Known gaps](#8-known-gaps)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. The two apps

| | Ticket checker | User app |
|---|---|---|
| Submodule | `rvl-gobcb-checker-app` | `rvl-gobcb-user-app` |
| Who uses it | gate staff scanning tickets | customers booking and showing tickets |
| Flutter / Dart (pinned, exact) | **3.27.1** / 3.6.0 | **3.32.0** / 3.8.0 |
| Backend it calls | `ticketchecker`, `admin` | `booking`, `event`, `ticketing`, `userissue`, `pushnotification`, `admin` |
| Special | camera barcode scanner (local plugin `flutter_barcode_scanner/`) | Firebase, Cognito sign-in (Amplify), webviews |
| Android package | `com.mahfuznow.ticket_checker[.dev]` | `com.ticketbangla.gobcbticket[.dev]` |

Both are Android 8+ / iOS 12+. **iOS cannot be built on Windows** (needs a Mac with Xcode), so this guide is Android only.

Because the pinned versions differ, one Flutter install is not enough. We use **FVM** (Flutter Version Manager): it keeps both SDKs side by side and picks the right one per project.

Both apps use **flavors** (`dev`, `test`, `staging`, `prod`). A flavor decides the app id suffix, the signing key and which `env/.env.<flavor>` file is loaded. Locally we use `dev`.

## 2. Install the tools (once)

About an hour, mostly downloads. PowerShell:

1. **Android Studio**: `winget install Google.AndroidStudio`. Run it once and accept the standard setup (it installs the Android SDK). Then in **More Actions → SDK Manager**:
   - SDK Platforms: **Android 15 (API 35)**
   - SDK Tools: **Android SDK Command-line Tools**, **Platform-Tools**, and (Show Package Details) **NDK 26.1.10909125** (the user app pins this exact NDK)

   Android Studio bundles a JDK, so you do not install Java separately. The script finds it at `C:\Program Files\Android\Android Studio\jbr` (or uses `JAVA_HOME`).
2. **Windows Developer Mode**: `start ms-settings:developers`, switch on. Flutter plugins need symlinks; `flutter pub get` fails without it.
3. **FVM**: `winget install leoafarias.fvm` (ID not verified; if winget cannot find it use `choco install fvm`). Open a **new** terminal afterwards.
4. **Node.js** and **git**: already needed for the portals. `aws` CLI is optional here (used to read Cognito IDs from Floci).
5. Accept the Android licences (answer `y` to all):
   ```powershell
   fvm install 3.32.0
   fvm spawn 3.32.0 doctor --android-licenses
   fvm spawn 3.32.0 doctor
   ```
   Green ticks needed: Flutter, Android toolchain, Android Studio. Ignore the Visual Studio (Windows desktop) and Chrome lines.

`Setup-MobileApps.ps1` installs each app's pinned Flutter version itself (`fvm install`), so step 5 only has to run once for the licences.

## 3. Pick a device

- **Real Android phone (recommended).** Settings → About phone → tap *Build number* 7 times → Developer options → switch on **USB debugging**. Plug in, accept the prompt on the phone, then `adb devices` must list it as `device`. This is the only dependable way to try the checker's camera scanning.
- **Emulator.** Android Studio → Device Manager → Create Device → Pixel, API 34 or 35 (x86_64 image). It needs Windows Hypervisor Platform (Windows Features) and virtualization enabled in BIOS. The emulator has a virtual camera, but scanning a QR code through it is fiddly.

Only one device at a time is simplest. With several connected, pass `-Device <id>` (ids from `adb devices`).

## 4. Setup and run

Prerequisite: the backend is running ([local-dev.md](local-dev.md) steps 1-5) and Floci is seeded (`scripts/Seed-EtpCognitoUsers.ps1`).

```powershell
# prepare both apps (copy, env files, keystores, dependencies); first run is slow
pwsh ./scripts/Setup-MobileApps.ps1

# prepare one app and run it on the connected device
pwsh ./scripts/Setup-MobileApps.ps1 -App user -Run
pwsh ./scripts/Setup-MobileApps.ps1 -App checker -Run
```

Parameters: `-App user|checker|both` (default `both`), `-Flavor dev|test|staging|prod` (default `dev`), `-GatewayPort` (default `5200`), `-Run`, `-Device <id>`.

What the script does, in order:

| Step | Detail |
|---|---|
| Prerequisites | `fvm`, `node`, `git`, Android SDK, `keytool` |
| Copy | `rvl-gobcb-*-app` → `mobile-local/user-app` and `mobile-local/checker-app` (robocopy; keystores, `local.properties`, build caches survive re-runs) |
| Env file | `env/.env.<flavor>` in the copy, pointing at the local gateway. Cognito pool/client IDs come from Floci (`etp-user`, `etp-ticketchecker`, client `etp-local`); placeholders if Floci is down |
| Keystores | The Gradle build signs every variant and reads passwords from `android/local.properties`. The script generates 8 debug/release keystores with `keytool` and writes the passwords there |
| Firebase | User app applies the Google-services Gradle plugin but `google-services.json` is not in the repo, so the script writes a **dummy** one in the copy |
| Dependencies | `fvm install` (the pinned SDK) then `fvm flutter pub get` |
| `-Run` | starts the gateway (once), runs `adb reverse`, then `fvm flutter run --flavor flavor_<flavor> -t lib/main/main_flavor_<flavor>.dart` |

Re-run the script after a Floci reset or re-seed (Cognito IDs change), and after the submodule is updated. First `flutter run` compiles with Gradle and takes several minutes; later runs are fast.

Running by hand later:
```powershell
cd mobile-local\user-app
fvm flutter run --flavor flavor_dev -t lib/main/main_flavor_dev.dart
```
If you run `flutter` outside `mobile-local/`, use `fvm spawn 3.32.0 <command>` (user app) rather than `fvm use`, which would write `.fvmrc` into a submodule.

## 5. How the apps reach the backend

The deployed system has one host that fans out by path: `<host>/booking/api/v1/...`, `<host>/event/api/v1/...`, `<host>/ticketchecker/api/v1/...`. Locally every service has its own port, and each app has one `API_BASE_URL`. So:

```
phone / emulator
  app  --  http://localhost:5200/<service>/api/v1/...
              |  adb reverse tcp:5200 tcp:5200   (phone's localhost -> this PC)
              v
  scripts/mobile-gateway.js :5200  --  /admin -> :5101   /booking -> :5102   /event -> :5103
                                       /pushnotification -> :5105   /scheduler -> :5106
                                       /ticketchecker -> :5107   /ticketing -> :5108
                                       /userissue -> :5110   /utility -> :5111
                                       /identity -> 503 (no backend exists)
```

- The gateway is plain Node with no dependencies. Health: `http://localhost:5200/health`. Log: `mobile-local/gateway.log`.
- `adb reverse` makes `localhost:5200` on the device mean this PC, so the same env file works for a phone and an emulator. It must be repeated after replugging the phone; `-Run` does it each time.
- Without `adb reverse`: an emulator reaches the PC at `10.0.2.2`; a phone at the PC's LAN IP (and Windows Firewall must allow port 5200).
- The user app allows cleartext HTTP (`usesCleartextTraffic="true"`). Not checked for the checker app: if it refuses `http://`, that is the cause.

## 6. Flutter in 10 minutes

- **Dart** is the language; **Flutter** is the UI toolkit. Everything on screen is a *widget* (nested objects). `pubspec.yaml` is the dependency file (like `package.json`); `flutter pub get` installs them.
- **Layout of both apps**: `lib/` (screens, MVVM view models, themes), plus two local packages, `domain/` (models, use cases) and `data/` (API clients, Amplify, repositories). Screens live under `lib/presentation/feature/<name>/`.
- **Entry points**: `lib/main/main_flavor_dev.dart` etc. each set the flavor, then `appMain` loads `env/.env.<flavor>` and refuses to start if a required key is missing.
- **Hot reload**: while `flutter run` is active, press `r` (hot reload, keeps state), `R` (restart), `q` (quit). Saving in an IDE does the same.
- **Editor**: VS Code with the *Flutter* extension, or Android Studio with the Flutter plugin. For the extension to use the right SDK, open `mobile-local/<app>` and run *Flutter: Select SDK*, or point it at `%USERPROFILE%\fvm\versions\<ver>` (FVM's cache; the path can differ).
- **Useful commands** (prefix with `fvm`, run inside `mobile-local/<app>`):

| Command | What it does |
|---|---|
| `fvm flutter doctor -v` | health check of the toolchain |
| `fvm flutter devices` | list phones/emulators |
| `fvm flutter pub get` | install dependencies |
| `fvm flutter analyze` | lint |
| `fvm flutter test` | unit/widget tests in `test/` |
| `fvm flutter clean` | delete build output (first thing to try when builds act strange) |
| `fvm flutter build apk --debug --flavor flavor_dev -t lib/main/main_flavor_dev.dart` | produce an APK in `build/app/outputs/flutter-apk/` |

## 7. Test and debug

- **Unit/widget tests**: `fvm flutter test`. The READMEs list unit testing as a TODO, so expect little coverage.
- **Manual flow** after both apps start: user app → browse events (needs seeded data, `scripts/Seed-EtpData.ps1`); checker app → event list and manual ticket validation.
- **Logs**: `flutter run` prints the app log in the terminal. Debug builds enable the app logger (it prints `API_BASE_URL` etc. at start-up, which also shows whether the env file was picked up). Android system log: `adb logcat`.
- **DevTools**: `flutter run` prints a DevTools URL: widget inspector, network tab, memory.
- **Is the backend reachable from the device?** On a phone, open Chrome to `http://localhost:5200/health` (works through `adb reverse`). You should see JSON.
- **Gateway errors**: `502 upstream_unreachable` in an app response means the backend service on that prefix is not running; `404 no_route` means the app called a path the gateway does not know.

## 8. Known gaps

1. **Signing in against Floci is unsolved.** Both apps sign in with Amplify Flutter (Cognito). Unlike the Angular portals, which the setup scripts patch with a custom `endpoint`, Amplify Flutter has no endpoint override in its config, so it talks to real `cognito-idp.ap-southeast-1.amazonaws.com` and the Floci users do not exist there. Options to investigate: patch `data/lib/service/aws_amplify_service.dart` in the copy, a system-level redirect of the Cognito host, or a shared dev environment from bs23. Until then the apps start but cannot log in; screens that need no token may still work.
2. **`identity` API** (sign-up, OTP, profile, forgot password) has no source in any repo (same as the user portal). The gateway returns 503.
3. **Checker `VDS_CERTIFICATE`** is a placeholder. It is the public certificate used to verify ticket QR signatures; ask bs23, or derive it from the Ticketing service signing key ([local-dev.md](local-dev.md)).
4. **Firebase is dummy** (`google-services.json`, `FIREBASE_*`). Analytics and push notifications do nothing.
5. **WebSocket** (`userissue` chat hub) is not proxied by the gateway.
6. **Dart-side path style is unverified**: the env files end in `/` because the clients use relative paths like `booking/api/v1/...`. If the first API call hits `http://localhost:5200booking/...`, remove or add the trailing slash in the script.
7. `flutter` may rewrite `android/local.properties`. The script re-adds missing keystore passwords on each run; if a build says "keystore password was incorrect", re-run it.
8. **iOS** is out of scope (needs macOS).

## 9. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `fvm: command not found` | Not installed, or the terminal was opened before install. Open a new terminal |
| `Building with plugins requires symlink support` | Windows Developer Mode is off (section 2, step 2) |
| `Android sdkmanager not found` / licences error | Install *Command-line Tools* in SDK Manager, then `fvm spawn 3.32.0 doctor --android-licenses` |
| `NDK ... not found` / NDK download hangs | Install NDK 26.1.10909125 in SDK Manager (user app) |
| `File google-services.json is missing` | Re-run the setup script (it writes the dummy file in the copy) |
| `Could not read local.properties` / keystore password error | Re-run the setup script; make sure you build inside `mobile-local/`, not the submodule |
| `Missing required environment variables: [...]` | The app list in `lib/main/main.dart` has a key the env file lacks; re-run the script, or add the key to `mobile-local/<app>/env/.env.dev` |
| `NO MATCH FOUND` in Gradle output | You ran `gradlew` directly. Always pass `--flavor flavor_<name>` through `flutter run/build` |
| Gradle: `Unsupported class file major version` | Wrong JDK. Unset `JAVA_HOME` or point it at Android Studio's `jbr` |
| `adb devices` shows `unauthorized` | Accept the RSA prompt on the phone; or `adb kill-server` and replug |
| App shows network errors | Check `http://localhost:5200/health` on the device, that `adb reverse` ran (`adb reverse --list`), and that the backend is up (`./status.ps1`) |
| Login fails | Known gap 1 |
| Build behaves strangely after a submodule update | `fvm flutter clean`, delete `mobile-local/<app>`, re-run the script |

## Before you finish any task

`git status --porcelain` inside `rvl-gobcb-user-app` and `rvl-gobcb-checker-app` must be empty. All generated files live in `mobile-local/`, which is git-ignored.
