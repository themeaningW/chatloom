# iPhone beta development loop

Keep features in shared `lib/` and `packages/`; test iOS behavior in its native
runner. Use short feature/fix branches and merge reviewed changes into one
shared client. A platform folder owns native integration, not a copy of chats.

## Report an issue from the phone

1. Open **Settings → Advanced → Report a problem**.
2. Describe the steps, expected result and actual result. Tap **Copy report**.
3. Paste it in the development conversation and attach a screenshot or a short
   screen recording. For a gesture, a recording is usually more useful.
4. For layout, mention whether the keyboard was open; for a delivery problem,
   mention the network and whether ChatLoom was open, backgrounded or closed.

The copied report adds version/build, OS version where available, logical
screen size, text scale, appearance and Reduce Motion. It does not read account
identifiers, chats, logs, server configuration or tokens, and submits nothing.
Review screenshots before sharing them. One issue per report makes regressions
and retesting easier to track.

## Fix and verify

Reproduce the exact screen/state first. Add a regression test for behavior
that could recur, then fix the shared component. Capture changed layouts with
fictional data at phone width in light/dark and large text. Run focused tests,
app analysis and the design-token check. Widget tests do not establish native
clipboard, permissions, push delivery or frame timing on an iPhone.

For a quick session, use **Debug + hot reload**, with the phone connected and
unlocked. Reload Dart/UI changes with `r`; restart with `R` if state or startup
changed. Native/plugin/build-define changes require a rebuild. On Windows use
the existing isolated xcross lab and its notification runner preparation:

```powershell
. .\ios-lab\Enter-IosLab.ps1
. .\ios-lab\Enable-IosCMake.ps1
Set-Location .\chatloom-upstream-pr
& .\scripts\ios\prepare-xcross-runner.ps1 -ProjectPath (Get-Location).Path -ClangPath 'C:\Program Files\LLVM\bin\clang.exe'
$env:XCROSS_BUNDLE_ID = 'prefixed'
xcross tunnel
xcross flutter run --debug --no-pub --usb -u <UDID> --dart-define-from-file=..\ios-lab\chatloom-server-defines.json
```

The tunnel may need an Administrator PowerShell session. Keep local service
defines outside Git. If the phone locks or the tunnel disconnects, reconnect
and run again. Debug on iOS needs tooling to launch; it is not the daily-use
build. On a Mac, use Flutter tooling/Xcode with the same project and defines.

For normal use, increment the build number and install **Release** over the
existing app. Do not uninstall to update: it risks removing local storage.
Verify the build number and original report on-device before closing the issue.
The current Windows lab installer is `ios-lab/Install-AppleUxBeta.ps1`.

With an Apple Developer Program team and signing set up, TestFlight is the
convenient route for repeated remote beta updates. A free Personal Team instead
requires periodic reprovisioning/reinstallation. This repository does not
publish a TestFlight build automatically.

## Gestures and motion acceptance

- Edge back: partial drag then cancel, then a completed drag. Input and scroll
  position should survive cancellation; a modal or protected action must win.
- Conversation scroll dismisses the iOS keyboard and keeps the unsent draft.
- Swipe-to-reply, double-tap reaction and long-press remain available alongside
  visible controls. Long-press preview must not send a read receipt.
- Check sheet drag-dismiss, media drag-dismiss and pinch zoom on actual content.
- Test **Settings → Accessibility → Motion → Reduce Motion** both ways. Page
  movement should disappear when enabled. Also check large text and VoiceOver.
- Measure responsiveness in Profile/Release; debug timings are not release
  performance evidence. Do not claim a frame-rate improvement from widget tests.

## Notifications

The free-account beta has local alerts while it is running and syncing, with
message-alert, sound and preview controls. A merged person's source chats share
one alert thread; duplicate events and older backfill do not replace the newest
alert. Lock/mute/ignore and active-chat policies still apply.

Closed/suspended-app delivery needs APNs, an enabled App ID/profile and a push
provider. This is a separate integration and physical-device acceptance task;
the beta does not implement or claim it. See [notification delivery](ios-notifications.md).

Sources: [Apple gestures](https://developer.apple.com/design/human-interface-guidelines/gestures),
[motion](https://developer.apple.com/design/human-interface-guidelines/motion),
[developer account and Personal Team limits](https://developer.apple.com/help/account/basics/about-your-developer-account),
[APNs registration](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns).
