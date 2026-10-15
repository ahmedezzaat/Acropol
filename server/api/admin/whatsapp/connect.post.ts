import * as z from "zod";

const bodySchema = z.object({
  // The one-time code the Embedded Signup dialog returns.
  code: z.string().trim().min(5).max(1000),
  // What the dialog reported on finishing (optional: looked up when missing).
  waba_id: z.string().trim().max(40).optional(),
  phone_number_id: z.string().trim().max(40).optional(),
});

interface PhoneInfo {
  id: string;
  display_phone_number?: string;
  verified_name?: string;
}

// Finishes "Connect WhatsApp": trades the Embedded Signup code for the
// business's access token, finds the connected number(s), saves them and
// subscribes Acropol to the WhatsApp Business Account's webhooks. In
// Coexistence mode the number keeps working in the WhatsApp Business app.
export default defineEventHandler(async (event) => {
  const { userId, adminClient } = await requireSetting(event, "integrations");
  const body = await readValidatedBody(event, bodySchema.parse);

  const { appId, appSecret } = await getWhatsappConfig(event);
  if (!appId || !appSecret) {
    throw createError({ statusCode: 400, statusMessage: "Save the Meta app id and the app secret first" });
  }

  // 1. code -> business token
  const tokenRes = await graph<{ access_token?: string }>("oauth/access_token", {
    query: { client_id: appId, client_secret: appSecret, code: body.code },
  });
  const token = tokenRes.access_token;
  if (!token) throw createError({ statusCode: 502, statusMessage: "Meta did not return an access token" });

  // 2. which business account? (the dialog tells us; otherwise ask Meta about the token)
  let wabaId = body.waba_id ?? "";
  if (!wabaId) {
    const debug = await graph<{ data?: { granular_scopes?: { scope: string; target_ids?: string[] }[] } }>("debug_token", {
      query: { input_token: token, access_token: `${appId}|${appSecret}` },
    });
    wabaId = debug.data?.granular_scopes?.find((s) => s.scope === "whatsapp_business_management")?.target_ids?.[0] ?? "";
  }
  if (!wabaId) throw createError({ statusCode: 502, statusMessage: "Could not find the WhatsApp Business Account" });

  // 3. its phone number(s)
  let phones: PhoneInfo[] = [];
  if (body.phone_number_id) {
    phones = [await graph<PhoneInfo>(body.phone_number_id, { token, query: { fields: "id,display_phone_number,verified_name" } })];
  } else {
    const list = await graph<{ data?: PhoneInfo[] }>(`${wabaId}/phone_numbers`, { token, query: { fields: "id,display_phone_number,verified_name" } });
    phones = list.data ?? [];
  }
  if (!phones.length) throw createError({ statusCode: 502, statusMessage: "The business account has no phone number" });

  // 4. receive its messages
  let subscribed = true;
  try {
    await graph(`${wabaId}/subscribed_apps`, { method: "POST", token });
  } catch {
    subscribed = false;
  }

  // 5. save (the token stays on the server)
  for (const p of phones) {
    const { error } = await adminClient.from("whatsapp_connections").upsert(
      {
        waba_id: wabaId,
        phone_number_id: p.id,
        display_phone_number: p.display_phone_number ?? null,
        verified_name: p.verified_name ?? null,
        coexistence: true,
        access_token: token,
        subscribed,
        connected_by: userId,
        connected_at: new Date().toISOString(),
      },
      { onConflict: "phone_number_id" },
    );
    if (error) throw createError({ statusCode: 500, statusMessage: error.message });
  }

  return { ok: true, subscribed, numbers: phones.map((p) => ({ phone_number_id: p.id, display_phone_number: p.display_phone_number ?? null })) };
});
