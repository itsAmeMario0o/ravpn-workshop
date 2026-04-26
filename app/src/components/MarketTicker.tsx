import { ArrowDown, ArrowUp } from "lucide-react";
import { cn, formatPercent } from "../lib/utils";
import { watchlist } from "../lib/data";

interface MarketTickerProps {
  variant: "dark" | "light";
}

export function MarketTicker({ variant }: MarketTickerProps) {
  return (
    <div
      className={cn(
        "flex items-center gap-6 overflow-x-auto whitespace-nowrap border-b px-6 py-2 text-sm font-mono",
        variant === "dark"
          ? "border-zinc-800 bg-zinc-950 text-zinc-300"
          : "border-slate-200 bg-white text-slate-700",
      )}
      role="marquee"
      aria-label="Market ticker"
    >
      {watchlist.map((q) => {
        const up = q.change >= 0;
        return (
          <span key={q.symbol} className="flex items-center gap-2">
            <span className="font-semibold">{q.symbol}</span>
            <span>${q.price.toFixed(2)}</span>
            <span
              className={cn(
                "flex items-center",
                up
                  ? variant === "dark"
                    ? "text-emerald-400"
                    : "text-emerald-600"
                  : variant === "dark"
                    ? "text-rose-400"
                    : "text-rose-600",
              )}
            >
              {up ? (
                <ArrowUp className="h-3 w-3" aria-hidden />
              ) : (
                <ArrowDown className="h-3 w-3" aria-hidden />
              )}
              {formatPercent(q.changePercent)}
            </span>
          </span>
        );
      })}
    </div>
  );
}
