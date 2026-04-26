import { Activity } from "lucide-react";
import { AuthBadge } from "../components/AuthBadge";
import { MarketTicker } from "../components/MarketTicker";
import { PortfolioSummary } from "../components/PortfolioSummary";
import { PositionsTable } from "../components/PositionsTable";
import { PriceChart } from "../components/PriceChart";

export function VpnDashboard() {
  return (
    <div className="min-h-screen bg-zinc-950 text-zinc-100">
      <header className="flex items-center justify-between border-b border-zinc-800 px-6 py-4">
        <div className="flex items-center gap-3">
          <Activity className="h-5 w-5 text-emerald-400" aria-hidden />
          <h1 className="text-lg font-semibold tracking-tight">Trading Desk</h1>
          <span className="font-mono text-xs text-zinc-500">/vpn</span>
        </div>
        <AuthBadge variant="dark" mode="ravpn" />
      </header>
      <MarketTicker variant="dark" />
      <main className="mx-auto max-w-7xl space-y-6 p-6">
        <PortfolioSummary variant="dark" />
        <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
          <div className="lg:col-span-2">
            <PriceChart variant="dark" symbol="ACME" seed={11} />
          </div>
          <PositionsTable variant="dark" />
        </div>
      </main>
    </div>
  );
}
