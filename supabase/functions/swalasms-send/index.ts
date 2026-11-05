// Server-side SwalaSMS dispatch. API credentials are Supabase Function secrets only.
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const sha256 = async (value: string) => {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return Response.json({ error: "Method not allowed" }, { status: 405, headers: corsHeaders });

  const authorization = req.headers.get("Authorization") ?? "";
  const token = authorization.replace(/^Bearer\s+/i, "");
  if (!token || token === authorization) return Response.json({ error: "Authentication required" }, { status: 401, headers: corsHeaders });

  const url = Deno.env.get("SUPABASE_URL");
  const anon = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const apiKey = Deno.env.get("SWALASMS_API_KEY");
  const senderId = Deno.env.get("SWALASMS_SENDER_ID");
  if (!url || !anon || !serviceKey) return Response.json({ error: "Supabase server configuration missing" }, { status: 503, headers: corsHeaders });
  if (!apiKey || !senderId) return Response.json({ error: "SwalaSMS is not configured" }, { status: 503, headers: corsHeaders });

  try {
    const userClient = createClient(url, anon, {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: authData, error: authError } = await userClient.auth.getUser(token);
    if (authError || !authData.user) return Response.json({ error: "Invalid session" }, { status: 401, headers: corsHeaders });
    const { data: profile } = await userClient.from("profiles").select("role,is_active").eq("id", authData.user.id).maybeSingle();
    if (!profile || profile.role !== "admin" || profile.is_active === false) {
      return Response.json({ error: "Administrator access required" }, { status: 403, headers: corsHeaders });
    }

    const body = await req.json();
    const idempotencyKey = typeof body.idempotencyKey === "string" ? body.idempotencyKey.trim() : "";
    const phone = typeof body.phone === "string" ? body.phone.replace(/[\s()-]/g, "") : "";
    const message = typeof body.message === "string" ? body.message.trim() : "";
    if (!/^[A-Za-z0-9._:/-]{8,200}$/.test(idempotencyKey) ||
        !/^255[0-9]{9}$/.test(phone) || message.length < 1 || message.length > 1000) {
      return Response.json({ error: "Valid idempotencyKey, Tanzanian phone (255XXXXXXXXX), and message are required" }, { status: 400, headers: corsHeaders });
    }

    const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const recipientHash = await sha256(phone);
    const { data: job, error: insertError } = await admin.from("provider_delivery_jobs")
      .insert({ provider: "swalasms", idempotency_key: idempotencyKey, recipient_hash: recipientHash, created_by: authData.user.id })
      .select("id,status,provider_message_id").single();

    if (insertError) {
      if (insertError.code === "23505") {
        const { data: existing } = await admin.from("provider_delivery_jobs")
          .select("status,provider_message_id").eq("provider", "swalasms").eq("idempotency_key", idempotencyKey).maybeSingle();
        if (existing?.status === "accepted") return Response.json({ accepted: true, duplicate: true, messageId: existing.provider_message_id }, { headers: corsHeaders });
        return Response.json({ error: "This SMS request is already being processed or has an uncertain result. Do not create a new key to retry it." }, { status: 409, headers: corsHeaders });
      }
      throw insertError;
    }

    try {
      const response = await fetch("https://swalasms.com/api/v1/sms/messages", {
        method: "POST",
        headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
        body: JSON.stringify({ sender_id: senderId, recipients: [phone], message }),
        signal: AbortSignal.timeout(20000),
      });
      const raw = await response.text();
      let parsed: Record<string, unknown> = {};
      try { parsed = JSON.parse(raw); } catch { /* provider may return non-JSON error text */ }
      if (!response.ok) {
        await admin.from("provider_delivery_jobs").update({
          status: response.status >= 500 || response.status === 429 ? "unknown" : "failed",
          error_code: `SWALASMS_HTTP_${response.status}`, updated_at: new Date().toISOString(),
        }).eq("id", job.id);
        return Response.json({ error: "SwalaSMS rejected or could not confirm the request", status: response.status }, { status: 502, headers: corsHeaders });
      }
      const messageId = String(parsed.message_id ?? parsed.messageId ?? parsed.id ?? "");
      await admin.from("provider_delivery_jobs").update({
        status: "accepted", provider_message_id: messageId || null, updated_at: new Date().toISOString(),
      }).eq("id", job.id);
      return Response.json({ accepted: true, messageId: messageId || null }, { headers: corsHeaders });
    } catch (_error) {
      await admin.from("provider_delivery_jobs").update({
        status: "unknown", error_code: "SWALASMS_NETWORK_RESULT_UNKNOWN", updated_at: new Date().toISOString(),
      }).eq("id", job.id);
      return Response.json({ error: "SMS result is uncertain. Check the SwalaSMS portal before attempting another send." }, { status: 502, headers: corsHeaders });
    }
  } catch (error) {
    console.error("swalasms-send error", error instanceof Error ? error.message : "unknown");
    return Response.json({ error: "Unable to process SMS request" }, { status: 500, headers: corsHeaders });
  }
});
