import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'

// Map of RevenueCat Product IDs to K-Coin amounts
const KCOIN_PACKAGES: Record<string, number> = {
  'kcoins_100': 100,
  'kcoins_500': 500,
  'kcoins_1200': 1200,
  'kcoins_2500': 2500,
};

serve(async (req) => {
  try {
    // 1. SECURITY: Fail-closed — Always require webhook secret
    const authToken = req.headers.get('Authorization')
    const expectedToken = Deno.env.get('REVENUECAT_WEBHOOK_SECRET')
    
    if (!expectedToken) {
      console.error('CRITICAL: REVENUECAT_WEBHOOK_SECRET is not configured. Rejecting all requests.')
      return new Response(JSON.stringify({ error: 'Webhook secret not configured' }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    if (authToken !== `Bearer ${expectedToken}`) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    // 2. Parse exactly what RevenueCat sent
    const body = await req.json()
    const event = body.event

    // We only care about purchases (consumables or non-renewing)
    if (event.type !== 'NON_RENEWING_PURCHASE' && event.type !== 'INITIAL_PURCHASE') {
      return new Response(JSON.stringify({ message: `Ignored event type: ${event.type}` }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    const userId = event.app_user_id
    const productId = event.product_id

    // Check if this product is a K-Coin package
    const coinAmount = KCOIN_PACKAGES[productId]
    if (!coinAmount) {
       return new Response(JSON.stringify({ message: `Product ${productId} is not a K-Coin package. Ignored.` }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    // 3. Initialize Supabase Admin Client (service_role bypasses RLS)
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false
        }
      }
    )

    // 4. SECURITY: Atomic balance update via server-side RPC
    // Uses SELECT ... FOR UPDATE to prevent race conditions
    const transactionId = event.transaction_id || `txn_${Date.now()}`
    const { data: rpcResult, error: rpcError } = await supabaseAdmin.rpc('credit_k_coins_server', {
      p_user_id: userId,
      p_amount: coinAmount,
      p_transaction_type: 'topup',
      p_reference_id: productId,
      p_description: `RevenueCat purchase: ${productId}`,
      p_source_type: 'revenuecat',
      p_source_id: transactionId,
      p_idempotency_key: transactionId,
      p_metadata: {
        product_id: productId,
        environment: event.environment,
        event_type: event.type,
      },
    })

    if (rpcError) {
      throw new Error(`Failed to grant coins: ${rpcError.message}`)
    }

    // 5. Log the transaction (idempotent via unique constraint on rc_transaction_id)
    const { error: logError } = await supabaseAdmin
      .from('k_coin_purchasing_history')
      .upsert({
        user_id: userId,
        product_id: productId,
        coins_granted: coinAmount,
        rc_transaction_id: transactionId,
        environment: event.environment, // 'PRODUCTION' or 'SANDBOX'
        ledger_transaction_id: rpcResult?.transaction_id ?? null,
      }, {
        onConflict: 'rc_transaction_id',
      })

    if (logError) { 
      console.error('Failed to log history', logError)
    }

    console.log(`Granted ${coinAmount} K-Coins to ${userId} (tx: ${transactionId})`)

    return new Response(
      JSON.stringify({ success: true, message: `Granted ${coinAmount} K-Coins to ${userId}`, ...rpcResult }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    )
  } catch (error: any) {
    console.error('Webhook processing error:', error)
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }
})
