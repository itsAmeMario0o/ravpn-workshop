import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { ZtaaDashboard } from "./ZtaaDashboard";

describe("ZtaaDashboard", () => {
  it("renders the trading desk heading and the ZTAA auth badge", () => {
    render(<ZtaaDashboard />);
    expect(screen.getByRole("heading", { name: /trading desk/i })).toBeInTheDocument();
    expect(screen.getByText(/authenticated via ztaa/i)).toBeInTheDocument();
    expect(screen.getByText("/ztaa")).toBeInTheDocument();
  });
});
