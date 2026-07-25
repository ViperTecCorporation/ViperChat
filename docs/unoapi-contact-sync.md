# UnoAPI contact synchronization

UnoAPI inboxes can import the provider contact directory into the account contact list. The setting is stored in
`channel_whatsapp.contact_sync_enabled`; it is intentionally not part of `provider_config` and is never sent to UnoAPI's
`/register` endpoint.

## Execution

- Enabling the setting checks `GET /sessions` once per minute for up to 30 minutes.
- The first synchronization starts three minutes after the session is confirmed as `online`.
- Later synchronizations run every three hours through `Whatsapp::Unoapi::ContactSync::ScheduleJob`.
- Inboxes are staggered by one minute, and a Redis lock allows only one contact-directory page to run at a time.
- Pages use `GET /{phone}/contacts?cursor=...&limit=200`. The saved cursor makes repeated Sidekiq jobs idempotent.
- A `409 contact_directory_requires_zapo_provider` pauses the inbox until an operator reconnects it after selecting Zapo.

## Contact identity

`Contact` remains account-wide. `ContactInbox` stores the LID and normalized phone aliases for each inbox:

1. Reuse an existing inbox alias.
2. Otherwise reuse the account contact by normalized phone or LID.
3. Merge compatible phone-only and LID-only contacts.
4. Refuse automatic merging when phone numbers or LIDs conflict.

Brazilian numbers returned as `55 + DDD + 8 digits` receive the ninth digit after the DDD. Existing 13-digit mobile
numbers must already have `9` in that position. Other countries must be valid E.164 numbers.

Valid account contact names are preserved. Empty names, names shorter than three grapheme clusters, emoji/punctuation-only
names, and names equal to the raw or normalized phone are replaced by a valid `display_name` or `push_name`. Missing
pictures never remove the current avatar.

The UnoAPI `last_updated_ms` is saved in `contact_inboxes.additional_attributes.unoapi_last_updated_ms` so repeated pages
do not rewrite unchanged contacts.

## Operational states

- `disabled`
- `waiting_connection`
- `scheduled`
- `running`
- `completed`
- `failed`
- `paused`

The inbox settings screen shows the current state, processed/failed counters, last completion, next run, and the latest
error.
