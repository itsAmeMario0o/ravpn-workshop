export interface Quote {
  symbol: string;
  name: string;
  price: number;
  change: number;
  changePercent: number;
}

export interface PricePoint {
  t: string;
  v: number;
}

export interface Position {
  symbol: string;
  shares: number;
  avgCost: number;
  marketValue: number;
  unrealizedPl: number;
}
