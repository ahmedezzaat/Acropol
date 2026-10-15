# WhatsApp Coexistence in Acropol

**Coexistence** (Meta) lets one business number work in the **WhatsApp Business app on your
phone** and through the **WhatsApp Cloud API** at the same time. Acropol connects to it so
every new person who messages you becomes a lead, while your team keeps chatting from the phone
as usual.

## What Acropol does (first feature)

* **A lead for each new phone number.** The first message from a person creates a lead
  (name = their WhatsApp name or the number, source *WhatsApp*, notes = the message).
  Later messages from the same number create nothing; a number that is already a lead or a
  customer is never duplicated.
* **Chats you start from the phone app also create the lead** (Meta's `smb_message_echoes`
  field), named by the number.
* Imported chat history (`history`) and contact sync (`smb_app_state_sync`) are ignored: only new
  messages from now on become leads.

## Connect a number (Settings → Integrations → "ربط واتساب (Coexistence)")

1. In the **WhatsApp** section above, save the app secret (and the verify token).
2. In the Coexistence section save the **Meta app id** and the **Embedded Signup configuration id**.
3. Press **Connect WhatsApp**, sign in to Facebook, choose the number of your WhatsApp Business
   app and confirm on the phone when asked.
4. The number shows under *Connected numbers* as *Receiving messages*. **Disconnect** stops the
   webhook for it (the number keeps working in the phone app).

## Meta setup checklist (do this once, in developers.facebook.com)

1. Create a **Business** app and add the **WhatsApp** product. The business must be
   **verified**, and you need access to Embedded Signup (Tech Provider / Solution Partner
   onboarding, depending on your account).
2. **Facebook Login for Business → Configurations → Create configuration → WhatsApp Embedded
   Signup**, with the permissions *whatsapp_business_management* and *whatsapp_business_messaging*,
   and **Coexistence** enabled (the number is onboarded from the WhatsApp Business app). Copy the
   configuration id.
3. Login settings: add your Acropol domain to **Allowed domains for the JavaScript SDK** and to
   the valid OAuth redirect URIs, and enable **Login with the JavaScript SDK**.
4. **WhatsApp → Configuration → Webhook**: callback URL `https://YOUR-DOMAIN/api/webhooks/whatsapp`,
   verify token = the one saved in Acropol, then subscribe to the fields **messages** and
   **smb_message_echoes** (optionally `history` and `smb_app_state_sync`; Acropol ignores them).
5. The phone needs a recent WhatsApp Business app, and the number must have been used in it for
   some days; Coexistence is not available in every country: check Meta's current list.

## Server settings

| Setting | Where |
|---|---|
| Meta app id, Embedded Signup configuration id | Settings → Integrations, or `NUXT_WHATSAPP_APP_ID`, `NUXT_WHATSAPP_CONFIG_ID` |
| App secret, verify token, default assignee | Settings → Integrations (WhatsApp section), or the `NUXT_WHATSAPP_*` variables |
| `WHATSAPP_GRAPH_VERSION` (default `v23.0`) | optional environment variable |

The business access token received at connection is kept on the server only (table
`whatsapp_connections`, not readable from the browser).
