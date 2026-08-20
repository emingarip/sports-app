import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from 'jsr:@supabase/supabase-js@2'

export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Settles pending analysis coupons against final scores from the sports_api
// backend (GET /api/v1/matches?date=...&tz=Europe/Istanbul returns a
// MatchSummary list with id, status, score_home, score_away). Only matches
// with status 'finished' are settled. Each selection verdict is computed here
// and pushed into the database through the service-role
// resolve_coupon_selections RPC together with the closing odds — the last
// synced pre-match bulletin_odds rows ARE the closing odds. Half-time (İY)
// markets are voided only when the payload genuinely carries no half-time
// score; MatchSummary exposes score_home_ht / score_away_ht since
// migration 20260820_000008.

type Verdict = 'won' | 'lost' | 'void'

interface FinalScore {
  h: number
  a: number
  htH: number | null
  htA: number | null
}

const HALF_TIME_MARKETS = new Set(['IY', 'IY_AU_0_5', 'IY_AU_1_5', 'IY_MS'])

function outcome1x2(home: number, away: number): 'home' | 'draw' | 'away' {
  if (home > away) return 'home'
  if (home < away) return 'away'
  return 'draw'
}

function totalGoalsBucket(total: number): string {
  if (total <= 1) return '0_1'
  if (total <= 3) return '2_3'
  if (total <= 5) return '4_5'
  return '6_plus'
}

// Verdict for one coupon selection, or null when the market code is unknown —
// the selection is then left pending instead of guessing.
function settleSelection(selection: any, score: FinalScore): Verdict | null {
  const code: string = selection.market_code
  const key: string = selection.selection_key
  const h = score.h
  const a = score.a
  const total = h + a

  if (HALF_TIME_MARKETS.has(code)) {
    // İY markets need the half-time score; void when unavailable.
    if (score.htH === null || score.htA === null) return 'void'
    const htTotal = score.htH + score.htA
    switch (code) {
      case 'IY':
        return key === outcome1x2(score.htH, score.htA) ? 'won' : 'lost'
      case 'IY_AU_0_5':
        return key === (htTotal > 0.5 ? 'over' : 'under') ? 'won' : 'lost'
      case 'IY_AU_1_5':
        return key === (htTotal > 1.5 ? 'over' : 'under') ? 'won' : 'lost'
      case 'IY_MS':
        // Half-time / full-time double, keyed '<ht>_<ft>' (e.g. 'home_draw').
        return key === `${outcome1x2(score.htH, score.htA)}_${outcome1x2(h, a)}`
          ? 'won'
          : 'lost'
    }
  }

  switch (code) {
    case 'MS':
      return key === outcome1x2(h, a) ? 'won' : 'lost'
    case 'CS': {
      const won =
        (key === 'home_draw' && h >= a) ||
        (key === 'home_away' && h !== a) ||
        (key === 'draw_away' && h <= a)
      return won ? 'won' : 'lost'
    }
    case 'AU_1_5':
    case 'AU_2_5':
    case 'AU_3_5': {
      // Prefer the locked line; fall back to the line encoded in the code.
      const line =
        selection.line_value != null
          ? Number(selection.line_value)
          : Number(code.slice(3).replace('_', '.'))
      return key === (total > line ? 'over' : 'under') ? 'won' : 'lost'
    }
    case 'KG':
      return key === (h >= 1 && a >= 1 ? 'yes' : 'no') ? 'won' : 'lost'
    case 'TG':
      return key === totalGoalsBucket(total) ? 'won' : 'lost'
    case 'H_MS_1':
      // Handicap +1 on the home side.
      return key === outcome1x2(h + 1, a) ? 'won' : 'lost'
    case 'H_MS_MINUS_1':
      // Handicap -1 on the home side.
      return key === outcome1x2(h - 1, a) ? 'won' : 'lost'
    default:
      return null
  }
}

// The matches endpoint is date-keyed in Europe/Istanbul.
const istanbulDayFormatter = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'Europe/Istanbul',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
})
const toIstanbulDate = (iso: string) => istanbulDayFormatter.format(new Date(iso))

// MatchSummary (sports_api/app/schemas/match.py) now carries
// score_home_ht / score_away_ht, so İY, İY A/Ü and İY/MS selections settle
// instead of being voided every single time. The older field names are still
// probed because rows written before the half-time columns landed do not have
// the canonical ones.
function readHalfTime(m: any): { htH: number | null; htA: number | null } {
  const htH = m.score_home_ht ?? m.ht_score_home ?? m.score_ht_home ?? m.half_time_home ?? null
  const htA = m.score_away_ht ?? m.ht_score_away ?? m.score_ht_away ?? m.half_time_away ?? null
  if (typeof htH !== 'number' || typeof htA !== 'number') {
    return { htH: null, htA: null }
  }
  return { htH, htA }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const jsonResponse = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status,
    })

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const sportsApiBaseUrl = Deno.env.get('SPORTS_API_BASE_URL')
    if (!sportsApiBaseUrl) throw new Error('Missing SPORTS_API_BASE_URL secret')
    const sportsApiToken = Deno.env.get('SPORTS_API_TOKEN')

    const headers: Record<string, string> = { 'Content-Type': 'application/json' }
    if (sportsApiToken) headers['Authorization'] = `Bearer ${sportsApiToken}`

    const errors: { coupon_id?: string; date?: string; error: string }[] = []

    // 1. Load pending coupons (oldest first).
    const { data: coupons, error: couponsErr } = await supabaseClient
      .from('analysis_coupons')
      .select('id, user_id, selections')
      .eq('status', 'pending')
      .order('created_at', { ascending: true })
      .limit(500)
    if (couponsErr) throw new Error(`analysis_coupons fetch failed: ${couponsErr.message}`)

    if (!coupons || coupons.length === 0) {
      return jsonResponse({
        success: true,
        coupons_checked: 0,
        coupons_resolved: 0,
        selections_settled: 0,
        errors,
      })
    }

    // 2. Distinct Istanbul kickoff dates of pending selections whose matches
    //    have already kicked off (future matches cannot be finished yet).
    const now = Date.now()
    const dates = new Set<string>()
    for (const coupon of coupons) {
      for (const sel of coupon.selections ?? []) {
        if (sel.result !== 'pending' || !sel.kickoff_at) continue
        if (new Date(sel.kickoff_at).getTime() > now) continue
        dates.add(toIstanbulDate(sel.kickoff_at))
      }
    }

    // 3. Fetch results per date and index finished matches by the canonical
    //    sports_api match id.
    const scoreByMatchId = new Map<string, FinalScore>()
    for (const date of dates) {
      const matchesUrl =
        `${sportsApiBaseUrl.replace(/\/$/, '')}/api/v1/matches` +
        `?date=${date}&tz=Europe/Istanbul`
      const response = await fetch(matchesUrl, { headers })
      if (!response.ok) {
        errors.push({ date, error: `sports_api matches fetch failed with status ${response.status}` })
        continue
      }
      const payload = await response.json()
      const matches = Array.isArray(payload) ? payload : payload.matches ?? payload.items ?? []
      for (const m of matches) {
        if (String(m.status ?? '').toLowerCase() !== 'finished') continue
        if (typeof m.score_home !== 'number' || typeof m.score_away !== 'number') {
          errors.push({ date, error: `finished match ${m.id} is missing a final score; skipped` })
          continue
        }
        scoreByMatchId.set(String(m.id), {
          h: m.score_home,
          a: m.score_away,
          ...readHalfTime(m),
        })
      }
    }

    // 4. Closing odds for every settleable selection: the last synced
    //    pre-match bulletin_odds rows are the closing odds.
    const bulletinMatchIds = new Set<string>()
    for (const coupon of coupons) {
      for (const sel of coupon.selections ?? []) {
        if (sel.result !== 'pending') continue
        if (scoreByMatchId.has(String(sel.sports_api_match_id))) {
          bulletinMatchIds.add(sel.bulletin_match_id)
        }
      }
    }

    const closingOdds = new Map<string, number>()
    const idList = [...bulletinMatchIds]
    const chunkSize = 100
    for (let i = 0; i < idList.length; i += chunkSize) {
      const { data: oddsRows, error: oddsErr } = await supabaseClient
        .from('bulletin_odds')
        .select('bulletin_match_id, market_code, selection_key, odds')
        .in('bulletin_match_id', idList.slice(i, i + chunkSize))
      if (oddsErr) throw new Error(`bulletin_odds fetch failed: ${oddsErr.message}`)
      for (const row of oddsRows ?? []) {
        closingOdds.set(
          `${row.bulletin_match_id}|${row.market_code}|${row.selection_key}`,
          Number(row.odds),
        )
      }
    }

    // 5. Settle coupon by coupon; the RPC keeps the coupon pending until every
    //    selection is settled, so partial results are safe to send.
    let couponsResolved = 0
    let selectionsSettled = 0
    for (const coupon of coupons) {
      const selections = coupon.selections ?? []
      const results: { index: number; result: Verdict; closing_odds: number | null }[] = []

      for (let index = 0; index < selections.length; index++) {
        const sel = selections[index]
        if (sel.result !== 'pending') continue

        const score = scoreByMatchId.get(String(sel.sports_api_match_id))
        if (!score) continue // not finished yet (or result feed unavailable)

        const verdict = settleSelection(sel, score)
        if (!verdict) {
          errors.push({
            coupon_id: coupon.id,
            error: `unsupported market_code '${sel.market_code}' at selection ${index}; left pending`,
          })
          continue
        }

        results.push({
          index,
          result: verdict,
          closing_odds:
            closingOdds.get(`${sel.bulletin_match_id}|${sel.market_code}|${sel.selection_key}`) ??
            null,
        })
      }

      if (results.length === 0) continue

      const { data: rpcResult, error: rpcError } = await supabaseClient.rpc(
        'resolve_coupon_selections',
        { p_coupon_id: coupon.id, p_results: results },
      )
      if (rpcError) {
        console.error(`resolve_coupon_selections failed for coupon ${coupon.id}: ${rpcError.message}`)
        errors.push({ coupon_id: coupon.id, error: rpcError.message })
        continue
      }

      selectionsSettled += results.length
      if (rpcResult?.status && rpcResult.status !== 'pending') {
        couponsResolved++
      }
    }

    return jsonResponse({
      success: true,
      coupons_checked: coupons.length,
      coupons_resolved: couponsResolved,
      selections_settled: selectionsSettled,
      errors,
    })
  } catch (error: any) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 500,
    })
  }
})
