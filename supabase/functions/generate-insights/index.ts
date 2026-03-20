import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
// Consider importing an LLM library or native fetch for Gemini/Vertex.

console.log('Generate Insights Edge Function started')

serve(async (req) => {
  // CORS Headers
  const headers = { 
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Content-Type': 'application/json'
  }
  
  // Handle preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers })
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: req.headers.get('Authorization')! } } }
    )

    // 1. Read Request Payload
    const { match_id, trigger_type } = await req.json()
    console.log(`Generating insights for Match: ${match_id}, Trigger: ${trigger_type}`)

    if (!match_id) throw new Error("match_id is required")

    // 2. Fetch Match Data
    const { data: matchData, error: matchError } = await supabaseClient
      .from('matches')
      .select('*')
      .eq('id', match_id)
      .single()

    if (matchError || !matchData) throw new Error("Match not found")

    // 3. Prepare AI Prompt Based on Trigger (pre_match or live)
    let systemPrompt = "";
    if (trigger_type === 'pre_match') {
      systemPrompt = "You are a tactical football analyst. Based on historic data and team forms, generate 3 highly specific tactical insights."
    } else {
      systemPrompt = `You are a live commentator. The score is ${matchData.home_team} ${matchData.home_score} - ${matchData.away_score} ${matchData.away_team} at minute ${matchData.minute}. Generate 3 reactive situational insights.`
    }

    // 4. Call Google Gemini / AI API (Pseudocode, replace with actual fetch call)
    /*
    const aiResponse = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent?key=${Deno.env.get('GEMINI_API_KEY')}`, {
      method: "POST",
      body: JSON.stringify({ contents: [{ parts: [{ text: systemPrompt }] }] })
    });
    const generatedInsights = await aiResponse.json();
    */
    
    // Mocked AI output for now
    const generatedInsightsText = `Insight 1: ${matchData.home_team} will try to dominate possession.\nInsight 2: ${matchData.away_team} is set up for counters.`

    // 5. Store Insights in Supabase
    const { data: insertedData, error: insertError } = await supabaseClient
      .from('match_insights')
      .insert([
        { match_id: match_id, insight_text: generatedInsightsText, type: trigger_type }
      ])
      .select()

    if (insertError) throw new Error("Failed to insert insight")

    return new Response(JSON.stringify({ success: true, insights: insertedData }), { headers })

  } catch (error: any) {
    return new Response(JSON.stringify({ error: error.message }), { headers, status: 400 })
  }
})
