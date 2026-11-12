# GIFs and short clips

In the composer, open the emoji/sticker panel and select GIFs. The shared
Flutter client offers a KLIPY/GIPHY source picker, remembered on this device.
KLIPY has GIFs and Clips; GIPHY has GIFs. Each source has its own key and result
grid. Switching sources invalidates outstanding search results. A tap or long press opens a preview;
only Send downloads the selected original and queues a message. Clips retain
sound; GIFs use the existing bridge GIF/ordinary-video adaptation. Preview
sound starts muted and can be enabled explicitly. The bookmark opens saved
GIFs and the existing Telegram-based search.

## Configuration

Each provider requires its own application API key. Without one, the panel
shows Set up KLIPY/GIPHY and makes no provider request. Select the source, open
the panel's settings button, obtain a key through the linked
[KLIPY documentation](https://docs.klipy.com/) or
[GIPHY dashboard](https://developers.giphy.com/dashboard/), and
save it there. It is stored through the app's existing protected storage,
never in Matrix account data, a message, or Git. Saving an empty key disables
this provider locally. A secure-storage failure leaves the previous setting
unchanged and reports that saving failed.

Distributors can provide `CHATLOOM_KLIPY_API_KEY` and `CHATLOOM_GIPHY_API_KEY` through their ignored
`--dart-define-from-file` configuration. Client-side application keys are
extractable from distributed binaries; use a provider-approved application
key and the provider's applicable limits. A device override takes precedence.
No borrowed/demo key is included. The existing local iOS installer preserves
its server-defines file when building this feature.

Searches and previews go directly to the selected provider. Requests contain the query,
locale, content filter and pagination; they contain no Matrix session token,
user ID, recipient, room ID or chat history. Result grids use one provider,
preserve returned media URLs, and do not populate a disk/search-result cache.
The Search KLIPY placeholder and visible attribution are included. GIPHY uses
unmodified official attribution marks from its published brand asset archive.
Configure the partner key without advertisements for this implementation.

The selected MP4 is downloaded only after Send, with a 16 MiB size limit,
timeout and format check. It enters the normal outgoing media queue and SDK
upload/encryption path, preserving its destination, reply and thread. Recheck
bridge media limits after download; unavailable formats remain blocked. A
lock/account/destination change before queueing cancels that attempt. Sent
chat attachments follow the app's normal history/cache policy.

## Providers and acceptance

[Tenor's public API was retired on 30 June 2026](https://support.google.com/tenor/answer/10455265?hl=en).
This integration uses the [KLIPY GIF/Clip API](https://docs.klipy.com/) and
[GIPHY GIF API](https://developers.giphy.com/docs/api/) rather
than scraping Tenor or reusing another application's key. Production access,
quotas and any custom distribution approval are managed through the providers.
GIPHY requires separate keys per platform, attribution, direct client requests,
and no API/media cache or provider mixing. KLIPY documents prior approval for
custom proxy/cache integrations. Review the selected-asset upload into Matrix
with the provider when requesting production distribution; this is an offline
implementation, not evidence of provider approval or an activated production key.

Automated checks use fictional keys and media. They verify endpoint selection,
pagination, errors, bounded downloads, no upload during previews, explicit
Send, destination/reply/thread preservation, GIF/audio flags, stale searches,
and the saved-GIF/Telegram regression path. Native iPhone playback and real
provider search/send across WhatsApp, Messenger and Instagram still need
acceptance with an actual key. No real contact message was sent during development.
