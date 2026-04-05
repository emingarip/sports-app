import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.3'
import { SignJWT } from 'https://esm.sh/jose@5.9.6'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const allowedEventTypes = new Set(['rewarded_ad', 'daily_reward', 'task_reward'])

function isAllowedGamificationUrl(url: string): boolean {
  return url.startsWith('https://') ||
    url.startsWith('http://localhost') ||
    url.startsWith('http://127.0.0.1')
}

function buildDescription(eventType: string, pointsAwarded: number): string {
  switch (eventType) {
    case 'rewarded_ad':
      return `Rewarded ad payout: ${pointsAwarded} K-Coins`
    case 'daily_reward':
      return `Daily reward payout: ${pointsAwarded} K-Coins`
    case 'task_reward':
      return `Task reward payout: ${pointsAwarded} K-Coins`
    default:
      return `Reward payout: ${pointsAwarded} K-Coins`
  }
}

function resolveExternalEventType(eventType: string): string {
  switch (eventType) {
    case 'rewarded_ad':
      return 'ad_reward'
    default:
      return eventType
  }
}

function normalizeStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return []
  return value
    .map((entry) => `${entry}`.trim())
    .filter((entry) => entry.length > 0)
}

async function buildGamificationAuthHeader(secretOrToken: string): Promise<string> {
  const trimmed = secretOrToken.trim()
  if (!trimmed) {
    throw new Error('GAMIFICATION_API_SECRET is not configured.')
  }

  // Backward compatibility: if the secret already looks like a JWT, send it as-is.
  if (trimmed.split('.').length === 3) {
    return `Bearer ${trimmed}`
  }

  const secretKey = new TextEncoder().encode(trimmed)
  const token = await new SignJWT({
    email: 'supabase-service',
    permissions: ['read', 'write', 'delete', 'admin'],
    role: 'admin',
    sub: 'supabase_service',
    type: 'access',
    user_id: 'supabase_service',
    username: 'supabase-service',
  })
    .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
    .setIssuedAt()
    .setIssuer('muscle-gamification')
    .setExpirationTime('30m')
    .sign(secretKey)

  return `Bearer ${token}`
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error('Supabase credentials are not configured.')
    }

    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing Authorization header' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const jwt = authHeader.replace(/^Bearer\s+/i, '').trim()
    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    })

    const { data: { user }, error: userError } = await supabaseAdmin.auth.getUser(jwt)
    if (userError || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const body = await req.json().catch(() => null)
    const eventType = `${body?.event_type ?? ''}`.trim()
    const referenceId = `${body?.reference_id ?? ''}`.trim()
    const metadata = body?.metadata && typeof body.metadata === 'object' ? body.metadata : {}

    if (!allowedEventTypes.has(eventType)) {
      return new Response(JSON.stringify({ error: 'Unsupported event_type' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (!referenceId) {
      return new Response(JSON.stringify({ error: 'reference_id is required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const idempotencyKey = `reward:${eventType}:${user.id}:${referenceId}`
    const { data: existingTransaction, error: existingError } = await supabaseAdmin
      .from('k_coin_transactions')
      .select('id, amount, balance_after, metadata')
      .eq('user_id', user.id)
      .eq('idempotency_key', idempotencyKey)
      .maybeSingle()

    if (existingError) {
      throw new Error(`Failed to inspect wallet ledger: ${existingError.message}`)
    }

    if (existingTransaction) {
      const existingMetadata = (existingTransaction.metadata ?? {}) as Record<string, unknown>
      return new Response(JSON.stringify({
        success: true,
        points_awarded: Math.max(0, Number(existingTransaction.amount ?? 0)),
        new_balance: Number(existingTransaction.balance_after ?? 0),
        transaction_id: existingTransaction.id,
        matched_rules: normalizeStringArray(existingMetadata.matched_rules),
        badges_awarded: normalizeStringArray(existingMetadata.badges_awarded),
        already_applied: true,
      }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (eventType === 'rewarded_ad') {
      const { data: eligibility, error: eligibilityError } = await supabaseAdmin.rpc('check_ad_eligibility_for_user', {
        p_user_id: user.id,
      })

      if (eligibilityError) {
        throw new Error(`Failed to validate rewarded ad eligibility: ${eligibilityError.message}`)
      }

      if (!eligibility?.eligible) {
        return new Response(JSON.stringify({
          success: false,
          error: 'Rewarded ad is not currently eligible.',
          reason: eligibility?.reason ?? 'unknown',
          next_available: eligibility?.next_available ?? null,
        }), {
          status: 409,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }
    }

    const gamificationApiUrl = (Deno.env.get('GAMIFICATION_API_URL') ?? '').trim()
    const gamificationApiSecret = (Deno.env.get('GAMIFICATION_API_SECRET') ?? '').trim()

    if (!gamificationApiUrl || !isAllowedGamificationUrl(gamificationApiUrl)) {
      throw new Error('GAMIFICATION_API_URL must be configured with HTTPS in production.')
    }

    const gamificationAuthHeader = await buildGamificationAuthHeader(gamificationApiSecret)

    const externalEventType = resolveExternalEventType(eventType)

    const rewardResponse = await fetch(`${gamificationApiUrl}/events`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': gamificationAuthHeader,
      },
      body: JSON.stringify({
        user_id: user.id,
        event_type: externalEventType,
        metadata: {
          ...metadata,
          reference_id: referenceId,
          internal_event_type: eventType,
        },
      }),
    })

    const rewardText = await rewardResponse.text()
    let rewardData: Record<string, unknown> = {}
    try {
      rewardData = rewardText ? JSON.parse(rewardText) : {}
    } catch {
      rewardData = { message: rewardText }
    }

    if (!rewardResponse.ok) {
      const errorMessage = typeof rewardData.error === 'string'
        ? rewardData.error
        : 'Gamification reward engine returned an error.'

      return new Response(JSON.stringify({
        success: false,
        error: errorMessage,
        details: rewardData,
      }), {
        status: rewardResponse.status,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const pointsAwarded = Math.max(0, Number(rewardData.points_awarded ?? 0))
    const matchedRules = normalizeStringArray(rewardData.matched_rules)
    const badgesAwarded = normalizeStringArray(rewardData.badges_awarded)

    if (pointsAwarded <= 0) {
      return new Response(JSON.stringify({
        success: true,
        points_awarded: 0,
        new_balance: null,
        transaction_id: null,
        matched_rules: matchedRules,
        badges_awarded: badgesAwarded,
        already_applied: false,
      }), {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const { data: creditResult, error: creditError } = await supabaseAdmin.rpc('credit_k_coins_server', {
      p_user_id: user.id,
      p_amount: pointsAwarded,
      p_transaction_type: eventType,
      p_reference_id: referenceId,
      p_description: buildDescription(eventType, pointsAwarded),
      p_source_type: 'gamification',
      p_source_id: referenceId,
      p_idempotency_key: idempotencyKey,
      p_metadata: {
        ...metadata,
        reference_id: referenceId,
        matched_rules: matchedRules,
        badges_awarded: badgesAwarded,
      },
    })

    if (creditError) {
      throw new Error(`Failed to settle reward: ${creditError.message}`)
    }

    return new Response(JSON.stringify({
      success: true,
      points_awarded: pointsAwarded,
      new_balance: creditResult?.new_balance ?? null,
      transaction_id: creditResult?.transaction_id ?? null,
      matched_rules: matchedRules,
      badges_awarded: badgesAwarded,
      already_applied: creditResult?.already_applied === true,
    }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error) {
    console.error('claim-kcoin-reward error:', error)
    return new Response(JSON.stringify({
      success: false,
      error: error instanceof Error ? error.message : 'Unknown error',
    }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
