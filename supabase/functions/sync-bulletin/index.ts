import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from 'jsr:@supabase/supabase-js@2'

export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Pulls the daily iddaa bulletin from the sports_api backend
// (GET /api/v1/bulletin) and mirrors it into public.bulletin_matches /
// public.bulletin_odds so the Flutter client can read it through the standard
// Supabase channel (including realtime odds updates).

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const sportsApiBaseUrl = Deno.env.get('SPORTS_API_BASE_URL')
    if (!sportsApiBaseUrl) throw new Error('Missing SPORTS_API_BASE_URL secret')
    const sportsApiToken = Deno.env.get('SPORTS_API_TOKEN')

    const url = new URL(req.url)
    const targetDate = url.searchParams.get('date') || new Date().toISOString().split('T')[0]

    const headers: Record<string, string> = { 'Content-Type': 'application/json' }
    if (sportsApiToken) headers['Authorization'] = `Bearer ${sportsApiToken}`

    const bulletinUrl =
      `${sportsApiBaseUrl.replace(/\/$/, '')}/api/v1/bulletin` +
      `?date=${targetDate}&tz=Europe/Istanbul`
    const response = await fetch(bulletinUrl, { headers })
    if (!response.ok) {
      throw new Error(`sports_api bulletin fetch failed with status ${response.status}`)
    }
    const bulletin = await response.json()
    const matches = bulletin.matches ?? []

    if (matches.length === 0) {
      return new Response(
        JSON.stringify({ success: true, message: 'Bulletin empty for date', date: targetDate }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    // 1. Upsert bulletin matches keyed by the canonical sports_api match id.
    const matchRows = matches.map((m: any) => ({
      sports_api_match_id: m.match_id,
      event_date: targetDate,
      kickoff_at: m.kickoff_at,
      status: m.status ?? 'scheduled',
      competition_name: m.competition_name,
      home_team: m.home_team,
      away_team: m.away_team,
      mbs: m.mbs,
      updated_at: new Date().toISOString(),
    }))

    const chunkSize = 300
    for (let i = 0; i < matchRows.length; i += chunkSize) {
      const { error } = await supabaseClient
        .from('bulletin_matches')
        .upsert(matchRows.slice(i, i + chunkSize), { onConflict: 'sports_api_match_id' })
      if (error) throw new Error(`bulletin_matches upsert failed: ${error.message}`)
    }

    // 2. Resolve generated ids so odds rows can reference them.
    const apiIds = matches.map((m: any) => m.match_id)
    const { data: storedMatches, error: idErr } = await supabaseClient
      .from('bulletin_matches')
      .select('id, sports_api_match_id')
      .in('sports_api_match_id', apiIds)
    if (idErr) throw new Error(`bulletin_matches id lookup failed: ${idErr.message}`)

    const idByApiId: Record<string, string> = {}
    for (const row of storedMatches ?? []) {
      idByApiId[row.sports_api_match_id] = row.id
    }

    // 3. Upsert odds per match/market/selection.
    let oddsCount = 0
    const oddsRows: any[] = []
    for (const m of matches) {
      const bulletinMatchId = idByApiId[m.match_id]
      if (!bulletinMatchId) continue
      for (const market of m.markets ?? []) {
        for (const selection of market.selections ?? []) {
          oddsRows.push({
            bulletin_match_id: bulletinMatchId,
            market_code: market.market_code,
            market_type: market.market_type,
            market_name_tr: market.name_tr,
            line_value: market.line_value,
            selection_key: selection.selection_key,
            selection_label_tr: selection.label_tr,
            odds: selection.odds,
            opening_odds: selection.opening_odds,
            movement_pct: selection.movement_pct,
            is_dropping: selection.is_dropping ?? false,
            implied_prob: selection.implied_prob,
            normalized_prob: selection.normalized_prob,
            suspended: selection.suspended ?? false,
            last_tick_at: market.last_tick_at,
            updated_at: new Date().toISOString(),
          })
        }
      }
    }

    for (let i = 0; i < oddsRows.length; i += chunkSize) {
      const { error } = await supabaseClient
        .from('bulletin_odds')
        .upsert(oddsRows.slice(i, i + chunkSize), {
          onConflict: 'bulletin_match_id,market_code,selection_key',
        })
      if (error) throw new Error(`bulletin_odds upsert failed: ${error.message}`)
      oddsCount += Math.min(chunkSize, oddsRows.length - i)
    }

    return new Response(
      JSON.stringify({
        success: true,
        date: targetDate,
        matches_upserted: matchRows.length,
        odds_upserted: oddsCount,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 },
    )
  } catch (error: any) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 500,
    })
  }
})
