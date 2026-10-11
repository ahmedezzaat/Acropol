// Asks the server to email the "new deal" alert for a deal that was just added.
// It runs after the deal is saved and never blocks or fails the creation.
export function notifyNewDeal(dealId: string | null | undefined) {
  if (!dealId) return;
  $fetch("/api/notify/new-deal", { method: "POST", body: { deal_id: dealId } }).catch(() => {
    /* the deal is saved either way */
  });
}
