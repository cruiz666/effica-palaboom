import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const WEBHOOK_AUTHORIZATION = Deno.env.get("REVENUECAT_WEBHOOK_AUTHORIZATION") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function timingSafeEqual(a: string, b: string): boolean {
  const encoder = new TextEncoder();
  const bytesA = encoder.encode(a);
  const bytesB = encoder.encode(b);
  if (bytesA.length !== bytesB.length) {
    // Still do a comparison of equal-length dummy data so the function
    // takes similar time whether lengths match or not.
    let dummy = 0;
    for (let i = 0; i < bytesA.length; i++) dummy |= bytesA[i];
    return false;
  }
  let diff = 0;
  for (let i = 0; i < bytesA.length; i++) {
    diff |= bytesA[i] ^ bytesB[i];
  }
  return diff === 0;
}

// Eventos de RevenueCat que cambian el estado de la suscripción. Cualquier
// otro tipo de evento (ej. BILLING_ISSUE, PRODUCT_CHANGE) se acepta con 200
// pero se ignora — no hay nada que este esquema simple necesite reflejar
// para esos casos.
function statusForEventType(eventType: string): "active" | "cancelled" | "inactive" | null {
  switch (eventType) {
    case "INITIAL_PURCHASE":
    case "RENEWAL":
    case "UNCANCELLATION":
      return "active";
    case "CANCELLATION":
      return "cancelled";
    case "EXPIRATION":
      return "inactive";
    default:
      return null;
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  if (
    WEBHOOK_AUTHORIZATION === "" ||
    !timingSafeEqual(req.headers.get("Authorization") ?? "", WEBHOOK_AUTHORIZATION)
  ) {
    return new Response("Unauthorized", { status: 401 });
  }

  let body: { event?: { type?: string; app_user_id?: string; product_id?: string; expiration_at_ms?: number } };
  try {
    body = await req.json();
  } catch {
    return new Response("Malformed JSON", { status: 400 });
  }

  const event = body.event;
  if (!event || !event.app_user_id || !event.type) {
    return new Response("Malformed payload", { status: 400 });
  }

  if (!UUID_PATTERN.test(event.app_user_id)) {
    return new Response("Invalid app_user_id", { status: 400 });
  }

  const status = statusForEventType(event.type);
  if (status === null) {
    return new Response(JSON.stringify({ ok: true, ignored: true }), { status: 200 });
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const { error } = await supabase.from("user_subscriptions").upsert({
    user_id: event.app_user_id,
    status,
    product_id: event.product_id ?? null,
    expires_at: event.expiration_at_ms ? new Date(event.expiration_at_ms).toISOString() : null,
    updated_at: new Date().toISOString(),
  });

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }

  return new Response(JSON.stringify({ ok: true }), { status: 200 });
});
