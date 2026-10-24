// Shapes shared by the confirm / done dialogs and their fees editor.
export interface FeePart {
  id: string;
  name: string;
  price: number;
  qty: number;
}
export interface FeesState {
  // the parts used (quantity above zero)
  parts: FeePart[];
  fee: number | null;
  total: number;
  // the parts have been reviewed: some were entered, or "none used" is ticked
  // (or the category has no spare parts)
  checked: boolean;
  loaded: boolean;
}

