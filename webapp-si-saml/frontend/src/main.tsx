import React from "react";
import ReactDOM from "react-dom/client";
import "./index.css";
import App from "./App";
import { ThemeToggle } from "./components/ThemeToggle";

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <ThemeToggle />
    <App />
  </React.StrictMode>,
);
