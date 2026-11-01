// Nova — `chat` Edge Function (Supabase, Deno).
//
// Text chat for the Nova app (v3.0.0+). The normal app build ships
// WITHOUT any user API key: it posts { install_id, system_prompt,
// messages } here, this function verifies the install was activated
// with an invite code (invite_codes.used_by_install = install_id),
// then calls Gemini with the server-side secret GEMINI_API_KEY and
// returns { reply }.
//
// Required secrets / env (set by the project owner, never by the app):
//   GEMINI_API_KEY        — Google AI Studio key (function secret)
//   OWNER_INSTALL_IDS     — optional, comma-separated install IDs that
//                           are always allowed (the owner's own
//                           grandfathered installs, which predate the
//                           invite system and never redeemed a code)
//   GEMINI_MODEL          — optional model override
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected by the
// Supabase Edge runtime automatically. The service role is needed
// because invite_codes has RLS with no client policies — the three
// invite RPCs stay the only anon surface; this function is the only
// server-side reader added for the proxy.
//
// Deploy: `supabase functions deploy chat` (or the dashboard editor).
// The app calls it with the project's anon key as bearer token.

import { createClient } from "jsr:@supabase/supabase-js@2";

const MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-3.8-flash"; // the app's current default model
const GEMINI_BASE = "https://generativelanguage.googleapis.com/v1beta";

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

/// Activation check shared with the live-token function: an install
/// counts as activated when an invite code was redeemed by exactly
/// this install id, or when the owner listed it in OWNER_INSTALL_IDS.
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

interface ChatTurn {
  role: string;
  text: string;
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
    // Clean, honest error until the owner sets the secret — the app
    // shows this message verbatim in the chat.
    return fail(
      503,
      "server_not_configured",
      "Der Nova-Server ist noch nicht fertig eingerichtet (GEMINI_API_KEY fehlt).",
    );
  }

  let payload: {
    install_id?: unknown;
    system_prompt?: unknown;
    messages?: unknown;
  };
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

  const rawTurns = Array.isArray(payload.messages) ? payload.messages : [];
  const turns: ChatTurn[] = rawTurns
    .filter((turn): turn is ChatTurn =>
      typeof turn === "object" && turn !== null &&
      typeof (turn as ChatTurn).text === "string" &&
      ((turn as ChatTurn).role === "user" || (turn as ChatTurn).role === "model")
    )
    .slice(-12);
  while (turns.length > 0 && turns[0].role !== "user") turns.shift();
  if (turns.length === 0) {
    return fail(400, "bad_request", "Keine Nachrichten übermittelt.");
  }

  const systemPrompt = typeof payload.system_prompt === "string"
    ? payload.system_prompt
    : "";
  const body: Record<string, unknown> = {
    contents: turns.map((turn) => ({
      role: turn.role,
      parts: [{ text: turn.text }],
    })),
    generationConfig: {
      maxOutputTokens: 1024,
      thinkingConfig: { thinkingLevel: "low" },
    },
  };
  if (systemPrompt) {
    body.systemInstruction = { parts: [{ text: systemPrompt }] };
  }

  let geminiResponse: Response;
  try {
    geminiResponse = await fetch(
      `${GEMINI_BASE}/models/${MODEL}:generateContent`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-goog-api-key": apiKey,
        },
        body: JSON.stringify(body),
      },
    );
  } catch (error) {
    console.error("Gemini fetch failed:", error);
    return fail(
      502,
      "upstream_unreachable",
      "Google ist gerade nicht erreichbar. Versuch es gleich nochmal.",
    );
  }

  const geminiData = await geminiResponse.json().catch(() => null) as
    | Record<string, unknown>
    | null;
  if (!geminiResponse.ok || !geminiData) {
    const upstream = (geminiData?.error as { message?: string } | undefined)
      ?.message;
    console.error("Gemini error:", geminiResponse.status, upstream ?? "");
    return fail(
      502,
      "upstream_error",
      upstream
        ? `Google meldet: ${upstream}`
        : `Google meldet einen Fehler (HTTP ${geminiResponse.status}).`,
    );
  }

  const candidates = geminiData.candidates as
    | Array<{ content?: { parts?: Array<{ text?: string }> } }>
    | undefined;
  const reply = (candidates?.[0]?.content?.parts ?? [])
    .map((part) => part.text ?? "")
    .join("")
    .trim();
  if (!reply) {
    return fail(
      502,
      "empty_reply",
      "Google hat eine leere Antwort geschickt — versuch es einfach nochmal.",
    );
  }
  return json({ reply });
});
