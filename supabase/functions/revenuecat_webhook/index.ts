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
    // 1. Validate the Webhook Secret (Security measure)
    const authToken = req.headers.get('Authorization')
    const expectedToken = Deno.env.get('REVENUECAT_WEBHOOK_SECRET')
    
    // Fallback or debug mode checking (in production, always enforce the secret)
    if (expectedToken && authToken !== `Bearer ${expectedToken}`) {
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

    // 3. Initialize Supabase Admin Client
    // We need service_role key to bypass RLS and securely update user balances
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

    // 4. Update the User's K-Coin balance
    // Get current balance first (though doing it atomically via RPC is better, we can also use direct update if safe, or call our process transaction RPC)
    
    // We will call the database to securely add the coins:
    const { data: userData, error: userError } = await supabaseAdmin
      .from('users')
      .select('k_coin_balance')
      .eq('id', userId)
      .single()

    if (userError || !userData) {
      throw new Error(`User not found: ${userId}`)
    }

    const newBalance = (userData.k_coin_balance || 0) + coinAmount

    const { error: updateError } = await supabaseAdmin
      .from('users')
      .update({ k_coin_balance: newBalance })
      .eq('id', userId)

    if (updateError) throw updateError

    // 5. Log the transaction (for user history)
    const transactionId = event.transaction_id || `txn_${Date.now()}`;
    const { error: logError } = await supabaseAdmin
      .from('k_coin_purchasing_history')
      .insert({
        user_id: userId,
        product_id: productId,
        coins_granted: coinAmount,
        rc_transaction_id: transactionId,
        environment: event.environment // 'PRODUCTION' or 'SANDBOX'
      })

    if (logError && logError.code !== '23505') { 
      // Ignored if it's a unique constraint violation (duplicate webhook)
      console.error('Failed to log history', logError)
    }

    return new Response(
      JSON.stringify({ success: true, message: `Granted ${coinAmount} K-Coins to ${userId}` }),
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
