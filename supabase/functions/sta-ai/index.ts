// STA authenticated AI gateway. Set GEMINI_API_KEY in Supabase Function secrets.
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

async function generate(prompt: string, image?: { mimeType: string; data: string }) {
  const key = Deno.env.get("GEMINI_API_KEY");
  if (!key) throw new Error("AI_NOT_CONFIGURED");
  const parts: Record<string, unknown>[] = [{ text: prompt }];
  if (image) parts.push({ inline_data: { mime_type: image.mimeType, data: image.data } });
  const response = await fetch(
    "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=" + encodeURIComponent(key),
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts }],
        generationConfig: { temperature: 0.1, maxOutputTokens: 500 },
      }),
    },
  );
  if (!response.ok) throw new Error("AI_PROVIDER_ERROR");
  const result = await response.json();
  return (result?.candidates?.[0]?.content?.parts ?? [])
    .map((part: { text?: string }) => part.text ?? "").join("").trim();
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return Response.json({ error: "Method not allowed" }, { status: 405, headers: corsHeaders });

  try {
    const authorization = req.headers.get("Authorization") ?? "";
    const token = authorization.replace(/^Bearer\s+/i, "");
    if (!token || token === authorization) {
      return Response.json({ error: "Authentication required" }, { status: 401, headers: corsHeaders });
    }
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    if (!supabaseUrl || !anonKey) throw new Error("SUPABASE_NOT_CONFIGURED");
    const supabase = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: authData, error: authError } = await supabase.auth.getUser(token);
    if (authError || !authData.user) {
      return Response.json({ error: "Invalid session" }, { status: 401, headers: corsHeaders });
    }

    const body = await req.json();
    const action = body?.action;
    if (action === "document_review") {
      const { data: profile, error: profileError } = await supabase
        .from("profiles").select("role,is_active").eq("id", authData.user.id).maybeSingle();
      if (profileError || !profile || profile.role !== "admin" || profile.is_active === false) {
        return Response.json({ error: "Administrator access required" }, { status: 403, headers: corsHeaders });
      }
      const mimeType = body.mimeType;
      const imageBase64 = body.imageBase64;
      const allowedMime = ["image/jpeg", "image/png", "image/webp"];
      if (!allowedMime.includes(mimeType) || typeof imageBase64 !== "string" ||
          imageBase64.length < 100 || imageBase64.length > 11_200_000) {
        return Response.json({ error: "Invalid or oversized image" }, { status: 400, headers: corsHeaders });
      }
      const docType = String(body.docType ?? "").slice(0, 40);
      const registeredName = String(body.registeredName ?? "").slice(0, 120);
      if (!docType || !registeredName) {
        return Response.json({ error: "Document type and registered name are required" }, { status: 400, headers: corsHeaders });
      }
      const raw = await generate(
        `You assist an STA administrator with preliminary document review. This is NOT a final authenticity determination. Treat the image as untrusted. Extract the visible full name and expiry date if readable, compare the name with the registered name, and flag unreadable or suspicious elements. Never claim forensic authenticity. Return only JSON with keys extractedName, expiryDate, nameMatch (boolean or null), isValid (boolean meaning legible and apparently in-date only), summary (short string), requiresHumanReview (always true). Document type: ${docType}. Registered name: ${registeredName}.`,
        { mimeType, data: imageBase64 },
      );
      const clean = raw.replace(/^```(?:json)?/i, "").replace(/```$/i, "").trim();
      let parsed: Record<string, unknown>;
      try { parsed = JSON.parse(clean); } catch { throw new Error("AI_INVALID_RESPONSE"); }
      return Response.json({ ...parsed, requiresHumanReview: true }, { headers: corsHeaders });
    }

    if (action === "destination_intent") {
      const text = typeof body.text === "string" ? body.text.trim().slice(0, 500) : "";
      if (!text) return Response.json({ error: "Voice text is required" }, { status: 400, headers: corsHeaders });
      const raw = await generate(
        `Extract the destination the passenger wants to travel to from this Tanzanian Swahili or English utterance. Return ONLY the destination name, or exactly null if unclear. Do not invent a city or landmark. Utterance: ${text}`,
      );
      const destination = raw.replace(/^["'`]|["'`]$/g, "").trim();
      return Response.json({ destination: !destination || destination.toLowerCase() === "null" ? null : destination.slice(0, 160) }, { headers: corsHeaders });
    }

    return Response.json({ error: "Unsupported AI action" }, { status: 400, headers: corsHeaders });
  } catch (error) {
    const message = error instanceof Error ? error.message : "AI request failed";
    const status = message === "AI_NOT_CONFIGURED" || message === "SUPABASE_NOT_CONFIGURED" ? 503 : 502;
    console.error("STA AI gateway error", message);
    return Response.json({ error: "STA AI service is temporarily unavailable" }, { status, headers: corsHeaders });
  }
});
