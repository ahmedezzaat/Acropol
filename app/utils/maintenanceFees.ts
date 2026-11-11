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
  // a discount on the total (money, not a percentage): the total is after it
  discount: number | null;
  // a tax invoice (فاتورة ضريبية): the tax is added to the total after the discount
  taxInvoice: boolean;
  tax: number;
  total: number;
  // the parts have been reviewed: some were entered, or "none used" is ticked
  // (or the category has no spare parts)
  checked: boolean;
  loaded: boolean;
}


// Value-added tax added to the total of a work order when it is a tax invoice.
export const TAX_RATE = 0.14;
