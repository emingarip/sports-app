import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SignJWT } from "https://esm.sh/jose@5.9.6";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function isAllowedGamificationUrl(url: string): boolean {
  return url.startsWith('https://') ||
    url.startsWith('http://localhost') ||
    url.startsWith('http://127.0.0.1');
}

async function buildGamificationAuthHeader(secretOrToken: string): Promise<string> {
  const trimmed = secretOrToken.trim();
  if (!trimmed) {
    throw new Error('GAMIFICATION_API_SECRET is not configured.');
  }

  if (trimmed.split('.').length === 3) {
    return `Bearer ${trimmed}`;
  }

  const secretKey = new TextEncoder().encode(trimmed);
  const token = await new SignJWT({
    email: 'supabase-service',
    permissions: ['read', 'write', 'delete', 'admin'],
    role: 'admin',
    sub: 'supabase_service',
    type: 'access',
    user_id: 'supabase_service',
    username: 'supabase-service',
  })
    .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
    .setIssuedAt()
    .setIssuer('muscle-gamification')
    .setExpirationTime('30m')
    .sign(secretKey);

  return `Bearer ${token}`;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: req.headers.get('Authorization')! } } }
    );

    const {
      data: { user },
      error: userError,
    } = await supabaseClient.auth.getUser();

    if (userError || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 401,
      });
    }

    const gamificationApiUrl = (Deno.env.get("GAMIFICATION_API_URL") ?? '').trim();
    const gamificationApiSecret = (Deno.env.get("GAMIFICATION_API_SECRET") ?? '').trim();

    if (!gamificationApiUrl || !isAllowedGamificationUrl(gamificationApiUrl)) {
      return new Response(JSON.stringify({ error: 'GAMIFICATION_API_URL must be configured with HTTPS in production.' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500,
      });
    }

    const gamificationAuthHeader = await buildGamificationAuthHeader(gamificationApiSecret);

    const reqData = await req.json();
    const action = reqData.action;
    const payload = reqData.payload || {};

    const backendHeaders: Record<string, string> = {
      'Content-Type': 'application/json',
      'Authorization': gamificationAuthHeader,
    };

    let response;

    if (action === 'get_badges') {
      response = await fetch(`${gamificationApiUrl}/badges`, {
        method: 'GET',
        headers: backendHeaders,
      });
    } else if (action === 'get_user_badges') {
      const uid = payload.user_id || user.id;
      response = await fetch(`${gamificationApiUrl}/users/${uid}`, {
        method: 'GET',
        headers: backendHeaders,
      });
    } else if (action === 'send_event') {
      const eventPayload = {
        user_id: user.id,
        event_type: payload.event_type,
        metadata: payload.metadata || {},
      };

      response = await fetch(`${gamificationApiUrl}/events`, {
        method: 'POST',
        headers: backendHeaders,
        body: JSON.stringify(eventPayload),
      });
    } else {
      return new Response(JSON.stringify({ error: 'Invalid action' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      });
    }

    let responseData;
    const responseText = await response.text();
    try {
      responseData = JSON.parse(responseText);
    } catch {
      responseData = { message: responseText };
    }

    return new Response(JSON.stringify(responseData), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: response.status,
    });
  } catch (error: any) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400,
    });
  }
});
