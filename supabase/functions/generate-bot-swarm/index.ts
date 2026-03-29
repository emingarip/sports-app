import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { corsHeaders } from '../_shared/cors.ts';

const TURKISH_FIRST_NAMES = [
  "Ahmet", "Mehmet", "Can", "Burak", "Emre", "Kaan", "Cem", "Ali", "Ozan", "Murat",
  "Ayşe", "Fatma", "Zeynep", "Elif", "Merve", "Ceren", "Ece", "Buse", "Gizem", "Selin"
];
const TURKISH_LAST_NAMES = [
  "Yılmaz", "Kaya", "Demir", "Çelik", "Şahin", "Yıldız", "Yıldırım", "Öztürk", "Aydın", "Özdemir",
  "Aslan", "Doğan", "Kılıç", "Cetın", "Kara", "Koç", "Kurt", "Özkan", "Şimşek", "Polat"
];

function generateRandomName() {
  const first = TURKISH_FIRST_NAMES[Math.floor(Math.random() * TURKISH_FIRST_NAMES.length)];
  const last = TURKISH_LAST_NAMES[Math.floor(Math.random() * TURKISH_LAST_NAMES.length)];
  return { first, last, full: `${first} ${last}` };
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '' // Need service role to create users
    );

    // Get the request payload
    const payload = await req.json();
    const { count = 10, team, persona_prompt, activity_level = 'medium' } = payload;

    if (!team || !persona_prompt) {
      throw new Error("team and persona_prompt are required.");
    }

    if (count > 50) {
      throw new Error("Max 50 bots can be generated at a time to prevent timeouts.");
    }

    console.log(`Generating a swarm of ${count} bots for team ${team}...`);

    let createdCount = 0;
    const errors = [];

    // Create bots concurrently in chunks to avoid overwhelming the auth API
    const chunkSize = 5;
    for (let i = 0; i < count; i += chunkSize) {
      const chunk = Array.from({ length: Math.min(chunkSize, count - i) });
      
      const promises = chunk.map(async () => {
        const { first, last, full } = generateRandomName();
        const randNum = Math.floor(Math.random() * 9000) + 1000;
        const username = `${first.toLowerCase()}_${last.toLowerCase()}${randNum}`;
        const email = `bot_${crypto.randomUUID().split('-')[0]}@sportsapp.ai`;
        const avatar_url = `https://ui-avatars.com/api/?name=${first}+${last}&background=random`;

        // 1. Create Auth User
        const { data: authData, error: authError } = await supabaseClient.auth.admin.createUser({
          email,
          password: crypto.randomUUID(), // Random impossible-to-guess password
          email_confirm: true,
          user_metadata: {
            username,
            avatar_url,
            is_bot: true, // Custom flag in metadata
          }
        });

        if (authError) {
          console.error("Auth Error:", authError);
          errors.push(authError.message);
          return null;
        }

        const userId = authData.user.id;

        // NOTE: Our database trigger `on_auth_user_created` will automatically insert this user 
        // into `public.users`. However, it doesn't set `is_bot`. We need to update that.
        
        // 2. Update public.users to set is_bot = true
        await supabaseClient
          .from('users')
          .update({ is_bot: true })
          .eq('id', userId);

        // 3. Insert into bot_personas
        const { error: personaError } = await supabaseClient
          .from('bot_personas')
          .insert({
            user_id: userId,
            team,
            persona_prompt,
            activity_level
          });

        if (personaError) {
          console.error("Persona Error:", personaError);
          errors.push(personaError.message);
          return null;
        }

        return userId;
      });

      const results = await Promise.all(promises);
      createdCount += results.filter(id => id !== null).length;
    }

    return new Response(
      JSON.stringify({ 
        success: true, 
        message: `Successfully created ${createdCount} bots.`, 
        created_count: createdCount,
        errors 
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      }
    );

  } catch (error: any) {
    console.error("Function error:", error);
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400,
    });
  }
});
