# Uno profile picture metadata

UnoProvider webhooks may include profile picture metadata beside contact and group picture URLs.

The picture URL path is stable for each contact or group, while the presigned
query string changes frequently. Chatwoot therefore calculates avatar sync
signatures from the normalized URL plus metadata when available.

## Contact avatar

```json
{
  "profile": {
    "picture": "https://.../profile-pictures/556699999999.jpg?...",
    "picture_metadata": {
      "etag": "\"eaed9c5735d6cdf4b5416c800fb39868\"",
      "last_modified": "2026-06-15T19:24:29.000Z",
      "content_length": "41053",
      "content_type": "image/jpeg"
    }
  }
}
```

## Group avatar

```json
{
  "group_picture": "https://.../profile-pictures/120363040468224422%40g.us.jpg?...",
  "group_picture_metadata": {
    "etag": "\"eaed9c5735d6cdf4b5416c800fb39868\"",
    "last_modified": "2026-06-15T19:24:29.000Z",
    "content_length": "41053",
    "content_type": "image/jpeg"
  }
}
```

## Sync behavior

`Avatar::AvatarFromUrlJob` accepts optional metadata and stores the generated signature in contact `additional_attributes.avatar_url_hash`.

The signature uses:

- normalized URL without query string or fragment
- `etag`
- `last_modified`
- `content_length`
- `content_type`

If UnoProvider sends no metadata, Chatwoot attempts a lightweight ranged request
with `Range: bytes=0-0` and reads `ETag`, `Last-Modified`, `Content-Range`,
and `Content-Type` from the response.
