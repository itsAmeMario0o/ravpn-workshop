import { cn, formatCurrency } from "../lib/utils";
import { positions } from "../lib/data";

interface PositionsTableProps {
  variant: "dark" | "light";
}

export function PositionsTable({ variant }: PositionsTableProps) {
  const surface = variant === "dark" ? "bg-zinc-900 border-zinc-800" : "bg-white border-slate-200";
  const head = variant === "dark" ? "text-zinc-400" : "text-slate-500";
  const row = variant === "dark" ? "border-zinc-800" : "border-slate-200";
  const text = variant === "dark" ? "text-zinc-100" : "text-slate-900";

  return (
    <div className={cn("rounded-lg border p-4", surface)}>
      <h2
        className={cn(
          "mb-3 text-sm font-semibold uppercase tracking-wide",
          variant === "dark" ? "text-zinc-300" : "text-slate-700",
        )}
      >
        Open positions
      </h2>
      <table className="w-full text-sm">
        <thead>
          <tr className={cn("text-left text-xs uppercase tracking-wide", head)}>
            <th className="pb-2 font-medium">Symbol</th>
            <th className="pb-2 text-right font-medium">Shares</th>
            <th className="pb-2 text-right font-medium">Avg cost</th>
            <th className="pb-2 text-right font-medium">Market value</th>
            <th className="pb-2 text-right font-medium">P/L</th>
          </tr>
        </thead>
        <tbody>
          {positions.map((p) => {
            const up = p.unrealizedPl >= 0;
            const plClass = up
              ? variant === "dark"
                ? "text-emerald-400"
                : "text-emerald-600"
              : variant === "dark"
                ? "text-rose-400"
                : "text-rose-600";
            return (
              <tr key={p.symbol} className={cn("border-t", row)}>
                <td className={cn("py-2 font-mono font-semibold", text)}>{p.symbol}</td>
                <td className={cn("py-2 text-right tabular-nums", text)}>{p.shares}</td>
                <td className={cn("py-2 text-right tabular-nums", text)}>
                  {formatCurrency(p.avgCost)}
                </td>
                <td className={cn("py-2 text-right tabular-nums", text)}>
                  {formatCurrency(p.marketValue)}
                </td>
                <td className={cn("py-2 text-right tabular-nums", plClass)}>
                  {formatCurrency(p.unrealizedPl)}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
