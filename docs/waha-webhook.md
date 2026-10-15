# WAHA webhook (WhatsApp via WAHA)

`POST /api/webhooks/whatsapp` accepts [WAHA](https://waha.devlike.pro) webhooks (any engine)
and creates a lead for every **new** person who messages your WhatsApp number. The same URL
still serves Meta's WhatsApp Cloud API (recognised by its `X-Hub-Signature-256` header);
`/api/v1/leads` is untouched.

## WAHA setup

In the WAHA session config:

```json
"webhooks": [{
  "url": "https://YOUR-DOMAIN/api/webhooks/whatsapp",
  "events": ["message"],
  "hmac": { "key": "<same value as WAHA_WEBHOOK_HMAC_KEY>" }
}]
```

and/or a custom header `X-Webhook-Secret: <same value as WAHA_WEBHOOK_SECRET>`
(`"customHeaders": [{ "name": "X-Webhook-Secret", "value": "..." }]`).

## Environment variables (Vercel → Project → Settings → Environment Variables)

| Variable | Required | What it is |
|---|---|---|
| `WAHA_WEBHOOK_HMAC_KEY` | one of the two (recommended) | Key WAHA signs the raw body with (`X-Webhook-Hmac`, sha512 or sha256). |
| `WAHA_WEBHOOK_SECRET` | one of the two | Must equal the `X-Webhook-Secret` header WAHA sends. |
| `WAHA_DEFAULT_ASSIGNEE_ID` | optional | Profile id new leads are assigned to; falls back to `NUXT_WHATSAPP_DEFAULT_ASSIGNEE_ID`. |

Every variable that is set must pass, so setting both requires both. **If neither is set the
endpoint accepts unauthenticated calls** (logged as a warning) so you can try it in development.
Set at least one in Production, then redeploy.

## What happens to a message

| Case | Response |
|---|---|
| New person (`<digits>@c.us`) | `{"ok":true,"action":"created","id":...}` and a lead: name = WhatsApp name or the phone, phone `+<digits>`, source `whatsapp`, notes `First message: <text>` (`[media]` for media-only, `[no text]` if empty) |
| Phone already a lead (phone or phone 2) or a customer | `{"ok":true,"action":"duplicate",...}` — nothing created |
| Our own message (`fromMe`), group (`@g.us`), `status@broadcast`, any event other than `message` | `{"ok":true,"action":"ignored"}` |
| `@lid` sender: real number taken from `_data.key.remoteJidAlt` or `senderPn`; if none | created/duplicate, or `ignored` (logged) |
| Wrong/missing signature or secret | `401` |
| Unparseable body | `400`; body over 256 KB `413` |
| Database failure | `500` (WAHA retries; safe, see below) |

Duplicates are decided in Postgres by `api_create_lead()`: one advisory lock per phone number,
checked against every lead and customer, so two messages arriving at the same instant, or a
retried delivery, create exactly one lead. No extra unique index is needed (and one on
`leads.phone` would clash with existing leads that share a number or use phone 2).
Names and text are stripped of control characters, trimmed and length-limited before storing.

## Test

```bash
BASE_URL=http://localhost:3000 \
WAHA_WEBHOOK_HMAC_KEY=... WAHA_WEBHOOK_SECRET=... \
node scripts/test-waha-webhook.mjs
```

It sends: normal person, duplicate, group, status broadcast, fromMe, `@lid` without/with a
number, media-only, two simultaneous messages, other events, invalid JSON, wrong HMAC and no
auth. The "created" cases make real leads (notes start `First message: [waha-test ...]`), so run
it against a development project and delete them afterwards.
