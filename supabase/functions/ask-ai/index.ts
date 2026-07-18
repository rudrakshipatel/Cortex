// Edge Function: "Ask AI about this case" — a doubt-clearing tutor for Pro
// players. The app sends the finished case's context + the running chat; this
// function calls Google Gemini with the server-side key and returns the
// assistant's reply. The key NEVER ships in the app.
//
// Required secret (set with `supabase secrets set`):
//   GEMINI_API_KEY  – your Google AI Studio key
// Optional override:
//   GEMINI_MODEL    – default "gemini-2.0-flash"
// (SUPABASE_URL and SUPABASE_ANON_KEY are injected automatically.)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const GEMINI_MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-2.0-flash";
const MAX_TOKENS = 800;

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

/// Turn a raw provider error into a short, user-facing message (the detail is
/// logged server-side, never shown in the chat).
function friendlyError(provider: string, status: number, detail: string): string {
  console.error(`${provider} error`, status, detail);
  const d = detail.toLowerCase();
  if (status === 429 || d.includes("resource_exhausted") || d.includes("quota") || d.includes("rate limit")) {
    return `The AI tutor has hit its usage limit right now. Please try again in a minute.`;
  }
  if (status === 401 || status === 403) {
    return `The AI tutor isn't available right now. Please try again later.`;
  }
  return `The AI tutor couldn't answer right now. Please try again.`;
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
  if (!userData?.user) return json({ error: "Please sign in to use the AI tutor." }, 401);

  let payload: { caseContext?: string; messages?: ChatMessage[] };
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Invalid request body." }, 400);
  }

  const history = (payload.messages ?? [])
    .filter((m) => (m.role === "user" || m.role === "assistant") && typeof m.content === "string")
    .slice(-20); // cap context to the last 20 turns
  if (history.length === 0) return json({ error: "No question provided." }, 400);

  const system = systemPrompt(payload.caseContext ?? "(no case details provided)");

  try {
    const reply = await askGemini(system, history);
    if (!reply) return json({ error: "The AI returned an empty response. Try again." }, 502);
    return json({ reply });
  } catch (e) {
    console.error(e);
    return json({ error: (e as Error).message ?? "The AI request failed." }, 502);
  }
});
