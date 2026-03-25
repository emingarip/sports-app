import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from 'jsr:@supabase/supabase-js@2'

export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  // Handle CORS Preflight requests for browser environments
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // 1. Initialize Supabase Admin Client using secure Service Role key to bypass RLS
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // 2. Fetch Highlightly API securely using Vault/Env Secrets
    const highlightlyKey = Deno.env.get('HIGHLIGHTLY_API_KEY')
    if (!highlightlyKey) throw new Error("Missing HIGHLIGHTLY_API_KEY secret")

    // Parse URL to see if a specific date was requested
    const url = new URL(req.url)
    const targetDate = url.searchParams.get('date') || new Date().toISOString().split('T')[0];
    
    // --- SMART CACHING LOGIC ---
    const { data: syncLog } = await supabaseClient
      .from('api_sync_logs')
      .select('last_synced_at')
      .eq('date', targetDate)
      .maybeSingle()

    let shouldFetchFromAPI = true;
    
    if (syncLog && syncLog.last_synced_at) {
      const lastSynced = new Date(syncLog.last_synced_at);
      const now = new Date();
      const diffMinutes = (now.getTime() - lastSynced.getTime()) / 1000 / 60;
      
      const today = new Date().toISOString().split('T')[0];
      
      if (targetDate === today) {
        // Live matches (today): Cache for 15 minutes to conserve API free quota
        if (diffMinutes <= 15) shouldFetchFromAPI = false;
      } else {
        // Scheduled or Past matches: Cache for 24 hours (1440 mins)
        if (diffMinutes <= 1440) shouldFetchFromAPI = false;
      }
    }

    if (!shouldFetchFromAPI) {
      return new Response(JSON.stringify({ success: true, cached: true, message: "Returned cached data from Supabase DB" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      })
    }
    // --- END CACHING LOGIC ---

    // --- HIGH AVAILABILITY API FALLBACK LOGIC ---
    let data = { data: [] }; // Default empty struct
    
    const fetchHighlightly = async (baseUrl: string, hostHeader: string) => {
      let allMatches: any[] = [];
      let offset = 0;
      const limit = 100;
      let morePages = true;

      let lastResponse: Response | null = null;

      while (morePages) {
        const endpoint = `${baseUrl}?date=${targetDate}&timezone=Europe/Istanbul&limit=${limit}&offset=${offset}`;
        const response = await fetch(endpoint, {
          headers: { 
            'x-rapidapi-key': highlightlyKey,
            'x-rapidapi-host': hostHeader,
            'Content-Type': 'application/json'
          }
        });

        lastResponse = response;

        if (!response.ok) {
          return response; // Exit early on error (e.g., 404, 429) so outer fallback jumps in
        }

        const json = await response.json();
        const matches = json.data || [];
        allMatches = [...allMatches, ...matches];

        // If returned payload is smaller than limit, we reached the end
        if (matches.length < limit) {
          morePages = false;
        } else {
          offset += limit;
        }
      }

      // Re-package the aggregated massive array into a standard 200 OK Response 
      // so the existing fallback evaluation `.json()` works seamlessly
      return new Response(JSON.stringify({ data: allMatches }), { 
        status: 200, 
        headers: { 'Content-Type': 'application/json' } 
      });
    };

    try {
      let response: Response | null = null;
      
      try {
        response = await fetchHighlightly('https://sports.highlightly.net/football/matches', 'sports.highlightly.net');
      } catch (primaryErr) {
        console.error(`Primary API (sports) network/DNS error: ${primaryErr}`);
      }

      // If response is null (network error) OR not OK (e.g. 429 Rate Limit)
      if (!response || !response.ok) {
        if (response) {
          console.log(`Primary API failed with status ${response.status}. Attempting fallback (soccer)...`);
        } else {
          console.log(`Primary API completely unreachable. Attempting fallback (soccer)...`);
        }
        
        try {
          // Secondary endpoint for Football explicit quota
          response = await fetchHighlightly('https://soccer.highlightly.net/football/matches', 'soccer.highlightly.net');
          
          if (response && response.status === 404) {
            console.log("Fallback API 404 on /football/matches, retrying plain /matches...");
            response = await fetchHighlightly('https://soccer.highlightly.net/matches', 'soccer.highlightly.net');
          }
        } catch (fallbackErr) {
          console.error(`Fallback API (soccer) network/DNS error: ${fallbackErr}`);
        }
      }

      // Final evaluation
      if (response && response.ok) {
        data = await response.json();
      } else {
        const status = response ? response.status : 'NETWORK_ERROR';
        console.error(`All Highlightly endpoints failed. Final status: ${status}. Proceeding with cached DB state.`);
      }
    } catch (criticalErr) {
      console.error(`Critical overarching fallback error: ${criticalErr}`);
    }
    
    // 3. Map highlightly payload array to our agnostic DB schema to prevent UI lock-in
    const payloadMatches = data.data || []
    if (payloadMatches.length === 0) {
      return new Response(JSON.stringify({ success: true, message: "No live matches" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }

    const unifiableMap = payloadMatches.map((hlMatch: any) => {
      // safely parse '3 - 1' strings
      let hScore = 0, aScore = 0;
      if (hlMatch.state?.score?.current) {
        const parts = hlMatch.state.score.current.split('-');
        if (parts.length === 2) {
          hScore = parseInt(parts[0].trim()) || 0;
          aScore = parseInt(parts[1].trim()) || 0;
        }
      }

      const desc = hlMatch.state?.description?.toLowerCase() || '';
      
      const isFinished = desc.includes('finished') || desc.includes('ended');
      const isNotStarted = desc.includes('postponed') || desc.includes('canceled') || desc.includes('tbd');
      const isLiveRaw = desc.includes('half') || desc.includes('playing') || desc.includes('live') || desc.includes('pause') || desc.includes('injury');

      const matchDate = new Date(hlMatch.date || new Date().toISOString());
      const now = new Date();
      const hoursSinceKickoff = (now.getTime() - matchDate.getTime()) / (1000 * 60 * 60);

      let derivedStatus = 'pre_match';

      if (isFinished) {
        derivedStatus = 'finished';
      } else if (isLiveRaw) {
        derivedStatus = 'live';
      } else if (!isNotStarted && matchDate <= now && hoursSinceKickoff < 6) {
        // Fallback: If it's within 6 hours of kick-off, assume live. Beyond that, it's stuck/postponed.
        derivedStatus = 'live';
      } else if (hoursSinceKickoff >= 6) {
        derivedStatus = 'finished'; // Or postponed, but finished hides it safely from live widgets
      } else {
        derivedStatus = 'pre_match';
      }

      return {
        provider_id: `highlightly_${hlMatch.id}`,
        league_id: hlMatch.league?.id?.toString() || 'default_league', 
        league_name: hlMatch.league?.name || 'Unknown League',
        league_logo_url: hlMatch.league?.logo || 'https://upload.wikimedia.org/wikipedia/commons/e/e4/Globe.png',
        home_team: hlMatch.homeTeam?.name || 'Unknown',
        away_team: hlMatch.awayTeam?.name || 'Unknown',
        home_logo_url: hlMatch.homeTeam?.logo,
        away_logo_url: hlMatch.awayTeam?.logo,
        status: derivedStatus,
        home_score: hScore,
        away_score: aScore,
        minute: hlMatch.state?.clock ? `${hlMatch.state.clock}'` : "0'",
        started_at: hlMatch.date || new Date().toISOString(),
      }
    })

    // 4. Chunk Upsert into Supabase `matches` table to bypass huge payload limits
    const chunkSize = 300;
    for (let i = 0; i < unifiableMap.length; i += chunkSize) {
      const chunk = unifiableMap.slice(i, i + chunkSize);
      const { error } = await supabaseClient
        .from('matches')
        .upsert(chunk, { onConflict: 'provider_id' });
      if (error) {
        console.error(`Error upserting chunk ${i}:`, error.message);
        throw error;
      }
    }

    // 5. Cleanup completely stuck matches from previous days (orphaned postponed matches)
    const sixHoursAgo = new Date(Date.now() - 6 * 60 * 60 * 1000).toISOString();
    await supabaseClient
      .from('matches')
      .update({ status: 'finished' })
      .eq('status', 'live')
      .lt('started_at', sixHoursAgo);

    // 6. Update the sync log to track the successful fetch
    await supabaseClient
      .from('api_sync_logs')
      .upsert({ date: targetDate, last_synced_at: new Date().toISOString() })

    return new Response(JSON.stringify({ success: true, upserted_count: unifiableMap.length }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    })
  } catch (error: any) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500,
    })
  }
})
