import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import { VpnDashboard } from "./routes/VpnDashboard";
import { ZtaaDashboard } from "./routes/ZtaaDashboard";
import "./index.css";

const root = document.getElementById("root");
if (!root) throw new Error("missing #root");

createRoot(root).render(
  <StrictMode>
    <BrowserRouter>
      <Routes>
        <Route path="/vpn" element={<VpnDashboard />} />
        <Route path="/ztaa" element={<ZtaaDashboard />} />
        <Route path="*" element={<Navigate to="/vpn" replace />} />
      </Routes>
    </BrowserRouter>
  </StrictMode>,
);
