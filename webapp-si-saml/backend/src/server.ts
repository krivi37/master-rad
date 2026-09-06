import express, {
  type Request,
  type RequestHandler,
  type Response,
} from "express";
import session from "express-session";
import passport from "passport";
import {
  Strategy as SamlStrategy,
  type Profile,
  type VerifiedCallback,
} from "@node-saml/passport-saml";

const config = {
  port: Number(process.env.PORT ?? 4001),
  frontendUrl: process.env.FRONTEND_URL ?? "http://si1.localhost:4000",
  entryPoint:
    process.env.SAML_ENTRY_POINT ??
    "http://si.localhost:8082/realms/si/protocol/saml",
  idpIssuer:
    process.env.SAML_IDP_ISSUER ?? "http://si.localhost:8082/realms/si",
  issuer: process.env.SAML_ISSUER ?? "webapp-si-saml",
  callbackUrl:
    process.env.SAML_ACS_URL ?? "http://si1.localhost:4000/saml/acs",
  // Keycloak's SLS endpoint that receives our LogoutRequest (same path as login).
  logoutUrl:
    process.env.SAML_LOGOUT_URL ??
    "http://si.localhost:8082/realms/si/protocol/saml",
  // Our SP endpoint where Keycloak returns the LogoutResponse.
  logoutCallbackUrl:
    process.env.SAML_SLS_URL ?? "http://si1.localhost:4000/saml/sls",
  metadataUrl:
    process.env.SAML_METADATA_URL ??
    "http://keycloak-si:8080/realms/si/protocol/saml/descriptor",
  sessionSecret: process.env.SESSION_SECRET ?? "webapp-si-saml-dev-secret",
};

type SamlAttributes = Record<string, string | string[]>;

interface SamlUser {
  nameID: string;
  nameIDFormat?: string;
  sessionIndex?: string;
  issuer?: string;
  sessionNotOnOrAfter?: string;
  attributes: SamlAttributes;
  assertionXml: string;
  authType?: "saml" | "local";
  [key: string]: unknown;
}

interface LocalCredential {
  username: string;
  password: string;
  name: string;
  email: string;
}

// Local accounts live ONLY inside this app: they are unknown to Keycloak SI and
// the LDAP directory. There is no IdP session behind them, so they get no SSO —
// the session cookie is the whole login, and deleting it logs the user out for
// good. Other instances never share it, so each one demands a fresh login.
const LOCAL_USERS: LocalCredential[] = [
  {
    username: "sonja-local",
    password: "local",
    name: "Sonja Local (SI app)",
    email: "sonja@local.si",
  },
  {
    username: "ljubo-local",
    password: "local",
    name: "Ljubo Local (SI app)",
    email: "ljubo@local.si",
  },
];

declare global {
  namespace Express {
    interface User extends SamlUser {}
  }
}

const delay = (milliseconds: number) =>
  new Promise((resolve) => setTimeout(resolve, milliseconds));

function toPem(certificate: string): string {
  const body = certificate.replace(/\s+/g, "");
  const lines = body.match(/.{1,64}/g)?.join("\n") ?? body;
  return `-----BEGIN CERTIFICATE-----\n${lines}\n-----END CERTIFICATE-----`;
}

async function loadIdpCertificate(): Promise<string> {
  for (let attempt = 1; attempt <= 60; attempt += 1) {
    try {
      const response = await fetch(config.metadataUrl);
      if (!response.ok) throw new Error(`HTTP ${response.status}`);

      const metadata = await response.text();
      const certificate = metadata.match(
        /<(?:[\w-]+:)?X509Certificate>([\s\S]*?)<\/(?:[\w-]+:)?X509Certificate>/,
      )?.[1];
      if (!certificate) throw new Error("Signing certificate not found");

      console.log(`Fetched IdP signing certificate from ${config.metadataUrl}`);
      return toPem(certificate);
    } catch (error) {
      console.log(
        `Waiting for Keycloak metadata (${attempt}/60): ${(error as Error).message}`,
      );
      await delay(2000);
    }
  }

  throw new Error(`Could not load IdP metadata from ${config.metadataUrl}`);
}

function normalizeAttributes(
  attributes: Record<string, unknown> = {},
): SamlAttributes {
  return Object.fromEntries(
    Object.entries(attributes).map(([name, value]) => [
      name,
      Array.isArray(value) ? value.map(String) : String(value),
    ]),
  );
}

function toUser(profile: Profile): SamlUser {
  const assertionXml = profile.getSamlResponseXml?.() ?? "";
  return {
    nameID: profile.nameID,
    nameIDFormat: profile.nameIDFormat,
    sessionIndex: profile.sessionIndex,
    issuer: typeof profile.issuer === "string" ? profile.issuer : undefined,
    sessionNotOnOrAfter: assertionXml.match(
      /SessionNotOnOrAfter="([^"]+)"/,
    )?.[1],
    attributes: normalizeAttributes(profile.attributes),
    assertionXml,
  };
}

function createStrategy(idpCert: string): SamlStrategy {
  return new SamlStrategy(
    {
      callbackUrl: config.callbackUrl,
      entryPoint: config.entryPoint,
      logoutUrl: config.logoutUrl,
      logoutCallbackUrl: config.logoutCallbackUrl,
      issuer: config.issuer,
      idpCert,
      idpIssuer: config.idpIssuer,
      audience: config.issuer,
      identifierFormat: "urn:oasis:names:tc:SAML:1.1:nameid-format:unspecified",
      wantAssertionsSigned: true,
      wantAuthnResponseSigned: true,
      signatureAlgorithm: "sha256",
      digestAlgorithm: "sha256",
      acceptedClockSkewMs: 3000,
      disableRequestedAuthnContext: true,
    },
    (profile: Profile | null, done: VerifiedCallback) => {
      profile
        ? done(null, toUser(profile))
        : done(new Error("Empty SAML profile"));
    },
    (profile: Profile | null, done: VerifiedCallback) =>
      done(null, profile ?? undefined),
  );
}

function clearSession(req: Request, res: Response): void {
  req.logout(() => {
    req.session.destroy(() => {
      res.clearCookie("webapp_b_sid");
      res.redirect(config.frontendUrl);
    });
  });
}

function registerRoutes(app: express.Express, strategy: SamlStrategy): void {
  const authenticate = passport.authenticate("saml") as RequestHandler;

  app.get("/saml/login", authenticate);

  app.post("/saml/acs", (req: Request, res: Response, next) => {
    passport.authenticate(
      "saml",
      (error: Error | null, user?: Express.User | false) => {
        if (error || !user) {
          console.warn("Rejected SAML response:", error?.message);
          res.status(403).send("SAML assertion rejected.");
          return;
        }

        req.logIn(user, (loginError) => {
          if (loginError) {
            next(loginError);
            return;
          }
          res.redirect(config.frontendUrl);
        });
      },
    )(req, res, next);
  });

  app.get("/saml/logout", (req, res) => {
    if (!req.isAuthenticated()) {
      res.redirect(config.frontendUrl);
      return;
    }

    strategy.logout(
      req as Parameters<typeof strategy.logout>[0],
      (error, logoutUrl) => {
        if (error || !logoutUrl) {
          console.error("Could not create LogoutRequest", error);
          clearSession(req, res);
          return;
        }
        res.redirect(logoutUrl);
      },
    );
  });

  const finishLogout: RequestHandler = (req, res) => clearSession(req, res);
  app.get("/saml/sls", authenticate, finishLogout);
  app.post("/saml/sls", authenticate, finishLogout);
  app.get("/saml/local-logout", finishLogout);

  app.post("/local/login", (req: Request, res: Response, next) => {
    const { username, password } = (req.body ?? {}) as {
      username?: string;
      password?: string;
    };
    const match = LOCAL_USERS.find(
      (candidate) =>
        candidate.username === username && candidate.password === password,
    );
    if (!match) {
      res.status(401).json({ error: "Invalid local credentials" });
      return;
    }

    const user: SamlUser = {
      nameID: match.username,
      authType: "local",
      issuer: "local-accounts (webapp-si-saml)",
      attributes: { displayName: match.name, email: match.email },
      assertionXml: "",
    };
    req.logIn(user, (loginError) => {
      if (loginError) {
        next(loginError);
        return;
      }
      res.json({ ok: true });
    });
  });

  app.get("/saml/metadata", (_req, res) => {
    res
      .type("application/xml")
      .send(strategy.generateServiceProviderMetadata(null, null));
  });

  app.get("/api/session", (req, res) => {
    if (!req.isAuthenticated() || !req.user) {
      res.status(403).json({ error: "Not authenticated" });
      return;
    }

    const user = req.user;
    res.json({
      subject: user.nameID,
      issuer: user.issuer ?? "",
      nameIDFormat: user.nameIDFormat,
      sessionIndex: user.sessionIndex,
      sessionNotOnOrAfter: user.sessionNotOnOrAfter,
      attributes: user.attributes,
      assertionXml: user.assertionXml,
      authType: user.authType ?? "saml",
    });
  });
}

async function main(): Promise<void> {
  const strategy = createStrategy(await loadIdpCertificate());
  passport.use("saml", strategy);
  passport.serializeUser((user, done) => done(null, user));
  passport.deserializeUser((user, done) => done(null, user as Express.User));

  const app = express();
  app.set("trust proxy", 1);
  app.use(express.urlencoded({ extended: false, limit: "5mb" }));
  app.use(express.json());
  app.use(
    session({
      name: "webapp_b_sid",
      secret: config.sessionSecret,
      resave: false,
      saveUninitialized: false,
      cookie: {
        httpOnly: true,
        sameSite: "lax",
        secure: false,
        maxAge: 60 * 60 * 1000,
      },
    }),
  );
  app.use(passport.initialize());
  app.use(passport.session());

  registerRoutes(app, strategy);
  app.listen(config.port, () => {
    console.log(`Web Application B listening on port ${config.port}`);
  });
}

main().catch((error) => {
  console.error("Fatal startup error:", error);
  process.exit(1);
});