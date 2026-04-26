import { TrendingUp, Wallet } from "lucide-react";
import { cn, formatCurrency, formatPercent } from "../lib/utils";
import { portfolioPl, portfolioValue } from "../lib/data";

interface PortfolioSummaryProps {
  variant: "dark" | "light";
}

export function PortfolioSummary({ variant }: PortfolioSummaryProps) {
  const plPercent = (portfolioPl / (portfolioValue - portfolioPl)) * 100;
  const plPositive = portfolioPl >= 0;

  const surface = variant === "dark" ? "bg-zinc-900 border-zinc-800" : "bg-white border-slate-200";
  const muted = variant === "dark" ? "text-zinc-400" : "text-slate-500";
  const value = variant === "dark" ? "text-zinc-50" : "text-slate-900";
  const accent = plPositive
    ? variant === "dark"
      ? "text-emerald-400"
      : "text-emerald-600"
    : variant === "dark"
      ? "text-rose-400"
      : "text-rose-600";

  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
      <div className={cn("rounded-lg border p-4", surface)}>
        <div className={cn("flex items-center gap-2 text-xs uppercase tracking-wide", muted)}>
          <Wallet className="h-4 w-4" aria-hidden />
          Portfolio value
        </div>
        <div className={cn("mt-2 text-2xl font-semibold tabular-nums", value)}>
          {formatCurrency(portfolioValue)}
        </div>
      </div>
      <div className={cn("rounded-lg border p-4", surface)}>
        <div className={cn("flex items-center gap-2 text-xs uppercase tracking-wide", muted)}>
          <TrendingUp className="h-4 w-4" aria-hidden />
          Unrealized P/L
        </div>
        <div className={cn("mt-2 text-2xl font-semibold tabular-nums", accent)}>
          {formatCurrency(portfolioPl)} ({formatPercent(plPercent)})
        </div>
      </div>
      <div className={cn("rounded-lg border p-4", surface)}>
        <div className={cn("flex items-center gap-2 text-xs uppercase tracking-wide", muted)}>
          Buying power
        </div>
        <div className={cn("mt-2 text-2xl font-semibold tabular-nums", value)}>
          {formatCurrency(412800)}
        </div>
      </div>
    </div>
  );
}
