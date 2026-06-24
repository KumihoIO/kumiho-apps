import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";
import { checkForUpdates } from "./updater";
import "./styles.css";

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);

// Best-effort, non-blocking auto-update check (no-op until updater is configured).
void checkForUpdates();
