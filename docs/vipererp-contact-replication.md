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

Original dev validation: nine focused request specs passed against an isolated disposable local
PostgreSQL database, including API token, account membership, administrator-only
access, tuple ties, fixed windows, stale PATCH and private field preservation.
RuboCop passed on the controller, migration and specs. There was no production
request, migration, contact write, publication or deployment at that stage.

## Production deployment, 2026-10-18

The running VPS was newer than the generic `4.16.0` release baseline. Do not
replace its unified runtime with the generic `v4.16.12-viper.32-ce` image without
first reconciling the unified changes. The production fix is an additive image:

- Baseline: `viperchat:unified-20261018-r1`, image ID
  `sha256:040d6040bd4793e5f3afb0a1ace949752d609d097fc8d224e649c50d2c9a7843`.
- Active image: `viperchat:unified-20261018-r1-contact-sync`, image ID
  `sha256:36e3f912fd82db93a1dc58f95a2e7457cf56547fbfa2090a131927432a4fb593`.
- Patch source: commit `5b87f8dac`; image label
  `io.vipertec.contact-replication.revision=5b87f8dac`.

Only the replication controller, its targeted index migration and three route
declaration lines were added to the existing runtime. The original routes and
all other image files were retained. Web and both workers were recreated;
ViperConnect, PostgreSQL, Redis and push relay were not restarted. The live
read-only `/app/public/vite` bind mount was retained and persisted in Portainer,
along with the application image references.

Migration `20261017160000` ran by itself, not a general pending-migration sweep.
The concurrent index took approximately 0.15 seconds; PostgreSQL reported the
index ready/valid and EXPLAIN selected it for the bounded account query.

Read-only public API checks using the production backend's configured token:
account 1 returned two pages of 100 contacts with consistent ordering, versions
and a fixed upper bound; first page took 371 ms. Detail GET returned 200 and an
unauthenticated request returned 401. These probes ran from the workstation,
not inside the Windows backend VM. No contact PATCH, manual synchronization,
activation or automatic merge was performed. The ERP card must still be saved
by an authorized user before its disabled account enters the scheduled sync.

The three application containers were running without restarts or the searched
boot/migration errors after deployment. This is a bounded startup check, not a
claim that every background workflow is error-free.

Recovery directory on the VPS:
`/var/snap/docker/common/viperchat-hotpatch/contact-replication-20261018/`.
It contains the incremental build inputs, protected original configuration,
manifest, validation evidence and `rollback.py`. The protected logical database
backup is 248,276,473 bytes, SHA-256
`05da1d0082942740d1bf69b88a9584aed244112f78773845753a96cbf6c24686`.
Checksum and `pg_restore --list` were checked; a full restore was not rehearsed.

For code rollback, run `python3 rollback.py` from that recovery directory after
reviewing its state guards. It restores the previous web/worker image and saved
Portainer definition, without dropping the index or deleting contacts. Preserve
the baseline image and recovery directory while this rollback remains needed.
