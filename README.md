# FraudShield (P10): real-time fraud alerts and dispute management

Flutter Banking Capstone, project P10. Customers get an alert for an
unusual payment, answer "Yes, it was me" or "No, it wasn't me" (which
blocks the card or UPI ID and opens a dispute case in one step), raise
guided disputes with evidence, and track each case against its SLA.

**No backend to install.** The bank server runs inside the app
(`lib/mock_server`), and it follows the API contract of the problem
statement exactly: integer paise, ISO dates, the error shape,
`Idempotency-Key`, and a live alert stream (Server-Sent Events).

**Real fingerprint / face unlock on phones** (local_auth), with the phone's
PIN or pattern as fallback. The Android and iOS setup for it is already
done in this project.

Demo login: **Customer ID `TEST_CUSTOM`, PIN `0123456789`**
On Chrome, Windows, or a phone with no screen lock, an on-screen demo
fingerprint prompt appears instead (its device PIN is **`1234`**).

---

## 1. Run it

You need Flutter **3.29 or newer** (`flutter --version`).

### Option A: open this folder (easiest)

```bash
cd fraud_shield
flutter pub get
flutter run
```

Pick any device: **Chrome**, **Windows**, an Android emulator or phone, or
an iPhone. The packages are `flutter_riverpod`, `go_router`, `dio` and
`local_auth`; `flutter pub get` fetches them.

### On an Android phone

Build the APK (the first build downloads Android tools and can take
20+ minutes; later builds take a minute or two):

```bash
flutter build apk --release --obfuscate --split-debug-info=build/symbols
```

The file is `build/app/outputs/flutter-apk/app-release.apk` (works on any
Android 7.0+ phone). Copy it to the phone (USB, Google Drive, or send it to
yourself on WhatsApp), open it, allow "Install unknown apps" when asked,
and tap Install. If Play Protect warns about an unknown developer, choose
"Install anyway".

With a USB cable and USB debugging turned on, you can instead run
`flutter run` (with hot reload) or `flutter install`.

For a smaller file per phone: `flutter build apk --split-per-abi`, then
use `app-arm64-v8a-release.apk` (most phones from the last 8 years).

If you later point the app at a real server (`API_BASE_URL`), add
`<uses-permission android:name="android.permission.INTERNET"/>` to
`android/app/src/main/AndroidManifest.xml`; the built-in bank needs none.

### Option B: copy into a new project

```bash
flutter create fraud_shield      # the name MUST be fraud_shield
cd fraud_shield
```

Delete the generated `lib/` and `test/` folders, then copy in `lib/`,
`test/`, `integration_test/`, `.github/`, `pubspec.yaml` and
`analysis_options.yaml` from this project. For the real fingerprint, also
replace these generated files with the ones from this project:

* `android/app/build.gradle.kts`
* `android/app/src/main/AndroidManifest.xml`
* `android/app/src/main/kotlin/com/example/fraud_shield/MainActivity.kt`
* `android/app/src/main/res/values/styles.xml`
* `android/app/src/main/res/values-night/styles.xml`
* `ios/Runner/Info.plist`

Then run `flutter pub get` and `flutter run`.

---

## 2. What to try

| Try this | Where |
|---|---|
| Wait about 20 s: a suspicious payment arrives as a banner and in the inbox, without refreshing | anywhere |
| "No, it wasn't me": fingerprint, card blocked and case opened in under 2 s | Home → Review now |
| "Yes, it was me" clears the alert | Alerts → any "Needs your answer" |
| An alert for an already-blocked card says "Blocked — no action needed" | Demo controls → "Send an alert for a blocked card" |
| Block or unblock a card, UPI ID or net banking with a reason | Home → Block / unblock |
| Dispute flow: the questions change by reason; evidence is optional for "didn't make this payment" and required for "didn't receive it" | Disputes → New dispute |
| Evidence: at most 5 files, 5 MB each, with progress; a failure at 90% retries only that file | Dispute → Evidence (turn on "Next upload fails at 90%") |
| SLA timer: amber in the last 2 days, red with the escalation path when breached | Disputes → StyleHub / Metro Cafe |
| Provisional credit that shows the difference | Disputes → QuickKart Online |
| Paginated secure messages, newest at the bottom | Case → Messages |
| Devices: the current device cannot sign itself out | Security |
| Activity log (every action with device id and client time) | Security → Activity log |
| Dispute older than 90 days: window explained, support contact offered | New dispute → TravelNest Hotels |
| Failures: offline, slow network, 503, dropped live connection, card network down, expired session | Demo controls (flask icon on Home) |
| App lock: switch to another app or tab and come back | anywhere |

New cases move along by themselves: assigned after about 20 s, provisional
credit after about 60 s (pull to refresh the case).

---

## 3. Tests

```bash
flutter test                                   # unit + widget tests
flutter test --coverage                        # about 80% line coverage
flutter test integration_test/app_test.dart    # main journey on a device
```

| File | What it proves |
|---|---|
| `test/unit/dispute_rules_test.dart` | Questions per reason, branching, evidence rule, validation per reason, 90-day window, disputed amount |
| `test/unit/rules_test.dart` | Money, dates, evidence limits, SLA (amber in the last 2 days), credit difference, backoff, SSE parser, fraud scoring |
| `test/unit/api_contract_test.dart` | Deny twice (also concurrently) = one block and one case; 409/413/422/404 mapping; 409 CURRENT; audit log |
| `test/unit/journeys_test.dart` | Deny → block → case; live alerts; reconnect and fetch missed alerts; upload retry of one file; messages |
| `test/unit/router_guard_test.dart` | Deep links while logged out land on login, then continue |
| `test/widget/screens_test.dart` | Every Must screen, lock screen and notification privacy |
| `test/widget/app_flow_test.dart` | The main journey as a widget flow |
| `test/widget/demo_device_test.dart` | The real demo fingerprint prompt, file sheet and demo controls |
| `integration_test/app_test.dart` | Deny → block → case created, on a device |

CI (`.github/workflows/ci.yml`) runs format, analyze, tests and a 70%
coverage gate on every pull request.

---

## 4. Environments (B9)

```bash
flutter run                                    # dev: built-in bank
flutter run --dart-define=ENV=staging --dart-define=API_BASE_URL=https://staging.example.com
flutter run --dart-define=ENV=prod    --dart-define=API_BASE_URL=https://api.example.com
```

With `API_BASE_URL` set, the same repositories talk to that server.

Signed, obfuscated release build:

```bash
flutter build apk --release --obfuscate --split-debug-info=build/symbols
```

---

## 5. Architecture

```
lib/
├── main.dart                    ProviderScope
├── app/                         app.dart (lock, banners, fingerprint layers) · router.dart (guard) · theme.dart
├── core/
│   ├── config/                  --dart-define environments
│   ├── errors/bank_error.dart   ONE sealed error type
│   ├── network/                 Dio + audit / auth / 401 / safe-log interceptors · error mapper · idempotency key
│   ├── realtime/                SSE alert stream client with backoff + Last-Event-ID · parser · backoff
│   ├── security/                session store · app lock · biometric service · device identity
│   ├── device/                  file picker service
│   ├── notifications/           push notices + in-app banner
│   ├── motion/                  reduce-motion aware animations
│   ├── utils/                   money (paise) · dates · validators
│   └── widgets/                 loading / error / empty states, fingerprint prompt
├── features/
│   ├── alerts/                  F1 inbox, F2 confirm / deny
│   ├── instruments/             F3 block / unblock
│   ├── transactions/            payments to dispute
│   ├── disputes/                F4 guided flow, F5 evidence queue
│   ├── cases/                   F6 tracker + SLA, F7 provisional credit, F8 messages
│   ├── security/                F9 devices, logins, activity log, demo controls
│   ├── auth/                    login, splash, lock screen, session
│   └── home/                    home + bottom navigation
└── mock_server/                 the in-app bank: API, seed data, fraud scoring, Dio adapter
```

Each feature has `domain/` (models with `fromJson` and pure rules),
`data/` (one repository per backend domain; throws only `BankError`),
`state/` (Riverpod notifiers) and `presentation/` (screens; no Dio).

State: `alertStreamClientProvider` (live stream), `alertsProvider`,
`alertProvider(id)`, `alertActionProvider(id)`, `instrumentsProvider`,
`disputeFlowProvider`, `uploadQueueProvider(disputeId)`,
`caseProvider(id)`, `caseMessagesProvider(id)`, `slaTickerProvider`,
`devicesProvider`.

API used: `GET /alerts?status=&sinceId=`, `GET /alerts/stream`,
`POST /alerts/{id}/confirm`, `POST /alerts/{id}/deny`,
`POST /instruments/{id}/block`, `POST /disputes`, `PATCH /disputes/{id}`,
`POST /disputes/{id}/evidence`, `POST /disputes/{id}/submit`,
`GET /cases`, `GET /cases/{id}`, `GET/POST /cases/{id}/messages`,
`GET /devices`, `DELETE /devices/{id}`, `GET /security/logins`,
`GET /security/audit`.

---

## 6. Fingerprint and other device features

**Fingerprint / face (built in).** `DeviceBiometricService`
(`lib/core/security/biometric_service.dart`) asks the phone's sensor before
deny, block, device sign-out and app unlock. `biometricOnly: false` lets
the phone's PIN or pattern stand in when no finger is enrolled. Where there
is no sensor to use (Chrome, Windows, a phone without a screen lock) it
shows the on-screen demo prompt, but only with the built-in bank; against a
real server it refuses.

The platform setup it needs (already done):

| File | Change |
|---|---|
| `pubspec.yaml` | `local_auth: ^2.3.0` |
| `android/app/src/main/kotlin/.../MainActivity.kt` | extends `FlutterFragmentActivity` |
| `android/app/src/main/AndroidManifest.xml` | `USE_BIOMETRIC` permission |
| `android/app/src/main/res/values*/styles.xml` | `Theme.AppCompat.DayNight.NoActionBar` (the dialog crashes on Android 8 and below otherwise) |
| `android/app/build.gradle.kts` | `androidx.appcompat:appcompat` for those themes |
| `ios/Runner/Info.plist` | `NSFaceIDUsageDescription` |

To test on a phone: set a screen lock and add a fingerprint in the phone's
Settings, install the APK, then tap "No, it wasn't me" on an alert.

**Secure storage.** Implement `SessionStore` with `flutter_secure_storage`
(read, write, clear) and override `sessionStoreProvider`.

**Files.** Implement `FilePickerService` with the `file_picker` package
and override `filePickerServiceProvider`.

**FLAG_SECURE (block screenshots on Android).** Not switched on, because
it also blacks out screen recordings for your demo video. To turn it on,
replace `MainActivity.kt` with:

```kotlin
package com.example.fraud_shield

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
    }
}
```

---

## 7. Known limitations

* Data lives in memory: restarting the app resets the demo bank and signs
  you out.
* Push notifications are in-app banners (they show while the app is
  open); with the app locked they hide all payment details.
* The file picker and session storage use in-app stand-ins, and
  FLAG_SECURE is off; see section 6 to switch them on.
