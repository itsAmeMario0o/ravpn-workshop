import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
} from "recharts";
import { cn } from "../lib/utils";
import { generateChartSeries } from "../lib/data";

interface PriceChartProps {
  variant: "dark" | "light";
  symbol: string;
  seed: number;
}

export function PriceChart({ variant, symbol, seed }: PriceChartProps) {
  const data = generateChartSeries(seed);
  const stroke = variant === "dark" ? "#34d399" : "#059669";
  const grid = variant === "dark" ? "#27272a" : "#e2e8f0";
  const text = variant === "dark" ? "#a1a1aa" : "#64748b";
  const surface = variant === "dark" ? "bg-zinc-900 border-zinc-800" : "bg-white border-slate-200";

  return (
    <div className={cn("rounded-lg border p-4", surface)}>
      <div className="mb-3 flex items-baseline justify-between">
        <h2
          className={cn(
            "text-sm font-semibold uppercase tracking-wide",
            variant === "dark" ? "text-zinc-300" : "text-slate-700",
          )}
        >
          {symbol} - 90 day price
        </h2>
        <span className={cn("text-xs", text)}>seed:{seed}</span>
      </div>
      <div className="h-64 w-full">
        <ResponsiveContainer width="100%" height="100%">
          <LineChart data={data} margin={{ top: 5, right: 10, left: 0, bottom: 0 }}>
            <CartesianGrid stroke={grid} strokeDasharray="2 4" />
            <XAxis dataKey="t" stroke={text} fontSize={11} tickLine={false} />
            <YAxis stroke={text} fontSize={11} tickLine={false} domain={["auto", "auto"]} />
            <Tooltip
              contentStyle={{
                background: variant === "dark" ? "#18181b" : "#ffffff",
                border: `1px solid ${grid}`,
                borderRadius: 6,
                fontSize: 12,
              }}
              labelStyle={{ color: text }}
            />
            <Line type="monotone" dataKey="v" stroke={stroke} strokeWidth={2} dot={false} />
          </LineChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}
