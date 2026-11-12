# iOS notification delivery in the beta

This build supports **local notifications while ChatLoom is running and
syncing**. Settings → Notifications lets the user request iOS permission,
open the app's iPhone settings, and display a generic local test. Startup
does not ask for permission automatically. The test does not read chats,
send a message, or establish that remote delivery works.

Incoming events use the existing eligibility, chat mute/ignore, active-chat,
message-preview and app-lock policies. Taps use the existing account-aware
notification router. Cold and warm delivery of the same response is deduplicated.
No account, chat or message data is added to diagnostic logs.

Settings also offers **Message alerts** and **Play sound** controls for incoming
local message alerts. A merged person shares one notification ID and iOS thread
across its source chats. Alerts are serialized, duplicate events are suppressed,
and older backfill cannot replace the newest displayed alert. Session/privacy
changes while presentation is pending cancel that request. These checks establish
requests to the OS, not evidence that iOS displayed an alert.

## What this does not implement

There is no APNs registration, device-token upload, APNs-enabled provisioning,
remote push gateway or notification-service extension in this change. Once
iOS suspends or terminates ChatLoom, its foreground Matrix sync is not a
notification delivery mechanism. Enabling local permission does not make
remote notifications work. The settings page states this explicitly.

The current build uses a free Personal Team. Apple's capability availability
depends on program membership and the signing profile. Do not add an
`aps-environment` entitlement to this project until a corresponding
APNs-enabled App ID/profile and provider configuration exist: adding the XML
alone cannot grant a capability and can make the free-account build fail.

## Remote push follow-up

1. Obtain an App ID and signing profile with Apple's Push Notifications capability.
2. Implement APNs registration and account-bound token lifecycle, including logout
   and token rotation; no token should be logged or shared in source.
3. Add a gateway/provider path from Matrix push events to APNs and define the
   generic notification fallback and encrypted-content handling.
4. Test real-device delivery with the app foreground, background, suspended,
   terminated, offline and locked. Test all preview/app-lock/mute policies.

No developer account, profile, server or credentials are modified by this work.

## Windows xcross runner

xcross 2.0.9 generates its own Objective-C runner; it does not compile the
project's Swift AppDelegate. Both runners must restore FlutterAppDelegate as
the notification-center delegate **after plugin registration**, because a
registered plugin can replace it. FlutterAppDelegate then forwards callbacks
to the registered local-notification plugin.

For a Windows cross build, run the following after the existing lab/toolchain
setup and before `xcross flutter build` or `xcross flutter run`, in the same
PowerShell 7 session. Use the physical checkout path as the working directory,
not a junction alias. Pass the real clang selected by the local xcross setup;
the current lab's generated SwiftPM toolset selects this LLVM installation:

```powershell
& .\scripts\ios\prepare-xcross-runner.ps1 -ProjectPath (Get-Location).Path -ClangPath 'C:\Program Files\LLVM\bin\clang.exe'
```

The helper builds a small managed compiler shim under `build/` and sets the
process-local `CC` override used by xcross's Darwin runner compiler selector.
(`XCROSS_APPLE_TOOL_CLANG` affects other build paths and does not select the
runner compiler in xcross 2.0.9.) It forwards compiler arguments and exit status
and prepares only this checkout's generated
`build/xcross-flutter-runner-bin/Runner.m` immediately before compilation. The
Objective-C hook resolves the notification-center class through Foundation;
this avoids a new framework link dependency in xcross's separately linked
runner. UserNotifications is already loaded by the registered native plugins. This is
repeatable even when xcross regenerates the source. An unexpected runner
template fails before compilation. It changes no xcross binary, package source,
entitlement or credential. Run the preparation again in each new PowerShell
session; a standalone patch to generated Runner.m would be overwritten.

The same CC selector is used by Windows SwiftPM. For the pinned
flutter_local_notifications 22.3.1 source only, the shim keeps its existing
NSDictionary/NSMutableDictionary mismatch at warning severity using
`-Wno-error=incompatible-pointer-types`. That exception requires the exact
source SHA-256 and expected xcross cache layout. A changed source fails for
review; package files remain untouched. Every other compiler invocation and
all linker arguments are forwarded unchanged.

`scripts/ios/test-prepare-xcross-runner.ps1` checks the shim against a synthetic
compiler, including argument quoting, regeneration, idempotence, path scope,
unchanged linker arguments and rejection of an unsupported template. These checks
do not establish real-device notification delivery. Xcode builds use the Swift
AppDelegate directly and do not need this Windows helper.

The xcross-specific selectors are documented in its pinned
[runner source](https://raw.githubusercontent.com/arxdeus/xcross/v2.0.9/packages/xcross/lib/src/shared/flutter/build/runner_shim.dart)
and [Darwin toolchain resolver](https://raw.githubusercontent.com/arxdeus/xcross/v2.0.9/packages/darwin_sdk_kit/lib/shared/toolchain/darwin_toolchain_resolver.dart).

## Sources

- [Apple: User Notifications](https://developer.apple.com/documentation/usernotifications/)
  distinguishes app-created local notifications from server-generated APNs delivery.
- [Apple: Asking permission](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications)
  describes authorization and checking current notification settings.
- [Apple: Registering with APNs](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns)
  requires the Push Notifications capability and device registration.
- [Apple: Add a capability](https://help.apple.com/xcode/mac/current/en.lproj/dev88ff319e7.html)
  states that capabilities depend on target type and program membership.
- [Apple: Supported iOS capabilities](https://developer.apple.com/help/account/reference/supported-capabilities-ios/)
  lists availability by developer program.

The platform-channel tests verify permission arguments, initialization retries,
generic local test content and response deduplication. They are not evidence of
physical-device notification delivery or successful APNs configuration.
