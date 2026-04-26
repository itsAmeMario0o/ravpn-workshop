import { Activity } from "lucide-react";
import { AuthBadge } from "../components/AuthBadge";
import { MarketTicker } from "../components/MarketTicker";
import { PortfolioSummary } from "../components/PortfolioSummary";
import { PositionsTable } from "../components/PositionsTable";
import { PriceChart } from "../components/PriceChart";

export function ZtaaDashboard() {
  return (
    <div className="min-h-screen bg-slate-50 text-slate-900">
      <header className="flex items-center justify-between border-b border-slate-200 bg-white px-6 py-4">
        <div className="flex items-center gap-3">
          <Activity className="h-5 w-5 text-emerald-600" aria-hidden />
          <h1 className="text-lg font-semibold tracking-tight">Trading Desk</h1>
          <span className="font-mono text-xs text-slate-500">/ztaa</span>
        </div>
        <AuthBadge variant="light" mode="ztaa" />
      </header>
      <MarketTicker variant="light" />
      <main className="mx-auto max-w-7xl space-y-6 p-6">
        <PortfolioSummary variant="light" />
        <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
          <div className="lg:col-span-2">
            <PriceChart variant="light" symbol="ACME" seed={11} />
          </div>
          <PositionsTable variant="light" />
        </div>
      </main>
    </div>
  );
}
