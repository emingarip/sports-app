import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
dotenv.config();

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;
const OPENROUTER_API_KEY = process.env.OPENROUTER_API_KEY;
const OPENROUTER_MODEL = process.env.OPENROUTER_MODEL || "google/gemini-2.5-pro:free";

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

async function testChat() {
  console.log("Looking for live matches...");
  const { data: matches } = await supabase.from('matches').select('*').eq('status', 'live');
  if (!matches || matches.length === 0) {
    console.log("No live matches found.");
    return;
  }
  console.log(`Found ${matches.length} live matches.`);

  let totalBotsFound = 0;
  for (const match of matches) {
    const { data: bots } = await supabase
      .from('bot_personas')
      .select('user_id, team, persona_prompt, activity_level')
      .in('team', [match.home_team, match.away_team])
      .limit(50);

    if (!bots || bots.length === 0) {
      // console.log(`No bots for ${match.home_team} vs ${match.away_team}`);
      continue;
    }
    totalBotsFound += bots.length;

    console.log(`Found ${bots.length} bots for ${match.home_team} vs ${match.away_team}!!`);
    const bot = bots[0];
    
    console.log(`Testing Gemini API for bot ${bot.user_id} (${bot.team})...`);
    
    const aiPrompt = `Test chat for live match ${match.home_team} vs ${match.away_team}. Just say "Hello!" in Turkish.`;
    
    try {
      const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${OPENROUTER_API_KEY}`,
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          "model": OPENROUTER_MODEL,
          "messages": [{ "role": "user", "content": aiPrompt }],
          "reasoning": { "enabled": true }
        })
      });

      const result = await response.json();
      const fs = await import('fs');
      fs.writeFileSync("output.json", JSON.stringify(result, null, 2), "utf8");
      console.log("Response written to output.json");

      // Just break after testing one
      process.exit(0);

    } catch (e) {
      console.error("Fetch error:", e);
    }
  }

  console.log(`Checked all matches. Total bots found interacting: ${totalBotsFound}`);
}

testChat();
