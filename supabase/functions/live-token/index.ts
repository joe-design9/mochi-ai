// Nova — `live-token` Edge Function (Supabase, Deno).
//
// Mints a short-lived Gemini Live ephemeral token for the Nova app's
// phone-call mode (v3.0.0+). The app holds NO API key in the normal
// build, so it posts { install_id } here; after the same activation
// check as the `chat` function (invite_codes.used_by_install =
// install_id, or the owner's OWNER_INSTALL_IDS allowlist), this
// function creates an auth token with the server-side secret
// GEMINI_API_KEY via the Gemini v1alpha authTokens API and returns
// { token, expire_time }. The app then connects to
// GenerativeService.BidiGenerateContentConstrained with
// ?access_token=<token> — the secret itself never leaves the server.
//
// Token policy: single use (uses = 1), new sessions may start for
// 2 minutes, the token itself expires after 30 minutes — one token
// covers exactly one call setup, including the controller's one
// silent reconnect window.
//
// Required secrets / env: GEMINI_API_KEY (function secret),
// OWNER_INSTALL_IDS (optional allowlist). SUPABASE_URL and
// SUPABASE_SERVICE_ROLE_KEY are injected by the Edge runtime.
//
// Deploy: `supabase functions deploy live-token`.

import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function fail(status: number, error: string, message: string): Response {
  return json({ error, message }, status);
}

/// Same activation rule as the `chat` function.
async function isActivated(installId: string): Promise<boolean> {
  const owners = (Deno.env.get("OWNER_INSTALL_IDS") ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter((value) => value.length > 0);
  if (owners.includes(installId)) return true;

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );
  const { data, error } = await supabase
    .from("invite_codes")
    .select("code")
    .eq("used_by_install", installId)
    .limit(1);
  if (error) {
    console.error("invite_codes lookup failed:", error.message);
    return false;
  }
  return (data?.length ?? 0) > 0;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return fail(405, "method_not_allowed", "Nur POST ist erlaubt.");
  }

  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) {
    return fail(
      503,
      "server_not_configured",
      "Der Nova-Server ist noch nicht fertig eingerichtet (GEMINI_API_KEY fehlt).",
    );
  }

  let payload: { install_id?: unknown };
  try {
    payload = await req.json();
  } catch {
    return fail(400, "bad_request", "Ungültiges JSON.");
  }
  const installId = typeof payload.install_id === "string"
    ? payload.install_id.trim()
    : "";
  if (!installId) {
    return fail(400, "bad_request", "install_id fehlt.");
  }
  if (!(await isActivated(installId))) {
    return fail(
      403,
      "not_activated",
      "Diese Installation ist nicht aktiviert.",
    );
  }

  const now = Date.now();
  const expireTime = new Date(now + 30 * 60 * 1000).toISOString();
  const newSessionExpireTime = new Date(now + 2 * 60 * 1000).toISOString();

  // CreateAuthToken takes the AuthToken resource as its body. The
  // REST transcoding accepts the resource fields at the top level;
  // should Google reject that shape with a 400, retry once with the
  // { authToken: … } wrapper so the function works either way.
  const authToken = { uses: 1, expireTime, newSessionExpireTime };
  const createToken = (body: unknown) =>
    fetch("https://generativelanguage.googleapis.com/v1alpha/authTokens", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": apiKey,
      },
      body: JSON.stringify(body),
    });

  let tokenResponse: Response;
  try {
    tokenResponse = await createToken(authToken);
    if (tokenResponse.status === 400) {
      tokenResponse = await createToken({ authToken });
    }
  } catch (error) {
    console.error("authTokens fetch failed:", error);
    return fail(
      502,
      "upstream_unreachable",
      "Google ist gerade nicht erreichbar. Versuch es gleich nochmal.",
    );
  }

  const tokenData = await tokenResponse.json().catch(() => null) as
    | Record<string, unknown>
    | null;
  const token = typeof tokenData?.name === "string" ? tokenData.name : "";
  if (!tokenResponse.ok || !token) {
    const upstream = (tokenData?.error as { message?: string } | undefined)
      ?.message;
    console.error("authTokens error:", tokenResponse.status, upstream ?? "");
    return fail(
      502,
      "upstream_error",
      upstream
        ? `Google meldet: ${upstream}`
        : `Google meldet einen Fehler (HTTP ${tokenResponse.status}).`,
    );
  }

  return json({ token, expire_time: expireTime });
});
