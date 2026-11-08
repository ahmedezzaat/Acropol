// The WhatsApp link of a phone number: for people who can use the WhatsApp inbox it opens that person's chat
// there (or starts one); for everyone else it opens wa.me, as before.
export function useWaLink() {
  const { hasAnyModulePermission, isAdmin } = usePermissions();
  const inbox = computed(() => isAdmin.value || hasAnyModulePermission("crm_chats"));
  function waLink(phone: string | null | undefined): string | null {
    const digits = phoneDigits(phone);
    if (!digits) return null;
    return inbox.value ? `/crm/chats?phone=${digits}` : toWhatsAppLink(phone);
  }
  return { waLink };
}
