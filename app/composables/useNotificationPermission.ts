export type NotificationPermissionState = NotificationPermission | "unsupported";

// Tracks the browser's notification permission. A site cannot grant itself
// this permission — only the user can, from a browser prompt that must be
// triggered by a click — so request() has to be called from a click handler.
export function useNotificationPermission() {
  const permission = useState<NotificationPermissionState>("notification-permission", () => "default");
  const ready = useState<boolean>("notification-permission-ready", () => false);
  // True once the user pressed "Enable" and the browser still has not granted
  // it: either they dismissed the prompt, or the browser never showed one
  // (Chrome stops showing it after a few dismissals and only puts a small icon
  // in the address bar; in-app browsers often never show it at all).
  const attempted = useState<boolean>("notification-permission-attempted", () => false);

  function read() {
    permission.value = "Notification" in window ? Notification.permission : "unsupported";
    ready.value = true;
  }

  async function request() {
    if (!("Notification" in window)) return;
    // The click that got us here also unlocks sound for later notifications.
    unlockAudio();
    try {
      // Older Safari only supports the callback form and returns undefined, so
      // support both; either way the real answer is read back from
      // Notification.permission afterwards.
      await new Promise<void>((resolve) => {
        const maybePromise = Notification.requestPermission(() => resolve()) as Promise<NotificationPermission> | undefined;
        if (maybePromise && typeof maybePromise.then === "function") maybePromise.then(() => resolve(), () => resolve());
        else setTimeout(resolve, 0);
      });
    } catch {
      /* fall through — we read the state below */
    }
    read();
    if (permission.value === "granted") {
      attempted.value = false;
      playNotificationSound();
    } else {
      attempted.value = true;
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

  return { permission, ready, attempted, request, recheck: read, watchChanges };
}
