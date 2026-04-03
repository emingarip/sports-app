import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

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

    const GAMIFICATION_API_URL = Deno.env.get("GAMIFICATION_API_URL") || "http://gamification.boskale.com/api/v1";
    const GAMIFICATION_API_SECRET = Deno.env.get("GAMIFICATION_API_SECRET");

    const reqData = await req.json();
    const action = reqData.action;
    const payload = reqData.payload || {};
    
    const backendHeaders: Record<string, string> = {
      'Content-Type': 'application/json',
    };
    if (GAMIFICATION_API_SECRET) {
      backendHeaders['Authorization'] = `Bearer ${GAMIFICATION_API_SECRET}`;
    }

    let response;

    if (action === 'get_badges') {
      response = await fetch(`${GAMIFICATION_API_URL}/badges`, {
        method: 'GET',
        headers: backendHeaders,
      });
    } else if (action === 'get_user_badges') {
      const uid = payload.user_id || user.id;
      response = await fetch(`${GAMIFICATION_API_URL}/users/${uid}`, {
        method: 'GET',
        headers: backendHeaders,
      });
    } else if (action === 'send_event') {
      const eventPayload = {
        user_id: user.id, // Strictly enforce authenticated user ID
        event_type: payload.event_type,
        metadata: payload.metadata || {},
      };
      
      response = await fetch(`${GAMIFICATION_API_URL}/events`, {
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
