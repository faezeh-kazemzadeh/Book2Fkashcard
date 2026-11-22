/**
 * Book2Flashcards AI proxy (Cloudflare Worker reference implementation).
 *
 * Why: the iOS app must never ship provider API keys. In production the app
 * calls this proxy with a short-lived user token; the proxy holds the OpenAI /
 * Azure key as a Worker secret, enforces quotas per user, and forwards an
 * allow-listed subset of the Chat Completions API.
 *
 * Secrets (set with `wrangler secret put`): OPENAI_API_KEY, TOKEN_SIGNING_KEY
 * KV namespace binding: QUOTA
 */

export interface Env {
  OPENAI_API_KEY: string;
  TOKEN_SIGNING_KEY: string; // HMAC key used by your auth service to sign user tokens
  QUOTA: KVNamespace;
  DAILY_REQUEST_LIMIT?: string;
}

const ALLOWED_MODELS = new Set(["gpt-5-mini", "gpt-5", "gpt-4.1-mini"]);
const MAX_BODY_BYTES = 2_000_000;

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (request.method !== "POST" || url.pathname !== "/v1/chat/completions") {
      return json({ error: { message: "Not found" } }, 404);
    }

    const userID = await verifyToken(request.headers.get("Authorization"), env.TOKEN_SIGNING_KEY);
    if (!userID) return json({ error: { message: "Invalid or expired token" } }, 401);

    const length = Number(request.headers.get("Content-Length") ?? "0");
    if (length > MAX_BODY_BYTES) return json({ error: { message: "Request too large" } }, 413);

    // Daily per-user quota.
    const day = new Date().toISOString().slice(0, 10);
    const quotaKey = `q:${userID}:${day}`;
    const used = Number((await env.QUOTA.get(quotaKey)) ?? "0");
    const limit = Number(env.DAILY_REQUEST_LIMIT ?? "300");
    if (used >= limit) {
      return json({ error: { message: "Daily limit reached" } }, 429, { "Retry-After": "3600" });
    }
    await env.QUOTA.put(quotaKey, String(used + 1), { expirationTtl: 60 * 60 * 26 });

    const body = (await request.json()) as Record<string, unknown>;
    const model = typeof body.model === "string" && ALLOWED_MODELS.has(body.model) ? body.model : "gpt-5-mini";
    // Forward only known fields; never let clients choose tools or other endpoints.
    const forwarded = {
      model,
      messages: body.messages,
      response_format: body.response_format,
      max_completion_tokens: Math.min(Number(body.max_completion_tokens ?? 4000), 8000),
      user: userID,
    };

    const upstream = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${env.OPENAI_API_KEY}` },
      body: JSON.stringify(forwarded),
    });
    const headers: Record<string, string> = { "Content-Type": "application/json" };
    const retryAfter = upstream.headers.get("Retry-After");
    if (retryAfter) headers["Retry-After"] = retryAfter;
    return new Response(upstream.body, { status: upstream.status, headers });
  },
};

/** Token format: base64url(userID.expiryEpochSeconds).base64url(HMAC-SHA256). */
async function verifyToken(header: string | null, signingKey: string): Promise<string | null> {
  if (!header?.startsWith("Bearer ")) return null;
  const [payloadB64, signatureB64] = header.slice(7).split(".");
  if (!payloadB64 || !signatureB64) return null;
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(signingKey), { name: "HMAC", hash: "SHA-256" }, false, ["verify"]);
  const valid = await crypto.subtle.verify("HMAC", key, base64UrlDecode(signatureB64), new TextEncoder().encode(payloadB64));
  if (!valid) return null;
  const [userID, expiry] = new TextDecoder().decode(base64UrlDecode(payloadB64)).split(".");
  if (!userID || Number(expiry) * 1000 < Date.now()) return null;
  return userID;
}

function base64UrlDecode(input: string): Uint8Array {
  const base64 = input.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(input.length / 4) * 4, "=");
  return Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
}

function json(data: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json", ...headers } });
}
