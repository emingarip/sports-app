// Follow this setup guide to integrate the Deno language server with your editor:
// https://supabase.com/docs/guides/functions/getting-started

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import * as jwt from "https://deno.land/x/djwt@v2.9/mod.ts";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // We are trusting the JWT from the Authorization header since we disabled verification at the gateway.
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      throw new Error('Missing Authorization header');
    }

    const token = authHeader.replace('Bearer ', '');
    // Decode JWT payload (without verification, Supabase Edge Functions trust Kong gateway, but we bypassed it)
    // Wait, since we bypassed Kong JWT verify, we should verify it here, or just trust the auth.getUser()
    
    // Create Supabase client with the user's JWT
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } }
    )

    // Get the user from the token to ensure it's valid
    const { data: { user }, error: userError } = await supabaseClient.auth.getUser()
    if (userError || !user) {
      throw new Error('Invalid JWT token or user not found')
    }

    const { gameId, roomId, score } = await req.json()
    
    // Basic fraud validation (Score must be non-negative)
    if (typeof score !== 'number' || score < 0) {
      throw new Error('Invalid score')
    }

    // Initialize Admin client to update balances securely
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // Log the user's score in the mini_game_logs
    const { error: logError } = await supabaseAdmin
      .from('mini_game_logs')
      .insert({
        game_id: gameId,
        room_id: roomId,
        user_id: user.id,
        score: score,
        reward: 10
      })

    if (logError) {
      // If user played multiple times? Depends on unique constraints. 
      // Assuming unique(mini_game_id, user_id), we might catch an error if they play twice.
      console.log("Log error:", logError)
      // Allow it to fail gracefully if they already claimed
      if (logError.code === '23505') { // Unique violation
        return new Response(JSON.stringify({ error: 'Reward already claimed for this game.' }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 400,
        })
      }
      throw logError
    }

    // Update User Balance by +10 K-Coin using the newly created transaction RPC
    const { error: rpcError } = await supabaseAdmin.rpc('process_user_balance_transaction', {
      user_id_param: user.id,
      amount_param: 10,
      operation: 'add'
    })

    if (rpcError) throw rpcError

    return new Response(JSON.stringify({ message: 'Success', rewardAmount: 10 }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    })
  } catch (error) {
    console.error("Function error:", error.message)
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400,
    })
  }
})
