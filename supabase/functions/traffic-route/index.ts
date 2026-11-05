// Traffic-aware Google Routes adapter. Configure GOOGLE_ROUTES_API_KEY in Supabase Function secrets.
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function coordinate(value: unknown, min: number, max: number): number | null {
  if (typeof value !== "number" || !Number.isFinite(value) || value < min || value > max) return null;
  return value;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") {
    return Response.json({ error: "Method not allowed" }, { status: 405, headers: corsHeaders });
  }
  try {
    const body = await req.json();
    if (body?.action === "health") {
      return Response.json(
        { configured: Boolean(Deno.env.get("GOOGLE_ROUTES_API_KEY")) },
        { headers: corsHeaders },
      );
    }
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const authorization = req.headers.get("Authorization") ?? "";
    if (!supabaseUrl || !anonKey || !authorization) {
      return Response.json({ error: "Routing service authentication is not configured" }, { status: 503, headers: corsHeaders });
    }
    const supabase = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: withinQuota, error: quotaError } = await supabase.rpc("sta_consume_route_quota");
    if (quotaError || withinQuota !== true) {
      return Response.json({ error: "Traffic routing request limit reached. Try again shortly." }, { status: 429, headers: corsHeaders });
    }
    const apiKey = Deno.env.get("GOOGLE_ROUTES_API_KEY");
    if (!apiKey) {
      return Response.json({ error: "Traffic-aware routing is not configured" }, { status: 503, headers: corsHeaders });
    }
    const origin = body?.origin ?? {};
    const destination = body?.destination ?? {};
    const originLat = coordinate(origin.latitude, -90, 90);
    const originLng = coordinate(origin.longitude, -180, 180);
    const destinationLat = coordinate(destination.latitude, -90, 90);
    const destinationLng = coordinate(destination.longitude, -180, 180);
    if (originLat === null || originLng === null || destinationLat === null || destinationLng === null) {
      return Response.json({ error: "Valid origin and destination coordinates are required" }, { status: 400, headers: corsHeaders });
    }

    const response = await fetch("https://routes.googleapis.com/directions/v2:computeRoutes", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": apiKey,
        "X-Goog-FieldMask": [
          "routes.distanceMeters",
          "routes.duration",
          "routes.staticDuration",
          "routes.polyline.geoJsonLinestring.coordinates",
          "routes.legs.steps.distanceMeters",
          "routes.legs.steps.startLocation.latLng",
          "routes.legs.steps.navigationInstruction.instructions",
        ].join(","),
      },
      body: JSON.stringify({
        origin: { location: { latLng: { latitude: originLat, longitude: originLng } } },
        destination: { location: { latLng: { latitude: destinationLat, longitude: destinationLng } } },
        travelMode: "DRIVE",
        routingPreference: "TRAFFIC_AWARE",
        computeAlternativeRoutes: true,
        polylineEncoding: "GEO_JSON_LINESTRING",
        polylineQuality: "HIGH_QUALITY",
        languageCode: "sw",
      }),
    });
    if (!response.ok) {
      const detail = await response.text();
      console.error("Google Routes request failed", response.status, detail.slice(0, 500));
      return Response.json({ error: "Traffic routing provider rejected the request" }, { status: 502, headers: corsHeaders });
    }
    const result = await response.json();
    const routes = Array.isArray(result?.routes) ? result.routes.slice(0, 3) : [];
    if (!routes.length) {
      return Response.json({ error: "No drivable route was found" }, { status: 404, headers: corsHeaders });
    }

    const normalized = routes.map((route: Record<string, any>) => ({
      distanceMeters: route.distanceMeters,
      duration: route.duration,
      staticDuration: route.staticDuration,
      polyline: route.polyline,
      legs: (route.legs ?? []).map((leg: Record<string, any>) => ({
        steps: (leg.steps ?? []).map((step: Record<string, any>) => ({
          distanceMeters: step.distanceMeters,
          startLocation: step.startLocation,
          navigationInstruction: step.navigationInstruction,
        })),
      })),
    }));
    return Response.json({ trafficAware: true, routes: normalized }, { headers: corsHeaders });
  } catch (error) {
    console.error("Traffic route error", error instanceof Error ? error.message : "unknown");
    return Response.json({ error: "Traffic-aware routing is temporarily unavailable" }, { status: 502, headers: corsHeaders });
  }
});
