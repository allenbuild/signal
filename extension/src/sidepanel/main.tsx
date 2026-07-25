import { StrictMode } from "react";
import { createRoot } from "react-dom/client";

import { App } from "./App";
import "./sidepanel.css";

const root = document.getElementById("root");
if (!root) throw new Error("Signal side panel root is missing.");

createRoot(root).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
