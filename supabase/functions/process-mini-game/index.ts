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

    // Call the newly created atomic RPC
    const { data: result, error: rpcError } = await supabaseAdmin.rpc('atomic_process_mini_game', {
      p_game_id: gameId,
      p_room_id: roomId,
      p_user_id: user.id,
      p_score: score,
      p_reward: 10
    });

    if (rpcError) throw rpcError;

    let message = 'Success';
    let rewardAmount = 0;

    if (result.status === 'new_high_score') {
      message = 'New high score saved!';
    } else if (result.status === 'score_submitted') {
      message = 'Score submitted. Did not beat high score.';
    } else if (result.status === 'success') {
      rewardAmount = result.rewardAmount;
    }

    return new Response(JSON.stringify({ message, rewardAmount }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    })
  } catch (error: any) {
    console.error("Function error:", error.message)
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400,
    })
  }
})
