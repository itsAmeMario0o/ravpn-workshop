// App entry point. Two routes from one bundle: /vpn renders the dark
// dashboard for RAVPN users, /ztaa renders the light dashboard for ZTAA
// users. Anything else redirects to /vpn so a stray request doesn't 404.
//
// The two routes serve the same data and the same components - only the
// theme variant differs. That's intentional. The point of the demo is
// "same app, two access paths," and the visual difference makes it
// obvious to the audience which path the user took.

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
