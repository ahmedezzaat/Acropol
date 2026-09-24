export default defineNuxtPlugin(() => {
  const user = useSupabaseUser();
  const { load, clear } = usePermissions();

  watch(
    user,
    (value) => {
      if (value) load();
      else clear();
    },
    { immediate: true },
  );
});
