import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from 'jsr:@supabase/supabase-js@2'

Deno.serve(async (req) => {
  try {
    // 1. Initialize Supabase Admin Client using secure Service Role key to bypass RLS
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // 2. Fetch Highlightly API securely using Vault/Env Secrets
    const highlightlyKey = Deno.env.get('HIGHLIGHTLY_API_KEY')
    if (!highlightlyKey) throw new Error("Missing HIGHLIGHTLY_API_KEY secret")

    // Fetch the live endpoint (Mapped matching the swagger documentation)
    const today = new Date().toISOString().split('T')[0];
    const highlightlyEndpoint = `https://sports.highlightly.net/football/matches?date=${today}&timezone=Europe/Istanbul`;
    
    const response = await fetch(highlightlyEndpoint, {
      headers: { 
        'x-rapidapi-key': highlightlyKey,
        'x-rapidapi-host': 'sports.highlightly.net',
        'Content-Type': 'application/json'
      }
    })
    
    if (!response.ok) throw new Error("Failed to fetch Highlightly data: " + response.statusText)
    const data = await response.json()
    
    // 3. Map highlightly payload array to our agnostic DB schema to prevent UI lock-in
    const payloadMatches = data.data || []
    if (payloadMatches.length === 0) {
      return new Response(JSON.stringify({ success: true, message: "No live matches" }), {
        headers: { "Content-Type": "application/json" },
      })
    }

    const unifiableMap = payloadMatches.slice(0, 100).map((hlMatch: any) => {
      // safely parse '3 - 1' strings
      let hScore = 0, aScore = 0;
      if (hlMatch.state?.score?.current) {
        const parts = hlMatch.state.score.current.split('-');
        if (parts.length === 2) {
          hScore = parseInt(parts[0].trim()) || 0;
          aScore = parseInt(parts[1].trim()) || 0;
        }
      }

      const isFinished = hlMatch.state?.description?.toLowerCase().includes('finished');
      const isNotStarted = hlMatch.state?.description?.toLowerCase().includes('not started');

      return {
        // Unique abstraction identifier prevents dupe matches if we poll every minute
        provider_id: `highlightly_${hlMatch.id}`,
        league_id: hlMatch.league?.id?.toString() || 'default_league', 
        league_name: hlMatch.league?.name || 'Unknown League',
        league_logo_url: hlMatch.league?.logo || 'https://upload.wikimedia.org/wikipedia/commons/e/e4/Globe.png',
        home_team: hlMatch.homeTeam?.name || 'Unknown',
        away_team: hlMatch.awayTeam?.name || 'Unknown',
        home_logo_url: hlMatch.homeTeam?.logo,
        away_logo_url: hlMatch.awayTeam?.logo,
        // Status mapping ensures Flutter enum compatibility (Flutter natively casts `pre_match` fallback to `upcoming`)
        status: isFinished ? 'finished' : (isNotStarted ? 'pre_match' : 'live'),
        home_score: hScore,
        away_score: aScore,
        minute: hlMatch.state?.clock ? `${hlMatch.state.clock}'` : "0'",
        started_at: hlMatch.date || new Date().toISOString(),
      }
    })

    // 4. Upsert into Supabase `matches` table
    const { error } = await supabaseClient
      .from('matches')
      .upsert(unifiableMap, { onConflict: 'provider_id' })

    if (error) throw error

    return new Response(JSON.stringify({ success: true, upserted_count: unifiableMap.length }), {
      headers: { "Content-Type": "application/json" },
      status: 200,
    })
  } catch (error: any) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { "Content-Type": "application/json" },
      status: 500,
    })
  }
})
