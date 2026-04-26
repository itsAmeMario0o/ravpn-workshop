import type { Position, PricePoint, Quote } from "../types";

export const watchlist: Quote[] = [
  { symbol: "JPM", name: "JPMorgan Chase", price: 248.71, change: 1.84, changePercent: 0.74 },
  { symbol: "GS", name: "Goldman Sachs", price: 612.39, change: -3.14, changePercent: -0.51 },
  { symbol: "MS", name: "Morgan Stanley", price: 142.06, change: 0.92, changePercent: 0.65 },
  { symbol: "BAC", name: "Bank of America", price: 47.18, change: 0.21, changePercent: 0.45 },
  { symbol: "C", name: "Citigroup", price: 79.84, change: -0.55, changePercent: -0.69 },
  { symbol: "WFC", name: "Wells Fargo", price: 76.92, change: 1.12, changePercent: 1.48 },
];

export const positions: Position[] = [
  { symbol: "JPM", shares: 850, avgCost: 198.42, marketValue: 211403.5, unrealizedPl: 42738.0 },
  { symbol: "GS", shares: 220, avgCost: 540.18, marketValue: 134725.8, unrealizedPl: 15886.2 },
  { symbol: "MS", shares: 1100, avgCost: 128.55, marketValue: 156266.0, unrealizedPl: 14861.0 },
  { symbol: "BAC", shares: 4200, avgCost: 41.6, marketValue: 198156.0, unrealizedPl: 23436.0 },
];

export function generateChartSeries(seed: number, points = 90): PricePoint[] {
  const series: PricePoint[] = [];
  let value = 240 + (seed % 7);
  for (let i = 0; i < points; i++) {
    const drift = Math.sin(i / 6 + seed) * 1.4;
    const noise = ((seed * (i + 1)) % 11) / 11 - 0.5;
    value = Math.max(1, value + drift + noise);
    const day = new Date(Date.UTC(2026, 0, 1 + i)).toISOString().slice(5, 10);
    series.push({ t: day, v: Number(value.toFixed(2)) });
  }
  return series;
}

export const portfolioValue = positions.reduce((sum, p) => sum + p.marketValue, 0);
export const portfolioPl = positions.reduce((sum, p) => sum + p.unrealizedPl, 0);
