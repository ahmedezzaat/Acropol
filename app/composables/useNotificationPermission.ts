export type NotificationPermissionState = NotificationPermission | "unsupported";

// Tracks the browser's notification permission. A site cannot grant itself
// this permission — only the user can, from a browser prompt that must be
// triggered by a click — so request() has to be called from a click handler.
export function useNotificationPermission() {
  const permission = useState<NotificationPermissionState>("notification-permission", () => "default");
  const ready = useState<boolean>("notification-permission-ready", () => false);

  function read() {
    permission.value = "Notification" in window ? Notification.permission : "unsupported";
    ready.value = true;
  }

  async function request() {
    if (!("Notification" in window)) return;
    // The click that got us here also unlocks sound for later notifications.
    unlockAudio();
    try {
      await Notification.requestPermission();
    } finally {
      read();
      if (permission.value === "granted") playNotificationSound();
    }
  }

  // Follows changes made in the browser's site settings while the page is open
  // (Chromium/Firefox); recheck() covers browsers that don't report them.
  async function watchChanges() {
    read();
    try {
      const status = await navigator.permissions.query({ name: "notifications" as PermissionName });
      status.onchange = read;
    } catch {
      /* not supported — the "check again" button covers it */
    }
  }

  return { permission, ready, request, recheck: read, watchChanges };
}
