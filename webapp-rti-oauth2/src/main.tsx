import React from "react";
import ReactDOM from "react-dom/client";
import { AuthProvider } from "react-oidc-context";
import { oidcConfig } from "./oidcConfig";
import App from "./App";
import { ThemeToggle } from "./components/ThemeToggle";
import "./index.css";

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <AuthProvider {...oidcConfig}>
      <ThemeToggle />
      <App />
    </AuthProvider>
  </React.StrictMode>,
);
