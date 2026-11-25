// The classification of customers and contacts (فرد / فنادق / شركات ومصانع / مكاتب هندسة ...), kept in Settings.
export interface CustomerCategory {
  id: string;
  name: string;
  sort_order: number;
  // one maintenance visit per customer, not per product (e.g. فنادق)
  one_visit_per_customer: boolean;
  // customers of this category must have a tax card (البطاقة الضريبية)
  requires_tax_card: boolean;
}

export function useCustomerCategories() {
  const supabase = useSupabaseClient();
  const categories = useState<CustomerCategory[]>("customer-categories", () => []);

  async function loadCategories(force = false) {
    if (categories.value.length && !force) return;
    const { data, error } = await supabase.from("customer_categories").select("id, name, sort_order, one_visit_per_customer, requires_tax_card").order("sort_order");
    if (!error) {
      categories.value = (data ?? []) as CustomerCategory[];
      return;
    }
    // the "one visit per customer" and tax card columns arrive with their migrations: until then read without them
    const { data: basic } = await supabase.from("customer_categories").select("id, name, sort_order").order("sort_order");
    categories.value = ((basic ?? []) as Omit<CustomerCategory, "one_visit_per_customer" | "requires_tax_card">[]).map((c) => ({ ...c, one_visit_per_customer: false, requires_tax_card: false }));
  }
  // for a select: no classification first
  const categoryOptions = computed(() => categories.value.map((c) => ({ label: c.name, value: c.id as string | null })));
  const categoryName = (id: string | null | undefined) => (id ? (categories.value.find((c) => c.id === id)?.name ?? null) : null);

  // the category a customer saved without one gets (the database's rule): companies are شركات ومصانع, the rest فرد
  const defaultCategoryId = (type: "company" | "individual") => categories.value.find((c) => c.name === (type === "company" ? "شركات ومصانع" : "فرد"))?.id ?? null;

  return { categories, loadCategories, categoryOptions, categoryName, defaultCategoryId };
}
