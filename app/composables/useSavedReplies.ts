// The inbox's saved replies (ردود جاهزة): one shared list for the reply box and the manager window,
// so a change made in one place shows in the other at once.
export interface SavedReply {
  id: string;
  title: string;
  body: string;
  shortcut: string | null;
  use_count: number;
}

export function useSavedReplies() {
  const supabase = useSupabaseClient();
  const replies = useState<SavedReply[]>("saved-replies", () => []);
  const loaded = useState<boolean>("saved-replies-loaded", () => false);

  async function load(force = false) {
    if (loaded.value && !force) return;
    const { data } = await supabase.from("whatsapp_saved_replies").select("id, title, body, shortcut, use_count").order("use_count", { ascending: false }).order("title");
    replies.value = (data ?? []) as SavedReply[];
    loaded.value = true;
  }
  // `id` null adds one; a duplicate shortcut comes back as error code 23505
  async function save(id: string | null, row: { title: string; body: string; shortcut: string | null }) {
    const { error } = id ? await supabase.from("whatsapp_saved_replies").update(row).eq("id", id) : await supabase.from("whatsapp_saved_replies").insert(row);
    if (!error) await load(true);
    return error;
  }
  async function remove(id: string) {
    const { error } = await supabase.from("whatsapp_saved_replies").delete().eq("id", id);
    if (!error) await load(true);
    return error;
  }
  async function used(r: SavedReply) {
    r.use_count++;
    await supabase.rpc("whatsapp_use_saved_reply", { p_id: r.id });
  }
  return { replies, load, save, remove, used };
}
