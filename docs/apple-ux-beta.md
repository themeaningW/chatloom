# Apple-inspired UX and clipboard beta

Branch: `feat/apple-ux-paste-beta`, based on the shared iOS/reels integration
`302b2af`. The application code remains shared across platform runners.

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
