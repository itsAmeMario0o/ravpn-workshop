import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { VpnDashboard } from "./VpnDashboard";

describe("VpnDashboard", () => {
  it("renders the trading desk heading and the RAVPN auth badge", () => {
    render(<VpnDashboard />);
    expect(screen.getByRole("heading", { name: /trading desk/i })).toBeInTheDocument();
    expect(screen.getByText(/authenticated via ravpn/i)).toBeInTheDocument();
    expect(screen.getByText("/vpn")).toBeInTheDocument();
  });
});
