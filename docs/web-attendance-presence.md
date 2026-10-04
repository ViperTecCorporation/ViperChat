# Web attendance presence and absence reminders

The guest currently fetches messages using HTTP polling every 3 seconds, not a
socket. Polling, delivery receipts and `/seen` do not establish presence.

## Frontend contract

`POST /web-attendance/api/presence` uses the existing encrypted, HTTP-only session
cookie scoped to `/web-attendance/api` and requires `X-Web-Attendance: 1`.

JSON: `{ "visible": true, "presence_id": "UUID-per-page" }`.
`visible` is required. `presence_id` is optional for compatibility; generate one
UUID per page mount and reuse it for every heartbeat from that page. Never share
it across tabs or generate a new one for each heartbeat.

Send immediately on opening, every 3 seconds, and on visibility changes. Use the
document's actual visibility. A hidden tab may continue reporting `false` but
must not report visible presence. The server supplies timestamps and identity;
client timestamps, conversation IDs and account IDs are ignored.

Responses: `204` accepted; `403` missing custom header; `410` missing, expired,
revoked or unavailable session; `422` missing/invalid visibility or invalid UUID.
Responses use `Cache-Control: no-store`, `Referrer-Policy: no-referrer` and
`X-Content-Type-Options: nosniff`.

Any visible tab with a heartbeat at most 10 seconds old prevents the reminder,
including different tabs sharing one session cookie and different devices.
Tab entries older than 10 seconds are pruned on heartbeat. No heartbeat means
disconnection after freshness expires; a receipt alone does not mean return.

## Reminder rules

Only a public outgoing Web message from an agent schedules a delayed check.
Messages created while online get one check too, covering an abrupt network loss
while the last heartbeat still looks fresh. If still online at that check, the
pending message is cleared and no periodic checking job is created. A read
pending message is cancelled.
The job waits at least 15 seconds after both absence and the triggering message.

One reminder is allowed per absence epoch. Repeated online heartbeats do not
change the epoch. A real visible return increments it and clears pending work;
another absence still needs a new Web message to produce another reminder.
The conversation lock serializes presence, scheduling and creation. A unique
database request key (`conversation:cycle:epoch`) also deduplicates creation.

The only WhatsApp payload is:
“Você tem uma nova mensagem. Clique no botão abaixo para continuar.”
It uses the active invitation ID and its existing CTA/link; no invitation is
created, renewed or revoked, and no Web message body/attachment is mirrored.
The invitation metadata continues excluding the notification from public guest
history. The normal `can_reply?` / `MessageWindowService` policy is checked both
when creating and when delivering. Uno currently has no 24-hour restriction in
that service; this change does not bypass or change the configured policy. If
reply is disallowed, no free-form reminder or template fallback is sent.

Resolution, revocation, disabled attendance, changed cycle, visible return, or
reading the triggering message prevent delivery. The dedicated delivery job
does not call invitation activation. It persistently claims an attempt before
network I/O so a timeout, process crash or repeated job cannot resend it. This is
at-most-once delivery: an ambiguous failure can lose a notification, rather than
risk a duplicate. The Web payload remains Web-only.
