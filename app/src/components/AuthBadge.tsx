import { Lock, ShieldCheck } from "lucide-react";
import { cn } from "../lib/utils";

interface AuthBadgeProps {
  variant: "dark" | "light";
  mode: "ravpn" | "ztaa";
}

export function AuthBadge({ variant, mode }: AuthBadgeProps) {
  const isRavpn = mode === "ravpn";
  const Icon = isRavpn ? Lock : ShieldCheck;
  const label = isRavpn ? "Authenticated via RAVPN" : "Authenticated via ZTAA + MFA";

  const badge =
    variant === "dark"
      ? "border-emerald-500/40 bg-emerald-500/10 text-emerald-300"
      : "border-emerald-500/40 bg-emerald-500/10 text-emerald-700";

  return (
    <span
      className={cn(
        "inline-flex items-center gap-2 rounded-full border px-3 py-1 text-xs font-medium",
        badge,
      )}
      data-testid="auth-badge"
    >
      <Icon className="h-3.5 w-3.5" aria-hidden />
      {label}
    </span>
  );
}
