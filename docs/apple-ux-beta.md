# Apple-inspired UX and clipboard beta

Branch: `feat/apple-ux-paste-beta`, based on the shared iOS/reels integration
`302b2af`. The application code remains shared across platform runners.

## Edge-aligned inbox (3581)

The header, hidden search panel and filter controls use a 16-point horizontal
gutter. Conversation surfaces extend to 12 points and add 4 points internally,
so visible avatars and trailing timestamps share the 16-point edge. Removed
the avatar slot's extra reserved width and reduced the scaled avatar/text and
metadata gaps. The user's avatar size, density, text scaling and unread-style
preferences remain in effect. Separators follow the actual text inset,
including when avatars are hidden.

Horizontal safe-area protection keeps content clear of landscape cutouts;
the header's top inset, search reveal, FAB and last-row bottom clearance retain
their existing behavior. Desktop keeps its intentional two-column layout.

48 focused regressions pass, covering 320/390/430-point portrait and 844-point
landscape layouts, 1x/2x text, density/avatar preferences, RTL rows, status
semantics, filters and hidden/revealed search. Production presenters were
inspected in [dark](ux/apple/inbox-edge-dark.png) and
[light](ux/apple/inbox-edge-light.png). Physical iPhone acceptance is pending.
Full analysis has zero errors/warnings and the same 70 existing infos;
changed-file analysis is clean and the strict design-token check passes.
The separate presentation harness still lacks its external source-snapshot
prerequisite; full-app production presenter fixtures supplied the captures.

## More room to type, app icon and brief feedback (3580)

On phones and narrow windows, the composer keeps +, the source-aware editor
and mic/send visible. Emoji/GIFs/stickers, dictation, attachments and round
video use the existing expandable + tray. Typing closes the tray, while the
editor, selection, composing range and focus remain mounted. Round video's
held gesture owns a permanent first tray slot; phone rotation keeps the same
layout. Attachment picking remains available through the tray's overflow.
The composer uses tighter 4-pixel outer insets, removes duplicated inner field
padding and uses a short **Message…** hint; source descriptions remain in
the source control's tooltip and accessibility label.

The production merged-chat fixture was inspected in
[dark](ux/apple/composer-input-space-dark.png) and
[light](ux/apple/composer-input-space-light.png). 100 focused regressions pass,
including 320/390/430-pixel layouts with 1x/2x text, responsive editor identity,
clipboard/send paths, recording controls, Undo expiry and brand resources.
Full analysis has zero errors/warnings and the same 70 pre-existing infos;
the focused component/test analysis is clean. The strict design-token check
passes without adding debt.

Merge/unmerge/archive and ordinary copy confirmations last 2.5 seconds.
Undo snackbars explicitly disable Flutter's action-driven persistence in
normal navigation; accessible navigation retains the persistent Undo action.
Errors and deliberately longer recovery prompts keep their own timing.

The Windows iOS builder skips asset catalogs. The existing ChatLoom artwork
now has opaque RGB iOS catalog slots, explicit PNG resources and matching
iPhone/iPad icon metadata. iOS uses this app identity for the Home Screen and
the leading notification icon. Source resource checks pass; physical icon
caching and notification presentation still need iPhone acceptance. See
[brand packaging](brand/BRAND.md).

The separate presentation harness still lacks its external source-snapshot
prerequisite; the captures above use actual production widget fixtures.

The Windows xcross release of `a9b0401` completed as **2.10.0 (3580)**.
The staged bundle contains all 14 explicit icon PNGs with matching iPhone/iPad
metadata and byte-identical source artwork. Composer/retained-feature markers,
the bridge endpoint and native notification/shake hooks were verified in AOT
and the runner. This artifact has not been installed on the physical iPhone.
Swift/Xcode compilation remains unverified here; the existing dSYM and
CocoaPods-only Share plugin limitations remain.

## GIF search input and compact controls (3579)

GIF search previously disabled its entire text field until its provider was
configured. Both public sources and the saved/Telegram panel now accept local
typing while unavailable. Requests still require a configured/available source.
Public search keeps the query through setup and resumes it only on an active
panel in the same unlocked privacy session.

The source and GIFs/Clips pills share one horizontal scroll strip with a
36-pixel visible surface and complete 48-pixel tap target. Search focus hides
this strip and the bottom tabs in the same frame as keyboard resizing; the
mounted search, focus and composer draft survive. The keyboard's **Search**
action restores the controls; an empty focus scope no longer leaves the panel
stuck at its compact search height. Fixtures were inspected in
[dark](ux/apple/gif-controls-dark.png) and
[light](ux/apple/gif-controls-light.png).

54 focused regressions pass, including the original disabled-input reproduction,
both unconfigured public sources, provider setup, stale privacy sessions,
320/390-pixel full-composer keyboard resizing at 1x/2x text, padded pill taps,
provider switching, search/send and saved GIFs. No real provider request or
message was sent. Physical iPhone keyboard, provider search and playback
acceptance remain pending. Full analysis has zero errors/warnings, with 70
existing informational findings elsewhere; final changed-file analysis is
clean and the strict design-token check passes. The separate presentation
harness cannot start without its external source-snapshot prerequisite;
production widget fixtures supplied the captures instead.

The Windows xcross release of `635caab` completed as **2.10.0 (3579)**.
Bundle metadata and GIF-search code were verified in AOT, together with the
retained bridge endpoint, notification/shake hooks and report screenshots.
This artifact has not been installed on the physical iPhone. Swift/Xcode
compilation remains unverified here; the known dSYM and CocoaPods-only Share
plugin limitations remain.

## Pull-down search and compact filters (3578)

Search starts hidden above the inbox content. Pull the list down from its top
to reveal the search panel, then tap it to open the existing full search.
Scrolling up hides the panel naturally. A lower-right magnifier opens the same
search directly from any scroll position. Chats/settings stay in the fixed
header; network and sort controls retain their order at the top of the content.
Bottom clearance keeps the last conversation above the magnifier at list end.

All/Unread/Groups/Aside and label chips use a 36-pixel visible pill with tighter
horizontal padding and the same complete 48-pixel tap target. Large text may
grow the surface. Other button defaults remain unchanged.

The label editor keeps its 16-icon quick palette and offers **View more** for
all 80 icons. Choosing one collapses the palette and retains that extra icon
in the quick selection when editing again. Existing icon IDs and private label
storage are unchanged. See [the expanded picker](ux/apple/label-more-icons.png).

79 focused regressions pass, including real iOS/Android scroll physics, middle
versus top pulls, both search entries, sort access, last-row clearance, compact
tap margins, large text, label persistence, inbox lifecycle and list motion.
Full analysis has zero errors/warnings; final changed-file analysis is clean,
with 70 existing informational findings elsewhere. The strict design-token
check passes. New compact-pill goldens were inspected in dark/light, and the
production inbox fixture was captured with search
[hidden](ux/apple/inbox-search-hidden-dark.png) and
[revealed](ux/apple/inbox-search-revealed-dark.png), also in
[light](ux/apple/inbox-search-revealed-light.png). The separate presentation
harness still lacks its external source-snapshot prerequisite; full-app
fixtures supplied these captures. Physical-device acceptance remains pending.

The Windows xcross release of `4cfb1ec` completed as **2.10.0 (3578)**.
Version metadata, hidden-search/FAB keys, expanded icon-picker code and retained
report screenshots were verified in AOT. The bridge endpoint, notification and
shake hooks remain included, and the removed long-press thread preview remains
absent. This artifact has not been installed on the physical iPhone. Actual
device gestures and Swift/Xcode compilation remain unverified here; the known
dSYM and CocoaPods-only Share plugin limitations remain.

## Automatic report screenshots (3577)

Both shake and manual **Report a problem** capture the visible Flutter app
surface before opening the form. The thumbnail expands for review and can be
removed. **Share report** opens the native share sheet with a PNG, a text-file
report and the report text; the copy icon copies text only. Nothing is sent
automatically, and screenshots are not saved to Photos.

The capture is on demand, capped at a 2048-pixel longest side, 2x scale and
8 MiB encoded PNG. A two-second limit or capture failure retains the text-only
report. A lock/background transition during capture discards it; a locked open
report loses its screenshot. The editor remains mounted. Temporary plaintext
exports reuse protected media leases and are cleaned after native handoff
finishes; a successful macOS service gets its existing-style short reading
lease. Text-file attachment preserves context in targets that ignore captions.

The capture covers Flutter content; system keyboards/status UI and native
platform views may be absent. Native iPhone capture/share-sheet acceptance
remains separate from fixture and source checks.

35 selected full-app tests pass: rendered PNG pixels, capture ordering and
deduplication, lock/background/timeout fallbacks, explicit sharing/removal,
attachment contents and temporary-lease cleanup. Full app analysis has zero
errors/warnings; final changed-file analysis is clean, with the 70 existing
app informational findings outside this change. The strict design-token check
passes. The production sheet was inspected in
[dark](ux/apple/feedback-screenshot-dark.png) and
[light](ux/apple/feedback-screenshot-light.png) fixtures, with large-text
reachability covered by a widget test. The separate presentation harness still
cannot start without its external source-snapshot prerequisite; these captures
come from the full-app feedback fixture instead.

The Windows xcross release of `90e3799` completed as **2.10.0 (3577)**.
Bundle metadata, screenshot/share controls in AOT, the retained bridge endpoint,
notification and shake hooks were verified; the removed thread preview remains
absent. This artifact has not been installed on the physical iPhone. Actual
iOS capture/native sharing and Swift/Xcode compilation remain unverified here;
the known dSYM and CocoaPods-only Share plugin limitations remain.

## Full-thread browsing without the long-press preview (3576)

Holding an inbox row or pin opens the compact actions menu again, matching
upstream `26199cd`; the separate saved-history preview and its **Open chat**
action have been removed. Labels and the selected inbox sort remain available.

Tap a row normally to browse the complete conversation, including older
history. With **Settings → Privacy & security → Incognito mode** enabled,
viewing and scrolling do not automatically send a read receipt. Use the
conversation's **Mark as read** button when desired; replying may still mark
messages read on their source network. The privacy policy, read-target logic
and read button already match this upstream revision and remain unchanged.

90 selected full-app tests pass. The new production inbox regression failed
before removal and now verifies the compact menu, no saved-history reads and
unchanged unread state. App analysis has zero errors/warnings and the same
70 informational findings; the strict design-token no-growth check passes.
The separate presentation harness could not start because its external
`docs/notion-ui/SOURCE-SNAPSHOT.json` project prerequisite is unavailable in
this checkout. It did not produce captures or additional verification.

The Windows xcross release of `ff8bb0f` completed as **2.10.0 (3576)**.
Bundle metadata, removal of the old preview from AOT and retention of Incognito,
manual read controls, private bridge configuration, notification and shake
hooks were verified. The artifact has not been installed on the physical
iPhone. Native device acceptance and Swift/Xcode compilation remain separate;
the existing dSYM and CocoaPods-only Share plugin limitations are unchanged.

## Shake to report (3575)

Shaking the active, unlocked iPhone opens the same **Report a problem** sheet
as the menu. **Settings → Advanced → Shake to report** toggles it; manual
reporting remains available. It preserves editor contents, deduplicates
manual/shake entry, ignores motion during background/lock and rejects old
subscription envelopes after resume. No report or screenshot is sent automatically.

The native UIKit window hook needs no motion sampling/plugin/permission.
While enabled it replaces Shake to Undo; switching it off restores the previous
iOS policy. Both Xcode and Windows xcross source paths include it; the generated
notification delegate hook is preserved. See [implementation and acceptance](ios-shake-to-report.md).

36 selected Flutter regressions and the scoped PowerShell runner-shim tests pass.
App analysis has zero errors/warnings and 70 existing informational findings;
the strict design-token no-growth check passes.

The Windows xcross release of `7d85369` completed as **2.10.0 (3575)**.
Bundle metadata, the preference and reporting code in AOT, both native shake
channels, the custom window and subscription nonce protocol were verified.
The private bridge configuration and notification delegate hook remain included.
This artifact has not been installed on the iPhone: physical shake/startup/keyboard
acceptance remains pending, and the Windows build does not compile the Swift
Xcode runner. The known dSYM and Share extension limitations remain.

## iPhone interaction and feedback (3574)

iOS keeps native Cupertino page navigation, including edge-back progress and
cancellation. Its shared transition adapter also removes translations under
Reduce Motion on imperative routes without remounting the editor. Scrolling
the conversation dismisses the iOS keyboard and retains the unsent draft.
Existing swipe reply, reactions, previews, sheet/media dismissal and zoom
remain in their existing shared components.

Local incoming-message alerts now offer **Message alerts** and **Play sound**
controls. A merged person uses one notification thread, duplicate events are
suppressed and old backfill cannot replace its newer alert. Open-person versus
open-source routing is account-scoped, and pending local presentation is
cancelled when the session/privacy guard changes. **APNs delivery while the app
is suspended or closed is still not connected**; local permission and these
changes cannot supply that capability.

**Settings → Advanced → Report a problem** copies a user-written report with
version/build and allowlisted display/OS context. It collects no chats/logs and
submits nothing automatically. See [the development loop](ios-development-loop.md)
and the [production-sheet fixture capture](ux/apple/feedback-sheet-dark.png).

137 focused regressions pass, covering interactive navigation completion and
cancellation, PopScope veto, Reduce Motion, real production timeline keyboard
dismissal, notification privacy/grouping and label regressions. Native iPhone
presentation, gestures, actual frame timing and remote push require separate
device acceptance.

The Windows xcross release of `7dcfe8c` completed as **2.10.0 (3574)**.
Version metadata, feedback/alert controls in AOT, private bridge configuration
and the native notification delegate hook were verified. App analysis has zero
errors/warnings and 70 existing informational findings; the strict design-token
no-growth check passes. This artifact has not been installed on the iPhone.
The known dSYM and Share extension limitations remain. The current signing
account remains a free Personal Team; no APNs service/profile was configured.

## Custom labels (3573)

The existing private label model is now available from the inbox's label icon
and each chat's **Labels…** action. Choose a name, one of sixteen icons and
any color (palette or custom hue/saturation/brightness). A chat may have
several labels. Label chips are private filtered views; deleting a label
keeps conversations and messages. Merged chats inherit source labels until
the person gets an explicit selection. See [usage and storage](chat-labels.md).

179 focused domain/widget/inbox regressions pass. App analysis has zero
errors or warnings and 70 existing informational findings. The strict
design-token no-growth check passes. Production editor captures with fictional
data were checked in [dark](ux/apple/label-editor-dark.png) and
[light](ux/apple/label-editor-light.png) modes. Small screens, 2x text and
keyboard insets are covered by widget tests; physical iPhone acceptance and
real cross-device sync remain pending.

The Windows xcross release of `ae4abb8` completed as **2.10.0 (3573)**.
Bundle version, label editor code, private bridge endpoint and the generated
notification delegate hook were verified. The artifact is ready for the
existing installer, but has not been installed on the physical iPhone.
The previously documented dSYM and Share extension limits remain.

## Merged-draft follow-up (build 3570)

The inbox preview and Drafts filter now read the same draft as the conversation
editor. A merged person uses its person draft, so clearing it cannot revive an
old source-room draft or conflict in the list. Source drafts remain stored for
source views and unmerge. No personal data cleanup or migration is required.

Five focused projection cases reproduce the former mismatch (four failed
before the fix). A production-row regression covers clearing, filtering and
unmerge; all 120 selected regression tests pass. Physical-device acceptance
of this follow-up is still pending installation.

`DESIGN.md` now records the user's priority: fewer visible elements, less text,
and familiar unambiguous icons with accessible labels and sufficient hit areas.

## Research and existing-screen audit

The previous production fixtures (`test/notion/goldens/screens/`) showed:

1. Large blue unread cards competed with names and message previews.
2. The floating inbox dock covered the last rows and truncated its network label.
3. Search and new-message entry were hard to discover.
4. Settings had little visual grouping and a very small account avatar.
5. The editor's native Paste menu bypassed the media-aware action; keyboard
   image insertion could send immediately instead of opening attachment review.

The design follows Apple's guidance on legible hierarchy, system typography,
visible search, and sufficiently large hit regions. It adapts the existing
Notion components rather than shipping a separate iOS feature implementation.

- [Apple UI design tips](https://developer.apple.com/design/tips/)
- [Typography](https://developer.apple.com/design/human-interface-guidelines/typography)
- [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)
- [Search fields](https://developer.apple.com/design/human-interface-guidelines/search-fields)

## Changes

- A solid Chats header with Settings/New message, visible Search, a network
  picker and sort control. No floating panel obscures conversations.
- Neutral rows, restrained unread emphasis, larger avatars and inset separators.
- A 17-point reading style, clearer type scale and neutral light/dark surfaces.
  Apple targets use Flutter's installed system text face; other hosts retain
  bundled Roboto. System fonts are not redistributed.
- Grouped Settings sections, larger profile avatar and clear disclosure icons.
- The compact editor preserves its 48-point controls and usable text width on
  narrow screens. Large text and reduced-motion settings remain respected.
- All defaults to latest activity; Unread remains a filter. Latest, Oldest and
  Unread first are saved locally. Manual pin order remains deliberate.
- Native Paste handles text at the selection and images as attachment previews
  in ordinary and merged conversations. Keyboard-inserted images also require
  review. Empty paste never deletes a selected draft. Stale async paste after
  navigation, typing or app locking is rejected. MIME and filename agree.

Arbitrary iOS Files clipboard URLs are not implemented by this change; use the
existing attachment file picker. Photos/Safari and system paste permissions
still need physical-device acceptance.

## Notifications

Settings → Notifications now offers iOS permission, native settings and a
generic local test. It does not prompt at startup. New-message local alerts
use the existing mute, active-chat, app-lock and preview policies while the app
is running and syncing. The native notification-center delegate is installed.

This is **not suspended/terminated-app push delivery**. No APNs entitlement,
provider, device-token registration or signing profile has been fabricated.
See [iOS notification delivery](ios-notifications.md) for the required follow-up.

## Test on iPhone after installation

This work cannot update the app already installed on a disconnected phone.
Install the new release using the existing local xcross setup (or build it on
a Mac from this branch). Do not uninstall the old app or reset its local keys.

1. Open Chats; check Search, Settings, network choice and all sort modes.
2. Check both light/dark appearance and larger system text.
3. Paste text into the middle of a draft and over selected text.
4. Copy an image from Photos and Safari, then long-press the empty editor and
   choose Paste. Check the attachment preview; nothing should send until Send.
5. Repeat in a merged conversation and confirm the chosen destination.
6. Check an empty clipboard leaves selected draft text intact.
7. In Notifications, enable permission and run the local test. This verifies
   local presentation only; it cannot verify APNs/background delivery.
8. Check real bridged reels, return from full screen, and background/resume.

Automated tests and rendered fixtures use fictional data and fake decoders or
platform channels where appropriate. Native compilation, source checks,
visual fixture captures and actual device acceptance must be reported separately.

## Verification on Windows

- The initial Apple UX pass ran 286 focused regression tests: clipboard/menu/keyboard insertion,
  selection and grapheme limits, previews/reels, sorting and pins, large-text
  layout, notification privacy/routing and inbox resource lifecycle.
- Application analysis (`lib`) has zero errors and zero warnings, with 70
  existing informational lint findings. Changed tests are also analyzed.
- The design-token no-growth check passes (172 legacy hits, baseline 181).
- Production-widget captures passed in light and dark appearance, including
  narrow layouts and 2x accessibility text. They are rendered on Windows with
  fixture data and the fallback font, not taken from an iPhone. Reference-photo
  golden comparison was not run because that isolated photo harness is absent.

The whole-checkout analyzer was also attempted. It is not clean: unrelated
worker/tool packages lack their own dependency setup, and existing smoke
scripts contain unresolved symbols. That result is separate from the app
analysis above. No worker/server changes were made by this beta.

## Native release artifact

The Windows xcross release build, including the merged-draft fix, succeeded
from source commit `4c52f89e6dd7c900052f0d84cc64d3beb17389c1`:

- Bundle: `build/xcross-ios/chatloom.app`, release/AOT.
- Bundle metadata verified as **2.10.0 (3570)**. The 120 selected follow-up
  regression tests passed; no physical-device acceptance is claimed.
- The generated Runner sets Flutter's notification delegate after plugin
  registration. The class lookup is present in the executable, and the bundled
  plugin library links UserNotifications. This verifies inclusion, not delivery
  on a physical device.
- The Windows toolchain did not produce App.framework.dSYM because its
  dsymutil crashes. This limits crash symbolication; the release build itself
  completed successfully.
- Incoming iOS Share extensions remain outside this beta. The CocoaPods-only
  receive_sharing_intent code is excluded by xcross; this is separate from the
  clipboard Paste implementation.

In the existing Windows lab, `ios-lab/Install-AppleUxBeta.ps1` prepares the
runner, synchronizes generated version settings, signs and installs through
the existing xcross setup. It requires a connected, unlocked iPhone. Keep the
phone unlocked throughout installation and preserve the existing app/data.

Mac testers can use [the Xcode installation guide](ios-beta-install.md), with
`feat/apple-ux-paste-beta` as the branch in its clone command. A standard
Mac/Xcode build of this revision has not been run here.

## Network filter and contact search follow-up (3571)

The network picker now opens below a header or above a bottom dock, remains
inside safe screen bounds, and scrolls when its options exceed available space.
Search includes old Archive/Aside rooms and can submit name searches to
supported connected bridges from the keyboard. Self-hosted accounts can use
advertised bridgev2 endpoints, including bridges with no existing room.

See [contact search and self-host configuration](bridge-contact-search.md) for
network limits and the required server publication or build-time override.
The local Windows installer preserves the existing private server defines.

Verification: 120 focused unit/widget regressions pass, app and changed-test
analysis has zero errors/warnings (70 existing informational findings), and
the design-token no-growth check passes. Production-widget captures were
inspected at 390/DPR3 and 320/large text; these use fictional data and Windows
fallback fonts, not physical iPhone screenshots. Live read-only checks reached
the private Matrix API and all three authenticated provisioning routes. Real
network search results still require signed-in device acceptance.

The Windows xcross release build of source `0c8b6c9` completed as **2.10.0
(3571)**. Its bundle metadata and compiled private bridge settings were checked;
the notification delegate remains included. This build has not been installed
on the phone: its USB tunnel setup stopped when Windows administrator approval
was not granted. The existing 3570 installation was preserved. The toolchain's
known missing dSYM and CocoaPods-only Share extension limits still apply.

## GIF and clip search (3572)

The GIF composer panel now offers separate KLIPY and GIPHY sources. KLIPY
includes GIFs and audio clips; GIPHY offers GIFs. Each provider needs its own
key, configurable through the panel's settings and stored on this device.
No provider key is bundled in the repository. A selected item opens a preview
and requires Send; the bookmark retains saved GIFs and Telegram search.
See [configuration, data flow and acceptance limits](gif-search.md).

60 focused API/widget/sticker regressions pass, app analysis has zero errors
and warnings (70 existing informational findings), and the design-token
no-growth check passes. Tests use fictional responses and a fake player;
they do not establish live provider approval, real search or iPhone playback.

The Windows xcross release build of `2917575` completed as **2.10.0 (3572)**.
Bundle metadata, both providers, both official GIPHY attribution assets, the
private bridge endpoint and notification delegate inclusion were verified.
This artifact is ready for the existing installer; it has not been installed
or tested on the physical iPhone. The known dSYM/Share extension limits remain.

## Rendered examples

Rendered examples:

- Chats: [dark](ux/apple/inbox-390-dark.png),
  [light](ux/apple/inbox-390-light.png).
- Conversation: [dark](ux/apple/conversation-390-dark.png),
  [light](ux/apple/conversation-390-light.png).
- Settings: [dark](ux/apple/settings-390-dark.png),
  [light](ux/apple/settings-390-light.png).

Physical-device acceptance remains pending. In particular, native clipboard
permissions, actual Photos/Safari content, notification presentation and
frame timing have not been measured on this new build.
