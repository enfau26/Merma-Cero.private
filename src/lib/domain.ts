export type TenantRole = "owner" | "admin" | "manager" | "operator" | "viewer";

export type StockMovementType =
  | "receipt"
  | "sale"
  | "waste"
  | "adjustment_in"
  | "adjustment_out"
  | "return"
  | "transfer_in"
  | "transfer_out";

export interface ExpiryAlert {
  lotId: string;
  productName: string;
  warehouseName: string;
  quantityAvailable: number;
  expiresOn: string;
  daysUntilExpiry: number;
  estimatedCost: string; // decimal string, never JS float for money
}

export function classifyExpiry(days: number): "expired" | "urgent" | "soon" | "ok" {
  if (days < 0) return "expired";
  if (days <= 2) return "urgent";
  if (days <= 7) return "soon";
  return "ok";
}
