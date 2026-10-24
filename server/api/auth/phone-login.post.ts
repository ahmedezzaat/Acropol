import { createClient } from "@supabase/supabase-js";
import { serverSupabaseServiceRole } from "#supabase/server";
import * as z from "zod";

// Sign in with phone + password. The phone is looked up on the profile (it never leaves
// the server, which also keeps the email behind it private) and the password is checked
// by Supabase Auth; the session is handed back for the browser to adopt.
const bodySchema = z.object({ phone: z.string().min(1), password: z.string().min(1) });

export default defineEventHandler(async (event) => {
  const body = await readValidatedBody(event, bodySchema.parse);
  const phone = canonicalPhone(body.phone);
  // one answer for every failure, so the form never says which part was wrong
  const denied = () => createError({ statusCode: 401, statusMessage: "invalid_login" });
  if (!phone) throw denied();

  const admin = serverSupabaseServiceRole(event);
  const { data: profile } = await admin.from("profiles").select("email, is_active, can_login").eq("phone", phone).maybeSingle();
  if (!profile || !profile.is_active || !profile.can_login) throw denied();

  const config = useRuntimeConfig();
  const url = config.public.supabase?.url as string;
  const key = config.public.supabase?.key as string;
  const client = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data, error } = await client.auth.signInWithPassword({ email: profile.email, password: body.password });
  if (error || !data.session) throw denied();

  return { access_token: data.session.access_token, refresh_token: data.session.refresh_token };
});
