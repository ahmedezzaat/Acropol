// The API returns at most 1000 rows per request, so a list that can grow past
// that has to be read in pages. `build` makes one page of the query for the
// given row range; give the query a stable order (end it with .order("id")).
// Several pages are requested at once (a short or empty page ends the list), so a
// few thousand rows cost one round trip instead of one per page.
export async function fetchAll<T>(
  build: (from: number, to: number) => PromiseLike<{ data: T[] | null; error: { message: string } | null }>,
  pageSize = 1000,
  concurrency = 3,
): Promise<T[]> {
  const rows: T[] = [];
  for (let page = 0; ; page += concurrency) {
    const batch = await Promise.all(
      Array.from({ length: concurrency }, (_, i) => build((page + i) * pageSize, (page + i + 1) * pageSize - 1)),
    );
    for (const { data, error } of batch) {
      if (error) throw error;
      rows.push(...(data ?? []));
      if (!data || data.length < pageSize) return rows;
    }
  }
}
