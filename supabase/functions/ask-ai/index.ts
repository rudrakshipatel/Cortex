// Edge Function: "Ask AI about this case" — a doubt-clearing tutor for Pro
// players. The app sends the finished case's context + the running chat; this
// function calls OpenAI (ChatGPT) or Google Gemini with the server-side key and
// returns the assistant's reply. Keys NEVER ship in the app.
//
// Capped at DAILY_AI_LIMIT questions per signed-in user per UTC day (see
// ai_daily_limit.sql for the increment_ai_usage RPC this calls) — checked
// BEFORE the paid provider call, so an over-limit request never costs money.
//
// Required secrets (set with `supabase secrets set`):
//   OPENAI_API_KEY  – your OpenAI key (sk-...)          [needed for provider "openai"]
//   GEMINI_API_KEY  – your Google AI Studio key         [needed for provider "gemini"]
// Optional overrides:
//   OPENAI_MODEL    – default "gpt-4o-mini"
//   GEMINI_MODEL    – default "gemini-2.0-flash"
// (SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are injected
// automatically — no extra secrets needed.)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const OPENAI_MODEL = Deno.env.get("OPENAI_MODEL") ?? "gpt-4o-mini";
const GEMINI_MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-2.0-flash";
const MAX_TOKENS = 800;
const DAILY_AI_LIMIT = 25;

interface ChatMessage { role: "user" | "assistant"; content: string }

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

/// System prompt that scopes the tutor to the case the player just finished.
function systemPrompt(caseContext: string): string {
  return [
    "You are a friendly clinical-reasoning tutor inside a medical training game called Cortex.",
    "A trainee has just finished the case below and wants to clear their doubts.",
    "Explain clearly and concisely, teach the reasoning, and stay focused on THIS case unless they ask to generalise.",
    "Use short paragraphs or bullet points. Avoid overly long answers.",
    "This is for education only — it is NOT medical advice for a real patient. If asked for real-world diagnosis or treatment decisions, remind them to consult a qualified clinician.",
    "",
    "=== CASE THE TRAINEE JUST COMPLETED ===",
    caseContext,
  ].join("\n");
}

async function askOpenAI(system: string, history: ChatMessage[]): Promise<string> {
  const key = Deno.env.get("OPENAI_API_KEY");
  if (!key) throw new Error("OpenAI is not configured on the server.");
  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: { "Authorization": `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: OPENAI_MODEL,
      temperature: 0.3,
      max_tokens: MAX_TOKENS,
      messages: [{ role: "system", content: system }, ...history],
    }),
  });
  if (!res.ok) throw new Error(friendlyError("ChatGPT", res.status, await res.text()));
  const data = await res.json();
  return data.choices?.[0]?.message?.content?.trim() ?? "";
}

/// Turn a raw provider error into a short, user-facing message (the detail is
/// logged server-side, never shown in the chat).
function friendlyError(provider: string, status: number, detail: string): string {
  console.error(`${provider} error`, status, detail);
  const other = provider === "Gemini" ? "ChatGPT" : "Gemini";
  const d = detail.toLowerCase();
  if (status === 429 || d.includes("resource_exhausted") || d.includes("quota") || d.includes("rate limit")) {
    return `${provider} has hit its usage limit right now. Please try again in a minute, or switch to ${other}.`;
  }
  if (status === 401 || status === 403) {
    return `${provider} isn't available right now. Please switch to ${other}.`;
  }
  return `${provider} couldn't answer right now. Please try again, or switch to ${other}.`;
}

async function askGemini(system: string, history: ChatMessage[]): Promise<string> {
  const key = Deno.env.get("GEMINI_API_KEY");
  if (!key) throw new Error("Gemini is not configured on the server.");
  const contents = history.map((m) => ({
    role: m.role === "assistant" ? "model" : "user",
    parts: [{ text: m.content }],
  }));
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${key}`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      system_instruction: { parts: [{ text: system }] },
      contents,
      generationConfig: { temperature: 0.3, maxOutputTokens: MAX_TOKENS },
    }),
  });
  if (!res.ok) throw new Error(friendlyError("Gemini", res.status, await res.text()));
  const data = await res.json();
  return (data.candidates?.[0]?.content?.parts ?? [])
    .map((p: { text?: string }) => p.text ?? "").join("").trim();
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  // Require a signed-in Supabase user (the app sends the player's JWT).
  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
  );
  const { data: userData } = await supabase.auth.getUser(token);
  const uid = userData?.user?.id;
  if (!uid) return json({ error: "Please sign in to use the AI tutor." }, 401);

  // Bump today's usage count first (service-role, bypasses RLS) — if that
  // pushes them over the daily cap, stop before spending anything on a
  // provider call.
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { data: usedToday, error: usageErr } = await admin.rpc("increment_ai_usage", { p_uid: uid });
  if (usageErr) {
    console.error("increment_ai_usage failed", usageErr);
    return json({ error: "Couldn't reach the AI tutor. Please try again." }, 500);
  }
  if ((usedToday ?? 0) > DAILY_AI_LIMIT) {
    return json({ error: `You've reached today's limit of ${DAILY_AI_LIMIT} AI questions. It resets at midnight UTC.` }, 429);
  }

  let payload: { provider?: string; caseContext?: string; messages?: ChatMessage[] };
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Invalid request body." }, 400);
  }

  const provider = (payload.provider ?? "openai").toLowerCase();
  const history = (payload.messages ?? [])
    .filter((m) => (m.role === "user" || m.role === "assistant") && typeof m.content === "string")
    .slice(-20); // cap context to the last 20 turns
  if (history.length === 0) return json({ error: "No question provided." }, 400);

  const system = systemPrompt(payload.caseContext ?? "(no case details provided)");

  try {
    const reply = provider === "gemini"
      ? await askGemini(system, history)
      : await askOpenAI(system, history);
    if (!reply) return json({ error: "The AI returned an empty response. Try again." }, 502);
    return json({ reply });
  } catch (e) {
    console.error(e);
    return json({ error: (e as Error).message ?? "The AI request failed." }, 502);
  }
});
