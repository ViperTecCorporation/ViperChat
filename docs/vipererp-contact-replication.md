# ViperERP contact replication

The ViperERP backend polls the account-scoped replication API every ten minutes
(configurable to five). This is a backend integration, not an n8n workflow.

Endpoints: `GET /api/v1/accounts/:account_id/vipererp_contacts/changes`,
`GET .../vipererp_contacts/:id`, `PATCH .../vipererp_contacts/:id`.
Requires an authenticated account administrator; membership, API-feature and
per-record authorization remain in the existing controller chain. No AgentBot
or cross-account bypass. The regular contacts API is unchanged.

The changes endpoint accepts nonnegative `since` (Unix microseconds), `after_id`,
optional fixed `until`, and `limit` from one to 100. It uses indexed tuple ordering
`(updated_at,id)` and a server-clock ceiling five seconds behind now, without
OFFSET, total count, avatars or inbox expansion. The response contains compact
records (id, name, phone_number, modified, version) and a continuation cursor.
The backend overlaps completed windows by two minutes and periodically reconciles
the directory in bounded pages. This is not an immutable snapshot or CDC stream.

PATCH requires `expected_version`, name (up to 150 characters) and a valid E.164
phone number. Under a row lock, a stale version returns 409 without changing the
contact. Successful changes reuse the existing WhatsApp contact-inbox source-ID
maintenance. Identifier, blocked, private attributes and email are not overwritten.

Deploy migration `20261017160000_index_contacts_replication_cursor` before enabling
the backend task. It adds an account/updated_at/id index concurrently. This change
does not deploy itself and does not require native/mobile bundles: it is an
additive machine API with no frontend or Capacitor changes.

Validation: nine focused request specs passed against an isolated disposable local
PostgreSQL database, including API token, account membership, administrator-only
access, tuple ties, fixed windows, stale PATCH and private field preservation.
RuboCop passed on the controller, migration and specs. There was no production
request, migration, contact write, publication or deployment in this task.
