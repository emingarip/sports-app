import { createClient } from '@supabase/supabase-js';
import { GoogleGenAI } from '@google/genai';
import dotenv from 'dotenv';
dotenv.config();

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;
const GEMINI_API_KEY = process.env.GEMINI_API_KEY;

if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY || !GEMINI_API_KEY) {
  console.error("Missing environment variables. Please check your .env file.");
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
const ai = new GoogleGenAI({ apiKey: GEMINI_API_KEY });

const ACTIVE_GAMES = [
  'penalty_shootout', 'flappy_ball', 'header_hero', 
  'goal_celebration', 'goalkeeper_reflex', 'keepy_uppy'
];

async function runSimulation() {
  console.log("🚀 Simulation Engine Started...");
  
  // 1. Chat Simulation Loop (runs every 15 seconds)
  setInterval(simulateLiveChat, 15000);

  // 2. Mini-Game Leaderboard Simulation Loop (runs every 5 seconds)
  setInterval(simulateLeaderboards, 5000);

  // 3. Emoji Reactions Broadcast (runs every 3 seconds)
  setInterval(simulateReactions, 3000);
}

async function simulateLiveChat() {
  try {
    // A. Find live matches
    const { data: matches } = await supabase
      .from('matches')
      .select('*')
      .eq('status', 'live');

    if (!matches || matches.length === 0) return;

    for (const match of matches) {
      // B. Find bots belonging to the teams playing
      const { data: bots } = await supabase
        .from('bot_personas')
        .select('user_id, team, persona_prompt, activity_level')
        .in('team', [match.home_team, match.away_team])
        .limit(50);

      if (!bots || bots.length === 0) continue;

      // Pick a random bot
      const bot = bots[Math.floor(Math.random() * bots.length)];

      // C. Generate context-aware Chat Message via Gemini
      const aiPrompt = `
      Sen Türkçe konuşan fanatik bir futbol taraftarısın. 
      Şu an canlı bir maç izliyorsun: ${match.home_team} vs ${match.away_team}. Skor: ${match.home_score}-${match.away_score}. Maç dakikası: ${match.minute}.
      Senin tuttuğun takım: ${bot.team}.
      Senin kişiliğin/karakterin: "${bot.persona_prompt}".
      
      Lütfen bu karakterinle maça dair çok kısa, 1 cümleyi geçmeyen bir chat mesajı yaz. 
      Sosyal medya dili veya WhatsApp grubu ağzı kullan (gerekirse argosuz trolleme yap). Tırnak işareti olmadan direkt mesajı ver.`;

      const response = await ai.models.generateContent({
        model: 'gemini-2.5-flash',
        contents: aiPrompt,
      });

      const messageContent = response.text?.trim();
      if (!messageContent) continue;

      // D. Insert into DB
      await supabase.from('chat_messages').insert({
        match_id: match.id,
        user_id: bot.user_id,
        message: messageContent,
        type: 'text'
      });

      console.log(`[CHAT] ${bot.team} botu (${bot.user_id.substring(0,8)}) yazdı: ${messageContent}`);
    }
  } catch (err) {
    console.error("simulateLiveChat Error:", err);
  }
}

// Keep track of fake ghost scores locally so they increment logically
const ghostScores = new Map(); 

async function simulateLeaderboards() {
  try {
    // Fetch a random bot to play a random game
    const { data: bots } = await supabase
      .from('bot_personas')
      .select('user_id')
      .limit(100);

    if (!bots || bots.length === 0) return;

    // Pick 3 random bots to update scores for
    for (let i = 0; i < 3; i++) {
      const bot = bots[Math.floor(Math.random() * bots.length)];
      const gameId = ACTIVE_GAMES[Math.floor(Math.random() * ACTIVE_GAMES.length)];
      
      const key = `${bot.user_id}_${gameId}`;
      let currentScore = ghostScores.get(key) || 0;
      
      // Increment score logically
      currentScore += Math.floor(Math.random() * 5) + 1; // Add 1 to 5 points
      
      // Sometimes a bot "dies" and resets
      if (Math.random() > 0.9) {
        currentScore = 0;
      }
      
      ghostScores.set(key, currentScore);

      if (currentScore > 0) {
        await supabase
          .from('mini_game_logs')
          .upsert({
            user_id: bot.user_id,
            game_id: gameId,
            score: currentScore,
          }, { onConflict: 'user_id, game_id' });

        console.log(`[GAME] Bot ${bot.user_id.substring(0,8)} scored ${currentScore} in ${gameId}`);
      }
    }
  } catch (err) {
    console.error("simulateLeaderboards Error:", err);
  }
}

async function simulateReactions() {
  try {
    const { data: matches } = await supabase
      .from('matches')
      .select('id')
      .eq('status', 'live');

    if (!matches || matches.length === 0) return;
    
    const emojis = ['🔥', '⚽', '😱', '👏', '👎', '❤️'];

    for (const match of matches) {
      const emoji = emojis[Math.floor(Math.random() * emojis.length)];
      
      // Fire a broadcast via supabase channel
      const channel = supabase.channel(`match_${match.id}`);
      channel.send({
        type: 'broadcast',
        event: 'reaction',
        payload: { emoji, from_bot: true }
      });
      // Cleanup
      supabase.removeChannel(channel);
    }
  } catch (err) {
    console.error("simulateReactions Error:", err);
  }
}

runSimulation();
