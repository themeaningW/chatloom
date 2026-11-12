# Private chat labels

Labels are personal filtered views of chats, shared by the Flutter clients.
They reuse `PersonalLabel`, `label:<id>` definitions and `labels:<entity>`
memberships in the existing encrypted private replica. There is no second
folder model or native Matrix Space creation.

## Use

1. In the inbox, tap the label icon beside the view chips, then **New label**.
2. Choose your own name, icon and color. **Custom color** opens hue,
   saturation and brightness controls. Tap **Save**.
3. Hold a chat, choose **Labels…**, select one or more labels and **Save**.
4. Tap a label chip to see its chats. The label icon also opens a complete
   list when there are too many chips. Its pencil edits a label's name,
   icon and color; **Delete label** removes that view and leaves chats intact.

Private sync must be connected and unlocked to edit. An offline worker does
not prevent locally queued edits. Conflicts, locked/background sessions and
account changes block stale writes. There is no unencrypted preferences
fallback. Web private storage retains its existing editing limitation.

## Behavior

- A chat may have multiple labels. Assigning one changes no placement, draft,
  read receipt, mute, pin or archive state. Legacy `showInInbox: false` flags
  remain ignored; labels never hide normal inbox chats.
- A label includes its direct chats, groups, archived chats and Aside chats.
  Ignored and technical chats remain in their own views. Network filtering
  and the chosen sort still apply inside a label.
- A merged person initially inherits its source chats' labels. Explicitly
  setting the person's labels, including clearing all of them, overrides
  that inheritance. Source memberships survive unmerge.
- The picker saves additions/removals against the latest local membership
  so unrelated membership changes arriving while it is open survive.
  Cross-device synchronization uses the existing replica conflict handling.
- A deleted definition gets a tombstone. Existing membership references are
  ignored, avoiding a bulk rewrite of chat preferences. Deleting the selected
  label returns the inbox to All.

## Validation

`test/personal/chat_labels_test.dart` covers definitions, multiple labels,
legacy metadata, merged conversations, deletion, concurrent local membership,
custom appearance, stale sessions and narrow/large-text access. Optional
`CHATLOOM_LABEL_CAPTURE_DIR` writes screenshots of the actual production
editor using fictional data. These are widget captures, not iPhone evidence.

The context-menu, inbox-filter, network-selector, profile and ordering suites
cover the integration. Existing full-app analysis and design-token checks
apply. Native build and physical-device results are recorded separately in
[the beta notes](apple-ux-beta.md).
