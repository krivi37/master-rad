import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// The SAML SP backend. The Vite dev server is the single public origin: it
// proxies /saml and /api to the backend so the session cookie stays first-party
// and Keycloak's ACS POST lands on http://localhost:4000/saml/acs.
const backend = process.env.BACKEND_URL ?? "http://localhost:4001";

export default defineConfig({
  plugins: [react()],
  server: {
    host: true,
    port: 4000,
    strictPort: true,
    proxy: {
      "/saml": { target: backend, changeOrigin: true },
      "/api": { target: backend, changeOrigin: true },
    },
  },
});
