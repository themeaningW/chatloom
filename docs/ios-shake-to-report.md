# Shake to report on iPhone

Shake ChatLoom while it is foreground and unlocked to open the existing
**Report a problem** sheet. It works on login/onboarding screens too. Write
the problem and tap **Copy report** to share it yourself. Nothing is submitted,
captured from chats or screenshotted automatically.

**Settings → Advanced → Shake to report** turns the shortcut off/on. It defaults
to on. Manual **Report a problem** remains available with this switch off or
when an older native runner lacks the bridge. A single shared guard prevents
manual and shake entry stacking several forms; a short cooldown drops repeated
motion events. The underlying editor and draft are retained.

## Native behavior

Both runners use a small custom `UIWindow` to observe UIKit motion events before
first-responder dispatch. Every event still reaches `super.sendEvent`. There
is no accelerometer polling, motion permission prompt, swizzling or forced
first-responder change. Swift replaces the storyboard window only at scene
startup, retaining its existing Flutter controller/implicit engine; Windows
xcross substitutes its generated window constructor using the existing scoped
compiler hook.

While subscribed and active, the bridge temporarily disables
`applicationSupportsShakeToEdit` so UIKit does not show Undo alongside the
report. It restores the previous value on cancellation/background. Turning
the shortcut off therefore restores the original Shake to Undo behavior;
text selection and other undo controls are unaffected.

The Dart scope lives below the app lock and presents in the root navigator's
overlay, which stays beneath the lock overlay. It stops listening on lock,
inactive/background, disposal or opt-out. Both native and Dart check foreground
eligibility; queued callbacks recheck their generation and privacy state.

`chatloom/ios_shake/availability` / `isAvailable` probes native support first.
The `chatloom/ios_shake` event channel receives a fresh random subscription
nonce as its listen argument and emits `{type: shake, subscription: nonce}`.
Old/unknown envelopes are discarded, including delayed events after resume or
re-enable. Channel capacity is zero with no listener, so events are not replayed.
The nonce is ephemeral and contains no account/device data.

## Verification

- `test/personal/shake_to_report_test.dart`: opening, deduplication, cooldown,
  input/selection retention, preference, stale packets/probes, lifecycle/lock,
  missing native support, disposal and other-platform fallback.
- Existing feedback, iOS navigation, conversation and app-lock tests cover
  the surrounding flow. All 36 selected tests pass.
- The PowerShell runner-shim tests cover source guards, old-runner migration,
  regeneration, nonce protocol, notification-hook preservation, LF/CRLF and
  unchanged compiler/linker arguments. Intentional invalid-source fixtures
  must be rejected before their synthetic compiler is invoked.

Mocks establish channel and UI behavior, not physical motion recognition.
On-device acceptance must check cold startup, keyboard-active shake, unchanged
draft/selection after closing, off/on, PIN lock and background/resume. Swift
Xcode compilation and actual iPhone motion dispatch are not established by a
Windows xcross build. Build results are recorded in [the beta notes](apple-ux-beta.md).

Reference: [Apple UIKit motion events](https://developer.apple.com/documentation/uikit/uiresponder/motionended(_:with:)).
