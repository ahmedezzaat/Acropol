// Calls to Meta's Graph API for the WhatsApp Embedded Signup (Coexistence).
// WHATSAPP_GRAPH_VERSION / WHATSAPP_GRAPH_BASE_URL can be overridden (the base
// URL is how the tests point it at a local fake).
const VERSION = () => process.env.WHATSAPP_GRAPH_VERSION || "v23.0";
const BASE = () => (process.env.WHATSAPP_GRAPH_BASE_URL || "https://graph.facebook.com").replace(/\/$/, "");

export async function graph<T>(
  path: string,
  opts: { method?: "GET" | "POST" | "DELETE"; token?: string; query?: Record<string, string> } = {},
): Promise<T> {
  const url = new URL(`${BASE()}/${VERSION()}/${path.replace(/^\//, "")}`);
  for (const [k, v] of Object.entries(opts.query ?? {})) url.searchParams.set(k, v);
  try {
    return (await $fetch(url.toString(), {
      method: opts.method ?? "GET",
      headers: opts.token ? { Authorization: `Bearer ${opts.token}` } : undefined,
    })) as T;
  } catch (err: any) {
    // Meta puts the human-readable reason in error.message.
    const reason = err?.data?.error?.message ?? err?.message ?? "Graph API call failed";
    throw createError({ statusCode: 502, statusMessage: `Meta: ${reason}` });
  }
}
