import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from 'jsr:@supabase/supabase-js@2'

export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Mirrors sports_api model predictions (GET /api/v1/bulletin/predictions)
// into public.bulletin_predictions. Run after sync-bulletin so that
// bulletin_matches rows already exist for the target date.

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

    const predictionsUrl =
      `${sportsApiBaseUrl.replace(/\/$/, '')}/api/v1/bulletin/predictions` +
      `?date=${targetDate}&tz=Europe/Istanbul`
    const response = await fetch(predictionsUrl, { headers })
    if (!response.ok) {
      throw new Error(`sports_api predictions fetch failed with status ${response.status}`)
    }
    const predictions = await response.json()

    if (!Array.isArray(predictions) || predictions.length === 0) {
      return new Response(
        JSON.stringify({ success: true, message: 'No predictions for date', date: targetDate }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    // Resolve bulletin_matches ids for the canonical sports_api match ids.
    const apiIds = predictions.map((p: any) => p.match_id)
    const { data: bulletinMatches, error: idErr } = await supabaseClient
      .from('bulletin_matches')
      .select('id, sports_api_match_id')
      .in('sports_api_match_id', apiIds)
    if (idErr) throw new Error(`bulletin_matches lookup failed: ${idErr.message}`)

    const idByApiId: Record<string, string> = {}
    for (const row of bulletinMatches ?? []) {
      idByApiId[row.sports_api_match_id] = row.id
    }

    const rows = predictions
      .filter((p: any) => idByApiId[p.match_id])
      .map((p: any) => ({
        bulletin_match_id: idByApiId[p.match_id],
        sports_api_match_id: p.match_id,
        model_version: p.model_version,
        generated_at: p.generated_at,
        lambda_home: p.lambda_home,
        lambda_away: p.lambda_away,
        rho: p.rho,
        market_probs: p.market_probs ?? {},
        value_picks: p.value_picks ?? [],
        updated_at: new Date().toISOString(),
      }))

    const chunkSize = 300
    for (let i = 0; i < rows.length; i += chunkSize) {
      const { error } = await supabaseClient
        .from('bulletin_predictions')
        .upsert(rows.slice(i, i + chunkSize), { onConflict: 'bulletin_match_id' })
      if (error) throw new Error(`bulletin_predictions upsert failed: ${error.message}`)
    }

    return new Response(
      JSON.stringify({
        success: true,
        date: targetDate,
        predictions_received: predictions.length,
        predictions_upserted: rows.length,
        skipped_without_bulletin_match: predictions.length - rows.length,
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
