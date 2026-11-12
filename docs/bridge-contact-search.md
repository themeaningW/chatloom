# Contacts and new chats across networks

Search and New message use the same search screen. Existing chats include
Archive and Aside, with no age cutoff. Local message search reads a bounded
device cache; Search message history remains available for older server history.

Typing filters saved chats, chat members and the bridge's downloaded contacts.
Pressing Search on the keyboard also searches connected networks that advertise
remote search. Opening a result that has no Matrix room requires confirmation
before the bridge opens or creates its DM. Searching does not send a message.

## Network capabilities

The client uses each bridge's advertised capabilities and signed-in state:

- Messenger and Instagram support remote person search. This is not a complete
  Facebook friend or Instagram follower export.
- WhatsApp supports the bridge's synced contacts and phone-number lookup.
  This does not read the iPhone address book. Enter a full international number
  when the contact has not been synced into the bridge.
- An existing room can open immediately. Finding an old network contact can
  open their portal, but does not guarantee importing their entire old history.

Source contracts: [Messenger search](https://github.com/mautrix/meta/blob/main/pkg/connector/startchat.go),
[Instagram search](https://github.com/mautrix/meta/blob/main/pkg/igconnector/startchat.go),
[WhatsApp contacts](https://github.com/mautrix/whatsapp/blob/main/pkg/connector/startchat.go).

## Self-hosted discovery

Non-Beeper accounts can discover bridgev2 provisioning endpoints through the
[mautrix well-known contract](https://github.com/mautrix/manager#auto-configuration).
Serve this public JSON at `/.well-known/matrix/mautrix` on the Matrix ID's server
or the configured homeserver origin:

```json
{
  "fi.mau.bridges": [
    "https://matrix.example.org/bridges/whatsapp",
    "https://matrix.example.org/bridges/messenger",
    "https://matrix.example.org/bridges/instagram"
  ]
}
```

Proxy each listed base's `/_matrix/provision/` paths to that bridge's
provisioning listener. Enable `provisioning.allow_matrix_auth` in the bridge
configuration; keep its provisioning API authenticated. Each endpoint's
`/v3/whoami` identifies the bridge bot, including bridges with no existing chats.
ChatLoom does not guess endpoint paths from bot names.

An authority-only `fi.mau.external_bridge_servers` list is also supported. Each
external server's HTTPS well-known is read once, without recursive expansion.
Discovery is unauthenticated. Provisioning uses the Matrix token only on the
configured homeserver origin; other advertised origins receive a short-lived
OpenID token accepted by current bridgev2. Authenticated redirects are disabled.
See [bridgev2 authentication](https://github.com/mautrix/go/blob/main/bridgev2/matrix/provisioning.go).

The existing build-time override remains supported for deployments that already
publish their bridge routes without well-known discovery:

```json
{
  "CHATLOOM_BRIDGE_PROVISIONING_URL": "https://matrix.example.org/bridges/{bridge}",
  "CHATLOOM_BRIDGE_BOTS": "@whatsappbot:example.org,@metabot:example.org,@instagrambot:example.org"
}
```

Use `--dart-define-from-file=/path/to/local-server-defines.json` for **every**
build and install. Keep user-specific endpoints outside Git. Updating a client
without these defines disables that override; the new automatic discovery then
requires a published well-known file. Neither method requires entering social
network credentials into ChatLoom search.

## Acceptance

Unit/widget checks use fictional servers and contacts. They cover discovery,
session isolation, search submission, stale results, old archived rooms and
confirmation before DM creation. Popup checks include a 390-wide iPhone at DPR3,
320-wide large text, keyboard/safe-area bounds and nested navigators.

On a real account, verify each network's availability, submit a known person's
name, try an unsynced WhatsApp number, and open an existing old conversation.
Real contact results and native touch behavior require device acceptance.
