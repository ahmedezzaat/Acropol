# Leads API & WhatsApp webhook

Two ways to create leads in Acropol from other software.

## 1. REST API — `POST /api/v1/leads`

Create an API key in **Settings → Integrations & API** (admins only). The full key is shown
once; only a hash is stored. Optionally pick a user that new leads are assigned to.

```bash
curl -X POST https://YOUR-DOMAIN/api/v1/leads \
  -H "Authorization: Bearer acr_xxxxxxxx" \
  -H "Content-Type: application/json" \
  -d '{"name":"Ahmed Ali","phone":"+201001234567","email":"ahmed@example.com","source":"website","notes":"Wants a solar heater"}'
```

(`X-API-Key: <key>` is accepted instead of the `Authorization` header.)

| Field | Notes |
| --- | --- |
| `name` | required |
| `phone`, `email` | at least one required |
| `phone2`, `notes`, `company_name` | optional |
| `lead_type` | `individual` (default) or `company` |
| `source` | `external_client`, `facebook`, `instagram`, `meta`, `google`, `website`, `event`, `referral`, `whatsapp`, `api` (default) |

Phone numbers are normalised (`0100…`, `+20100…`, `0020100…` are the same number) and stored as `+<country code><number>`.

| Response | Meaning |
| --- | --- |
| `201 {"status":"created","id":…}` | lead created |
| `200 {"status":"duplicate","entity":"lead"\|"customer","id":…}` | the phone already belongs to a lead/customer — nothing created |
| `400` | invalid body |
| `401` | missing, invalid or revoked key |

Leads created this way have no creator; they are unassigned unless the key has a default assignee.

## 2. WhatsApp Cloud API webhook — `/api/webhooks/whatsapp`

Every inbound WhatsApp message creates a lead for the sender (name = WhatsApp profile name,
notes = the first message, source = WhatsApp). If the number already belongs to a lead or
customer, nothing is created. Delivery/read receipts are ignored.

1. Set these environment variables on the server and restart:
   ```
   NUXT_WHATSAPP_VERIFY_TOKEN=<any string you choose>
   NUXT_WHATSAPP_APP_SECRET=<Meta app secret: App settings → Basic>
   NUXT_WHATSAPP_DEFAULT_ASSIGNEE_ID=<optional profile id>
   ```
2. In Meta for Developers → your app → WhatsApp → Configuration:
   - Callback URL: `https://YOUR-DOMAIN/api/webhooks/whatsapp` (must be public HTTPS —
     use a tunnel such as ngrok for local testing)
   - Verify token: the same string as `NUXT_WHATSAPP_VERIFY_TOKEN`
   - Subscribe to the **messages** field.

Requests are authenticated with Meta's `X-Hub-Signature-256` HMAC (keyed with the app secret).
Until `NUXT_WHATSAPP_APP_SECRET` is set the endpoint answers `503`.

## How duplicates are decided

`api_create_lead()` (Postgres) compares normalised phone digits against every lead's
`phone`/`phone2` and every customer's `phone`, under a per-number advisory lock — so two
simultaneous messages from one person still create exactly one lead.
