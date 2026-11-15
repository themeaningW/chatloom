# iOS appearance and media beta 3586

Branch: `feat/apple-ux-paste-beta`. One shared Flutter application remains in
`lib/`; the iOS adapters only supply native accessibility preferences.

## Behavior

- Received animated images and bridged MP4 GIFs play inside their conversation
  when visible and autoplay is allowed. Native **Auto-Play Animated Images**
  (iOS 17+) controls media separately from **Reduce Motion** and the app's
  interface-effects preference. The older runner/platform fallback remains
  conservative. Hidden/background media and protected media stay gated.
- When autoplay is paused, the GIF offers an inline **Play GIF** control with
  its reason in the accessible label. An explicit play can be paused again;
  it does not change the saved global preferences or open the media viewer.
  Animated Lottie stickers keep their existing reduced-motion behavior.
- Flutter Image itself pauses multiframe decoding under `disableAnimations`.
  The content gate applies the resolved media policy to that image subtree,
  while the interface keeps its original motion preference. Data-saver byte
  limits, attachment protection and native-player limits are retained.
- Native **Reduce Transparency** forces solid surfaces independently of
  animation preferences. Its signal and the media signal refresh on resume
  and on native preference notifications, without remounting the navigator.
- **Sort chats → Appearance** opens the existing settings. Production inbox
  and bubble previews now sit beside their relevant controls. Row height and
  avatar scaling leave the text size unchanged. No second setting is added.
- Direct token typography inherits the theme's system font, matching resolved
  typography. The inbox title scrolls away with the list, freeing its toolbar
  row. Pull-to-reveal search and the floating search button remain available.
- Reply and inbox swipes project a bounded momentum tail, retain their
  directional/edge guards, and soften at the travel boundary. A visible
  dismissing row can be caught before its action commits. The committed
  collapse remains protected against duplicate actions.

## Native runners

Xcode uses `AppDelegate.swift`. The Windows xcross path compiles the equivalent
Objective-C bridge through `prepare-xcross-runner.ps1`; its scoped compiler
adapter links Accessibility only for the app runner. `test-prepare-xcross-runner.ps1`
checks both the original hooks and accessibility registration, argument
transport, unrelated files and rejection of changed/unsupported generated code.
An xcross build does not validate the Swift runner in Xcode.

## Device acceptance

Offline validation: 184 regression tests passed, followed by 46 media/gesture
checks after the final control sizing. Analysis of the 27 changed Dart files
has no issues; full application analysis has zero errors/warnings and 67
existing informational lints. The strict design-token ratchet and synthetic
native-runner checks pass.

The separate UI-verification harness cannot locate this project's expected
snapshot workspace. Direct production-widget captures were used instead.
The existing primitive golden suite has 4 passing checks and 26 image
mismatches. The button render is byte-identical with the pre-change token file
from `8daf673`; those reference images already differ in background and
metrics. References were preserved. This is an open visual-baseline issue,
not a claim that the entire visual suite is green.

Build/test evidence is separate from the following checks on a real iPhone:

1. With ChatLoom's GIF autoplay and iOS **Auto-Play Animated Images** enabled,
   open received Messenger/Instagram GIFs and previously sent GIFs. They should
   move inside the conversation without opening their viewer.
2. Enable **Settings → Accessibility → Motion → Reduce Motion**. Interface
   effects should reduce while media follows the separate autoplay setting.
3. Disable **Auto-Play Animated Images**. Use **Play GIF** and **Pause GIF**
   inside the timeline, then scroll away, background, lock and return.
4. Enable **Settings → Accessibility → Display & Text Size → Reduce
   Transparency**. Check menus and fixed glass surfaces, then switch it off.
5. Open **Sort chats → Appearance**, change **Row height & avatars**, and
   compare the adjacent preview with the inbox. Try large system text, dark
   and light themes, and keyboard open/closed.
6. Swipe slowly, flick, reverse and catch a moving row. Check the system back
   edges, vertical scrolling, reply/Aside and VoiceOver's equivalent actions.

The local audit skill stays excluded from Git. Offline fixtures contain no real
messages. They demonstrate rendering and playback logic, not native frame
timing, haptics, VoiceOver or live bridge acceptance on the installed iPhone.
