# iPhone beta development loop

Keep features in shared `lib/` and `packages/`; test iOS behavior in its native
runner. Use short feature/fix branches and merge reviewed changes into one
shared client. A platform folder owns native integration, not a copy of chats.

## Report an issue from the phone

Shake the unlocked, foreground iPhone app to open **Report a problem** directly,
or use the menu path below. **Settings → Advanced → Shake to report** toggles
this shortcut (on by default). While enabled in the active app it replaces
Shake to Undo; switching it off restores the previous iOS shake-to-edit policy.
Normal editing/undo controls remain. No report or screenshot is sent automatically.
See [native behavior and validation limits](ios-shake-to-report.md).

1. Open **Settings → Advanced → Report a problem**.
2. A screenshot is captured before the form opens. Tap its thumbnail to review
   it or **Remove screenshot** to omit it. Describe the steps and expected result.
3. Tap **Share report** to share the PNG and a text report through the system
   sheet. The copy icon copies text only. A gesture can still benefit from a
   separately attached short screen recording.
4. For layout, mention whether the keyboard was open; for a delivery problem,
   mention the network and whether ChatLoom was open, backgrounded or closed.

The text report adds version/build, OS version where available, logical screen
size, text scale, appearance and Reduce Motion. It does not query chats, account
identifiers, logs, server configuration or tokens. The screenshot includes the
visible app content, so review it before sharing. Captures stay in memory until
explicit sharing; native attachments use protected temporary-file leases and
are cleaned after sharing (macOS services get a short reading lease). No copy
is saved to Photos. Locking removes the screenshot from the open report.

This captures Flutter app content. Native keyboard, status UI or platform views
may not appear; record a keyboard/gesture issue separately when needed. One
issue per report makes regressions and retesting easier to track.

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
- Swipe-to-reply, double-tap reaction and message long-press remain available
  alongside visible controls. Holding an inbox row opens its actions menu only.
- For full-thread browsing without automatic read receipts, enable
  **Settings → Privacy & security → Incognito mode** and open the conversation
  normally. **Mark as read** explicitly sends the receipt; simply viewing or
  scrolling does not. Replying may mark messages read on the source network.
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
