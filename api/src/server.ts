import cors from "cors";
import express, {
  type NextFunction,
  type Request,
  type RequestHandler,
  type Response,
} from "express";
import jwksRsa from "jwks-rsa";
import passport from "passport";
import {
  ExtractJwt,
  Strategy as JwtStrategy,
  type StrategyOptionsWithoutRequest,
  type VerifiedCallback,
} from "passport-jwt";

// OAuth 2.0 resource server. This lab accepts tokens from Keycloak A (rti)
// only: Web Application A logs in against Keycloak A, and federated users from
// Keycloak B are brokered into rti so they still receive an rti-issued token.
// To also trust Keycloak B directly, register a second JWT strategy.
const config = {
  port: Number(process.env.PORT ?? 5000),
  issuer: process.env.API_ISSUER ?? "http://rti.localhost:8081/realms/rti",
  jwksUri:
    process.env.API_JWKS_URI ??
    "http://keycloak-rti:8080/realms/rti/protocol/openid-connect/certs",
  audience: process.env.API_AUDIENCE ?? "oauth2-api",
  requiredGroup: process.env.API_REQUIRED_GROUP ?? "api-access",
  corsOrigin: process.env.API_CORS_ORIGIN ?? "http://localhost:3000",
};

interface TokenPayload {
  sub?: string;
  iss?: string;
  preferred_username?: string;
  groups?: string[] | string;
}

declare global {
  namespace Express {
    interface User extends TokenPayload {}
  }
}

// jwks-rsa fetches signing keys from the in-network Keycloak URL so validation
// does not depend on the browser-facing issuer hostname resolving here.
const strategyOptions: StrategyOptionsWithoutRequest = {
  jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
  secretOrKeyProvider: jwksRsa.passportJwtSecret({
    jwksUri: config.jwksUri,
    cache: true,
    rateLimit: true,
  }),
  issuer: config.issuer,
  audience: config.audience,
  algorithms: ["RS256"],
};

passport.use(
  new JwtStrategy(
    strategyOptions,
    (payload: TokenPayload, done: VerifiedCallback) => {
      done(null, payload);
    },
  ),
);

function tokenGroups(payload: TokenPayload): string[] {
  const raw = payload.groups;
  const list = Array.isArray(raw) ? raw : typeof raw === "string" ? [raw] : [];
  return list.map((group) => String(group).replace(/^\//, ""));
}

function unauthorized(res: Response, description: string): void {
  res.set(
    "WWW-Authenticate",
    `Bearer realm="oauth2-api", error="invalid_token", error_description="${description}"`,
  );
  res.status(401).json({
    error: "unauthorized",
    message: "Authentication is required.",
  });
}

const authenticate: RequestHandler = (req, res, next) => {
  passport.authenticate(
    "jwt",
    { session: false },
    (err: unknown, user: Express.User | false, info: unknown) => {
      if (err) {
        console.log(`Token verification error: ${(err as Error).message}`);
        unauthorized(res, "The access token could not be verified");
        return;
      }
      if (!user) {
        const reason = info instanceof Error ? info.message : "no bearer token";
        console.log(`Rejected token: ${reason}`);
        unauthorized(res, "A valid bearer access token is required");
        return;
      }
      req.user = user;
      next();
    },
  )(req, res, next);
};

const requireApiAccess = (
  req: Request,
  res: Response,
  next: NextFunction,
): void => {
  if (!tokenGroups(req.user ?? {}).includes(config.requiredGroup)) {
    res.status(403).json({
      error: "forbidden",
      message: "You do not have permission to invoke this API.",
    });
    return;
  }
  next();
};

const app = express();
app.use(cors({ origin: config.corsOrigin }));
app.use(passport.initialize());

app.get("/health", (_req: Request, res: Response) => {
  res.json({ status: "ok" });
});

app.get(
  "/api/data",
  authenticate,
  requireApiAccess,
  (req: Request, res: Response) => {
    const token = req.user ?? {};
    res.json({
      message: "You have successfully invoked the protected API.",
      subject: token.sub,
      username: token.preferred_username,
      issuer: token.iss,
      timestamp: new Date().toISOString(),
    });
  },
);

app.listen(config.port, () => {
  console.log(`OAuth 2.0 protected API listening on port ${config.port}`);
  console.log(`Trusted issuer:    ${config.issuer}`);
  console.log(`Required audience: ${config.audience}`);
  console.log(`Required group:    ${config.requiredGroup}`);
});
