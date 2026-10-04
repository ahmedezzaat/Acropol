import type { RealtimeChannel } from "@supabase/supabase-js";

export interface AppNotification {
  id: string;
  user_id: string;
  type:
    | "deal_assigned"
    | "lead_assigned"
    | "activity_scheduled"
    | "activity_reminder"
    | "deal_unassigned"
    | "deals_unassigned";
  params: Record<string, unknown>;
  is_read: boolean;
  created_at: string;
}

interface ProfileName {
  id: string;
  full_name: string | null;
  email: string;
}

const PAGE_SIZE = 50;

// Shared notification state for the signed-in user. Everything lives in
// useState so the bell (desktop sidebar), the floating bell (phones) and the
// panel all read the same list.
export function useNotifications() {
  const supabase = useSupabaseClient();
  const { t, locale } = useI18n();

  const items = useState<AppNotification[]>("notifications", () => []);
  const open = useState<boolean>("notifications-open", () => false);
  const profiles = useState<ProfileName[]>("notifications-profiles", () => []);

  const unreadCount = computed(() => items.value.filter((n) => !n.is_read).length);

  function personName(id: unknown) {
    if (typeof id !== "string") return null;
    const p = profiles.value.find((p) => p.id === id);
    return p ? p.full_name || p.email : null;
  }

  function formatWhen(value: unknown) {
    if (typeof value !== "string") return "";
    return new Date(value).toLocaleString(locale.value === "ar" ? "ar" : "en", {
      dateStyle: "medium",
      timeStyle: "short",
    });
  }

  // Turns a stored type + params into text in the viewer's language, the page
  // it points at, and an icon. Rows carry no text of their own on purpose.
  function describe(n: AppNotification) {
    const p = n.params;
    const by = personName(p.assigned_by);
    const name = String(p.name ?? "");
    const base = { name, by: by ?? "", type: String(p.activity_type ?? ""), when: formatWhen(p.scheduled_at) };

    switch (n.type) {
      case "deal_assigned":
        return {
          icon: "i-lucide-briefcase",
          color: "primary" as const,
          text: by ? t("notifications.dealAssignedBy", base) : t("notifications.dealAssigned", base),
          link: `/crm/deals/${p.deal_id}`,
        };
      case "lead_assigned":
        return {
          icon: "i-lucide-user-plus",
          color: "primary" as const,
          text: by ? t("notifications.leadAssignedBy", base) : t("notifications.leadAssigned", base),
          link: `/crm/leads/${p.lead_id}`,
        };
      case "activity_scheduled":
        return {
          icon: "i-lucide-calendar-plus",
          color: "info" as const,
          text: by ? t("notifications.activityScheduledBy", base) : t("notifications.activityScheduled", base),
          link: `/crm/deals/${p.deal_id}`,
        };
      case "deal_unassigned": {
        const rule = String(p.rule_name ?? "");
        const unassignedBy = personName(p.unassigned_by);
        return {
          icon: "i-lucide-user-x",
          color: "warning" as const,
          text: rule
            ? t("notifications.dealUnassignedRule", { ...base, rule })
            : unassignedBy
              ? t("notifications.dealUnassignedBy", { ...base, by: unassignedBy })
              : t("notifications.dealUnassigned", base),
          link: `/crm/deals/${p.deal_id}`,
        };
      }
      case "deals_unassigned": {
        // Opens the board already filtered to the unassigned deals in the
        // rule's stage, so the manager can reassign them straight away.
        const query = new URLSearchParams({ assignee: "unassigned" });
        if (p.pipeline_id) query.set("pipeline", String(p.pipeline_id));
        if (p.stage_id) query.set("stage", String(p.stage_id));
        return {
          icon: "i-lucide-users-round",
          color: "warning" as const,
          text: t("notifications.dealsUnassigned", {
            rule: String(p.rule_name ?? ""),
            count: Number(p.count ?? 0),
            stage: String(p.stage_name ?? ""),
          }),
          link: `/crm/deals?${query.toString()}`,
        };
      }
      default:
        return {
          icon: "i-lucide-alarm-clock",
          color: "warning" as const,
          text: t("notifications.activityReminder", { ...base, attempt: Number(p.attempt ?? 1), max: Number(p.max ?? 4) }),
          link: `/crm/deals/${p.deal_id}`,
        };
    }
  }

  async function load() {
    const [{ data: rows }, { data: people }] = await Promise.all([
      supabase.from("notifications").select("*").order("created_at", { ascending: false }).limit(PAGE_SIZE),
      supabase.from("profiles").select("id, full_name, email"),
    ]);
    items.value = (rows ?? []) as AppNotification[];
    profiles.value = people ?? [];
  }

  async function markRead(n: AppNotification) {
    if (n.is_read) return;
    n.is_read = true;
    await supabase.from("notifications").update({ is_read: true }).eq("id", n.id);
  }

  async function markAllRead() {
    const unread = items.value.filter((n) => !n.is_read);
    if (!unread.length) return;
    unread.forEach((n) => (n.is_read = true));
    await supabase
      .from("notifications")
      .update({ is_read: true })
      .in(
        "id",
        unread.map((n) => n.id),
      );
  }

  return { items, open, unreadCount, describe, load, markRead, markAllRead };
}

// Call once, from the layout: loads the list, then listens for new rows for
// this user (Realtime applies the table's RLS, so only their own arrive) and
// surfaces each one as a toast, plus a desktop notification when the tab is
// in the background and the user has allowed them.
export function useNotificationsRealtime() {
  const supabase = useSupabaseClient();
  const user = useSupabaseUser();
  const toast = useToast();
  const { t } = useI18n();
  const { items, open, describe, load, markRead } = useNotifications();

  let channel: RealtimeChannel | null = null;
  let subscribedFor: string | null = null;

  function stop() {
    if (channel) supabase.removeChannel(channel);
    channel = null;
    subscribedFor = null;
  }

  async function start(userId: string) {
    if (subscribedFor === userId) return;
    stop();
    subscribedFor = userId;
    await load();

    channel = supabase
      .channel(`notifications:${userId}`)
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "notifications", filter: `user_id=eq.${userId}` },
        (payload) => {
          const n = payload.new as AppNotification;
          if (items.value.some((x) => x.id === n.id)) return;
          items.value = [n, ...items.value].slice(0, 100);

          const d = describe(n);
          playNotificationSound();
          toast.add({
            title: d.text,
            icon: d.icon,
            color: d.color,
            duration: 8000,
            actions: [
              {
                label: t("notifications.open"),
                color: "neutral",
                variant: "outline",
                onClick: () => {
                  markRead(n);
                  open.value = false;
                  navigateTo(d.link);
                },
              },
            ],
          });

          if (import.meta.client && document.hidden && "Notification" in window && Notification.permission === "granted") {
            new Notification(t("nav.appName"), { body: d.text, tag: n.id, silent: false });
          }
        },
      )
      .subscribe();
  }

  if (import.meta.client) {
    watch(
      () => user.value?.sub as string | undefined,
      (id) => {
        if (id) start(id);
        else stop();
      },
      { immediate: true },
    );
    onBeforeUnmount(stop);
  }
}
