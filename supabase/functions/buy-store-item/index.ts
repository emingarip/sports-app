import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    
    if (!supabaseUrl || !supabaseKey) {
      throw new Error("Supabase credentials not found in env");
    }

    // Initialize Supabase Admin client
    const supabaseAdmin = createClient(supabaseUrl, supabaseKey);

    // Get Auth token from the request
    const authHeader = req.headers.get('Authorization')!;
    if (!authHeader) {
        return new Response(JSON.stringify({ error: "Missing Authorization header" }), { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // Verify token and get user using the service-role client.
    // This avoids gateway/JWT edge cases while still validating the caller.
    const jwt = authHeader.replace(/^Bearer\s+/i, '').trim();
    const { data: { user }, error: userError } = await supabaseAdmin.auth.getUser(jwt);
    
    if (userError || !user) {
        return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const userId = user.id;

    // Parse body
    const bodyText = await req.text();
    let body;
    try {
        body = JSON.parse(bodyText);
    } catch {
        return new Response(JSON.stringify({ error: "Invalid JSON" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // Usually invoked as _supabase.functions.invoke('...', body: { p_product_code: ... })
    // Tolerate both `p_product_code` or `product_code`
    const productCode = body.p_product_code || body.product_code;
    const requestId = body.p_request_id || body.request_id;
    
    if (!productCode) {
        return new Response(JSON.stringify({ error: "Missing product_code" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    if (!requestId || `${requestId}`.trim() === '') {
        return new Response(JSON.stringify({ error: "Missing request_id" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const { data: purchaseResult, error: purchaseError } = await supabaseAdmin.rpc(
      'buy_store_item_server',
      {
        p_user_id: userId,
        p_product_code: productCode,
        p_request_id: requestId,
      },
    );

    if (purchaseError) {
      console.error("buy_store_item_server error:", purchaseError);
      const message = purchaseError.message ?? "Store purchase failed";
      let status = 400;

      if (
        message.includes('Product not found') ||
        message.includes('User profile not found')
      ) {
        status = 404;
      } else if (message.includes('already owned')) {
        status = 409;
      }

      return new Response(JSON.stringify({ success: false, error: message }), {
        status,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify(purchaseResult), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (error) {
    console.error("Edge function error:", error);
    return new Response(JSON.stringify({ success: false, error: error.message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500,
    });
  }
});
