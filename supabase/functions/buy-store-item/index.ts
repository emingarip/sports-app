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

    const gamificationApiUrl = Deno.env.get("GAMIFICATION_API_URL");
    const gamificationAdminToken = Deno.env.get("GAMIFICATION_ADMIN_TOKEN");

    if (!gamificationApiUrl || !gamificationAdminToken) {
       throw new Error("Gamification credentials not found in env");
    }

    // Initialize Supabase Admin client
    const supabaseAdmin = createClient(supabaseUrl, supabaseKey);

    // Get Auth token from the request
    const authHeader = req.headers.get('Authorization')!;
    if (!authHeader) {
        return new Response(JSON.stringify({ error: "Missing Authorization header" }), { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // Verify token and get User
    const supabaseAuthClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY")!, {
        global: { headers: { Authorization: authHeader } }
    });
    
    const { data: { user }, error: userError } = await supabaseAuthClient.auth.getUser();
    
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
    
    if (!productCode) {
        return new Response(JSON.stringify({ error: "Missing product_code" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // 1. Fetch Product
    const { data: product, error: productError } = await supabaseAdmin
        .from('store_products')
        .select('*')
        .eq('product_code', productCode)
        .eq('is_active', true)
        .single();
        
    if (productError || !product) {
       return new Response(JSON.stringify({ error: `Product ${productCode} not found or inactive` }), { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const price = product.price;

    // 2. Fetch User's K-Coins from Gamification API (Optional but good for quick check)
    // Actually, we can just attempt the subtract directly. If it fails, balance is insufficient.
    // Let's call Gamification API subtract
    const gamificationUpdateUrl = `${gamificationApiUrl}/users/${userId}/points`;
    
    const subtractRes = await fetch(gamificationUpdateUrl, {
        method: "PUT",
        headers: {
            "Content-Type": "application/json",
            "Authorization": `Bearer ${gamificationAdminToken}` // Custom Admin token header logic for Gamification
        },
        body: JSON.stringify({
            points: price,
            operation: "subtract",
            action_type: "store_purchase", // Audit trail in gamification
            metadata: {
                product_code: productCode
            }
        })
    });

    if (!subtractRes.ok) {
        const errorData = await subtractRes.json().catch(() => ({}));
        console.error("Gamification API Error:", subtractRes.status, errorData);
        // Usually 400 means insufficient balance in Gamification
        const msg = errorData.error || "Insufficient K-Coin balance or Gamification system error";
        return new Response(JSON.stringify({ error: msg }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const subtractData = await subtractRes.json();
    const newBalance = subtractData.total_points || 0; // Gamification returns total_points

    // 3. Record the transaction in PostgreSQL
    const { data: transaction, error: txError } = await supabaseAdmin
        .from('k_coin_transactions')
        .insert({
            user_id: userId,
            amount: -price,
            transaction_type: 'purchase',
            reference_id: productCode,
            description: `Purchased store item: ${product.title}`
        })
        .select('id')
        .single();

    if (txError) {
        console.error("Transaction Insert Error:", txError);
        // Note: Gamification points were already deducted. Ideally we'd have a distributed transaction / saga pattern, 
        // but for now logging is sufficient since this is just a ledger.
    }
    
    const transactionId = transaction?.id;
    let entitlementId = null;

    // 4. Issue Entitlement if not consumable
    if (product.product_type !== 'consumable') {
        let expiresAt = null;
        if (product.product_type === 'subscription') {
            expiresAt = new Date();
            expiresAt.setDate(expiresAt.getDate() + product.duration_days);
            
            // Check existing entitlement to add to the existing expiry if active
            const { data: existing } = await supabaseAdmin
                .from('user_entitlements')
                .select('expires_at')
                .eq('user_id', userId)
                .eq('product_code', productCode)
                .single();
                
            if (existing && existing.expires_at) {
                const existingExp = new Date(existing.expires_at);
                if (existingExp.getTime() > Date.now()) {
                    existingExp.setDate(existingExp.getDate() + product.duration_days);
                    expiresAt = existingExp;
                }
            }
        }
        
        const { data: entitlement, error: entError } = await supabaseAdmin
            .from('user_entitlements')
            .upsert({
                user_id: userId,
                product_code: productCode,
                expires_at: expiresAt ? expiresAt.toISOString() : null,
                is_active: true
            }, { onConflict: 'user_id, product_code' })
            .select('id')
            .single();

        if (entError) {
            console.error("Entitlement Upsert Error:", entError);
        } else {
            entitlementId = entitlement?.id;
        }
    }

    // 5. Return success
    return new Response(JSON.stringify({
        success: true,
        new_balance: newBalance,
        transaction_id: transactionId,
        entitlement_id: entitlementId
    }), {
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
