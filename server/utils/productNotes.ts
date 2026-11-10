// The notes written on each product category (Admin -> Product categories) as a block for the assistants' prompts.
export function productNotesBlock(categories: { name: string; ai_notes?: string | null }[] | null): string {
  const lines = (categories ?? [])
    .filter((c) => c.ai_notes?.trim())
    .map((c) => `### ${c.name}\n${c.ai_notes!.trim().slice(0, 2000)}`);
  return lines.join("\n\n").slice(0, 10000);
}
