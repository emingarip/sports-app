import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Configuration for CORS
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Reward structure
const REWARDS = [100, 70, 50];

serve(async (req) => {
  // Handle CORS options
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      throw new Error('Missing Authorization header');
    }

    const { gameId, roomId } = await req.json()
    
    if (!gameId || !roomId) {
      throw new Error("Missing gameId or roomId");
    }

    // Initialize Admin client (Service Role)
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // Verify token and Admin Role
    const token = authHeader.replace("Bearer ", "");
    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(token);

    if (authError || !user) {
      throw new Error("Unauthorized");
    }

    const { data: userData, error: userError } = await supabaseAdmin
      .from('users')
      .select('is_admin')
      .eq('id', user.id)
      .maybeSingle();

    if (userError || !userData || userData.is_admin !== true) {
      return new Response(JSON.stringify({ error: "Forbidden: Admin access required" }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 403,
      });
    }

    // Check if game is already finalized to prevent double-rewards
    const { data: existingLog, error: checkError } = await supabaseAdmin
      .from('mini_game_logs')
      .select('rank_reward')
      .eq('game_id', gameId)
      .not('rank_reward', 'is', null)
      .limit(1)

    if (checkError) throw checkError;
    if (existingLog && existingLog.length > 0) {
      throw new Error("Game is already finalized.");
    }

    // Fetch the top 3 scores for this gameId
    const { data: topScores, error: topError } = await supabaseAdmin
      .from('mini_game_logs')
      .select('id, user_id, score, users(username)')
      .eq('game_id', gameId)
      .order('score', { ascending: false })
      .limit(3)

    if (topError) throw topError;

    const winners: any[] = [];

    // Distribute rewards
    for (let i = 0; i < topScores.length; i++) {
      const topLog = topScores[i];
      const reward = REWARDS[i] || 0; // 100, 70, 50

      if (reward > 0) {
        // Log the assigned rank reward to prevent double execution
        await supabaseAdmin
          .from('mini_game_logs')
          .update({ rank_reward: reward, rank: i + 1 })
          .eq('id', topLog.id);

        // Update User Balance by the rank reward using the RPC
        const { error: rpcError } = await supabaseAdmin.rpc('process_user_balance_transaction', {
          user_id_param: topLog.user_id,
          amount_param: reward,
          operation: 'add'
        });

        if (rpcError) {
          console.error("Failed to add reward to user:", rpcError);
        }

        winners.push({
          userId: topLog.user_id,
          username: topLog.users?.username || 'Top Sektirme',
          score: topLog.score,
          reward: reward,
          rank: i + 1
        });
      }
    }

    // Broadcast the winners to the Realtime room so Flutter/React UI displays the leaderboard
    const channelName = `match_${roomId}`;
    
    await new Promise<void>((resolve) => {
      const channel = supabaseAdmin.channel(channelName);
      channel.subscribe(async (status) => {
        if (status === 'SUBSCRIBED') {
          const { error: broadcastError } = await channel.send({
            type: 'broadcast',
            event: 'mini_game',
            payload: {
              action: 'GAME_WINNERS',
              gameId: gameId,
              winners: winners
            }
          });
          
          if (broadcastError) {
            console.error("Broadcast failed:", broadcastError);
          }
          
          setTimeout(() => {
            supabaseAdmin.removeChannel(channel);
            resolve();
          }, 1000);
        }
        
        if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
          console.error("Failed to subscribe to channel for broadcast");
          supabaseAdmin.removeChannel(channel);
          resolve(); // Don't throw, just log the error and continue
        }
      });
    });

    return new Response(JSON.stringify({ message: 'Game finalized', winners }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    })
  } catch (error: any) {
    console.error("Finalize error:", error.message)
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400,
    })
  }
})
