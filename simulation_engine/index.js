import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
import { pipeline } from '@xenova/transformers';

dotenv.config();

let generateEmbedding;
(async () => {
  try {
    generateEmbedding = await pipeline('feature-extraction', 'Xenova/all-MiniLM-L6-v2');
    console.log("[AI] Xenova Embedding (Vector) Model yüklendi! Hafıza sistemi aktif.");
  } catch (e) {
    console.error("Xenova Model Error:", e);
  }
})();

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;
const OPENROUTER_API_KEY = process.env.OPENROUTER_API_KEY;
const OPENROUTER_MODEL = process.env.OPENROUTER_MODEL || "google/gemini-2.0-flash-lite-preview-02-05:free";

if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY || !OPENROUTER_API_KEY) {
  console.error("Missing environment variables. Please check your .env file.");
  process.exit(1);
}

// Suppress Supabase Realtime REST fallback deprecation warning to keep terminal clean
const originalConsoleWarn = console.warn;
console.warn = (...args) => {
  if (args[0] && typeof args[0] === 'string' && args[0].includes('Realtime send() is automatically falling back to REST API')) return;
  originalConsoleWarn(...args);
};
const originalConsoleLog = console.log;
console.log = (...args) => {
  if (args[0] && typeof args[0] === 'string' && args[0].includes('Realtime send() is automatically falling back to REST API')) return;
  originalConsoleLog(...args);
};

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

const ACTIVE_GAMES = [
  'keepy_uppy'
];

async function runSimulation() {
  console.log("🚀 Simulation Engine Started...");
  
  // 1. Chat Simulation Loop (runs every 15 seconds)
  setInterval(simulateLiveChat, 15000);

  // 2. Mini-Game Leaderboard Simulation Loop (runs every 5 seconds)
  setInterval(simulateLeaderboards, 5000);

  // 3. Emoji Reactions Broadcast (runs every 3 seconds)
  setInterval(simulateReactions, 3000);

  // 4. Realtime Chat Listener for Smart Bot Follows
  supabase
    .channel('public:chat_messages')
    .on(
      'postgres_changes',
      { event: 'INSERT', schema: 'public', table: 'chat_messages' },
      handleNewChatMessage
    )
    .subscribe();

  // 5. Realtime DM Listener for Bots
  supabase
    .channel('public:private_messages')
    .on(
      'postgres_changes',
      { event: 'INSERT', schema: 'public', table: 'private_messages' },
      handleNewPrivateMessage
    )
    .subscribe();
}

async function handleNewChatMessage(payload) {
  try {
    const message = payload.new;
    // Sadece kısa ve anlamlı mesajları değerlendir, API yığılmasını önle
    if (!message || !message.message || message.message.length < 5) return;
    
    // Yüzde 50 ihtimalle görmezden gel (API rate limit koruması)
    if (Math.random() > 0.5) return;

    // Check if user is a bot
    const { data: user } = await supabase
      .from('users')
      .select('username, is_bot')
      .eq('id', message.user_id)
      .single();

    if (!user || user.is_bot) return;

    // Gemini evaluation
    const aiPrompt = `
    Bir futbol platformundayız. 
    Kullanıcı şu mesajı yazdı: "${message.message}"
    
    Bu mesaj gerçekten tutkulu, iddialı, eğlenceli veya takımını çok iyi savunan bir mesaj mı?
    Eğer öyleyse, platformdaki diğer taraftarlar (botlar) bu kişiye saygı duyup arkadaş eklemek/takip etmek ister.
    
    Cevabı SADECE şu formatta ver:
    Eğer takibe değerse: "EVET | [Arkadaşlık isteği yollayan botun diliyle kısaca neden takip etmek istediğini yaz. Mümkün olduğunca doğal ve oyundaki duruma yönelik olsun]"
    Eğer sıradan veya boş bir mesajsa: "HAYIR"
    `;

    const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${OPENROUTER_API_KEY}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        "model": OPENROUTER_MODEL,
        "messages": [
          {
            "role": "user",
            "content": aiPrompt
          }
        ]
      })
    });

    const result = await response.json();
    const aiText = result.choices?.[0]?.message?.content?.trim() || "";
    
    if (aiText.startsWith("EVET")) {
      const reason = aiText.split('|')[1]?.trim() || "Mesajını çok beğendi.";

      // Gerçekçilik için 2 ila 8 saniye bekle
      setTimeout(async () => {
        // Pick a random bot
        const { data: bots } = await supabase.from('users').select('id').eq('is_bot', true).limit(50);
        if (!bots || bots.length === 0) return;
        const bot = bots[Math.floor(Math.random() * bots.length)];

        // Insert suggestion for admin approval
        await supabase.from('bot_follow_suggestions').insert({
          bot_id: bot.id,
          target_user_id: message.user_id,
          reason: reason
        });
        
        console.log(`[💡 BOT SUGGESTION] Bot wants to follow ${user.username}. Reason: ${reason}`);
      }, Math.floor(Math.random() * 6000) + 2000);
    }
  } catch (err) {
    console.error("handleNewChatMessage Error:", err.message);
  }
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

      // C. Get Last 30 Messages for Context
      const { data: lastMessages } = await supabase
        .from('chat_messages')
        .select(`
          message,
          users ( username )
        `)
        .eq('match_id', match.id)
        .order('created_at', { ascending: false })
        .limit(30);

      let chatHistoryContext = "Şu an odada hiç mesaj yok, ilk sen yazıyorsun.";
      let memoryContext = "Ekstra bir kişisel hafızan veya anın yok.";

      if (lastMessages && lastMessages.length > 0) {
        chatHistoryContext = lastMessages.reverse().map(m => `[${m.users?.username || 'Bilinmiyor'}]: ${m.message}`).join('\n');
        
        // Use the most recent 5 messages as the query to find related memories
        const combinedRecentMessages = lastMessages.slice(-5).map(m => m.message).join(" ");
        
        if (generateEmbedding && combinedRecentMessages.trim() !== "") {
            try {
                const output = await generateEmbedding(combinedRecentMessages, { pooling: 'mean', normalize: true });
                const queryVector = Array.from(output.data);
                
                // Search pgvector for similar past interactions for this specific bot
                const { data: memories } = await supabase.rpc('match_bot_memories_global', {
                  query_embedding: queryVector,
                  match_threshold: 0.1, // Very low threshold to ensure matches
                  match_count: 2,
                  p_bot_id: bot.user_id
                });

                if (memories && memories.length > 0) {
                  memoryContext = "SENİN KİŞİSEL HAFIZAN (Geçmişte hatırladıkların):\n" + memories.map(m => `- ${m.content}`).join("\n");
                }
            } catch(e) {
                console.error("Vector Search Error:", e.message);
            }
        }
      }

      // D. Generate context-aware Chat Message via Gemini/OpenRouter
      const aiPrompt = `
Sen Türkçe konuşan fanatik bir futbol taraftarısın. 
Şu an canlı bir maç izliyorsun: ${match.home_team} vs ${match.away_team}. Skor: ${match.home_score}-${match.away_score}. Maç dakikası: ${match.minute}.
Senin tuttuğun takım: ${bot.team}.
Senin kişiliğin/karakterin: "${bot.persona_prompt}".
      
${memoryContext}

ODADAKİ SON KONUŞMALAR:
${chatHistoryContext}

Görevlerin:
1. Odadaki sohbete dahil ol. Gerekirse yukarıda konuşan kullanıcılara "@kullaniciadi" yazarak cevap ver, onlara sataş veya hak ver. Küfür etme ama trübün argosu serbest.
2. Asla robotik veya destan gibi uzun kelimeler kullanma. 'aynn', 'hoca naptın', 'abi', 'harbi' gibi sokak ağzı kullan.
3. Gerçekçi görünmek için BİLEREK ufak klavye harf hataları yap (typo, ö yerine o, mrb vs.).
4. ÇOK KISA, genellikle 1-2 kelime veya en fazla 1 kısa cümle yaz. 
5. Tırnak işareti, ekstra açıklama vb. kullanmadan direkt vereceğin mesajı yaz.`;

      let response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
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

      let result = await response.json();
      let messageContent = result.choices?.[0]?.message?.content?.trim() || "";
      
      // Fallback mechanism
      if (!messageContent) {
        console.log(`[DEBUG] Primary AI model failed, attempting fallback. Error:`, result.error?.message);
        response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${OPENROUTER_API_KEY}`,
            "Content-Type": "application/json"
          },
          body: JSON.stringify({
            "model": "google/gemma-2-9b-it:free",
            "messages": [{ "role": "user", "content": aiPrompt }]
          })
        });
        
        result = await response.json();
        messageContent = result.choices?.[0]?.message?.content?.trim() || "";
        if (!messageContent) {
            console.log(`[DEBUG] Fallback AI model also failed. Stopping retries for this tick.`);
            continue;
        }
      }

      // E. Insert into DB with Human Typing Delay (2 to 8 seconds)
      const typingDelay = Math.floor(Math.random() * 6000) + 2000;
      setTimeout(async () => {
        try {
          await supabase.from('chat_messages').insert({
            match_id: match.id,
            user_id: bot.user_id,
            message: messageContent,
            type: 'text'
          });
          console.log(`[CHAT] ${bot.team} botu (${bot.user_id.substring(0,8)}) ${typingDelay}ms bekleyip yazdı: ${messageContent}`);
        } catch(err) {
          console.error("Delayed chat insert error:", err);
        }
      }, typingDelay);
    }
  } catch (err) {
    console.error("simulateLiveChat Error:", err);
  }
}

// Keep track of fake ghost scores locally so they increment logically
const ghostScores = new Map(); 

async function simulateLeaderboards() {
  try {
    // 1. O an Admin panelinden başlatılmış (aktif) mini oyunları çek
    const { data: activeGames } = await supabase
      .from('active_mini_games')
      .select('*');

    if (!activeGames || activeGames.length === 0) return;

    // 2. Bu oyunların oynandığı maçları bul (home_team ve away_team için)
    const matchIds = activeGames.map(g => g.match_id);
    const { data: matches } = await supabase
      .from('matches')
      .select('id, home_team, away_team')
      .in('id', matchIds);

    if (!matches || matches.length === 0) return;

    // 3. Sadece bu maçları oynayan takımların botlarını getir
    const liveTeams = matches.flatMap(m => [m.home_team, m.away_team]);
    const { data: bots } = await supabase
      .from('bot_personas')
      .select('user_id, team')
      .in('team', liveTeams)
      .limit(100);

    if (!bots || bots.length === 0) return;

    // 4. Rastgele 3 bota kendi takımlarının aktif olduğu oyunda skor üret
    for (let i = 0; i < 3; i++) {
      const bot = bots[Math.floor(Math.random() * bots.length)];
      
      // Botun takımının bulunduğu maçı bul
      const matchForBot = matches.find(m => m.home_team === bot.team || m.away_team === bot.team);
      if (!matchForBot) continue;

      // O maç için adminin başlattığı tam oyun session IDsini (game_id) bul (coin dağıtımı için birebir eşleşmeli)
      // FIX: Ensure types match when comparing match_id since DB might return number for matches.id but we saved string in active_mini_games
      const activeGame = activeGames.find(g => String(g.match_id) === String(matchForBot.id));
      if (!activeGame) continue;
      
      const gameId = activeGame.game_id; // Orjinal benzersiz ID
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
        // Find existing score
        const { data: existing } = await supabase.from('mini_game_logs')
          .select('id').eq('user_id', bot.user_id).eq('game_id', gameId).maybeSingle();

        let errObj = null;
        if (existing) {
          const { error: err1 } = await supabase.from('mini_game_logs')
            .update({ score: currentScore, room_id: matchForBot.id, reward: 0 })
            .eq('id', existing.id);
          errObj = err1;
        } else {
          const { error: err2 } = await supabase.from('mini_game_logs')
            .insert({ user_id: bot.user_id, game_id: gameId, room_id: matchForBot.id, score: currentScore, reward: 0 });
          errObj = err2;
        }

        if (errObj) {
            console.error("[GAME DB ERROR]", errObj);
        } else {
            console.log(`[GAME] Bot ${bot.user_id.substring(0,8)} scored ${currentScore} in ${activeGame.game_type}`);
        }
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
// ----------------------------------------------------------------------
// EXPORTED MEMORY HELPER FOR FUTURE DM/FRIENDSHIP INTEGRATION
// ----------------------------------------------------------------------
async function handleNewPrivateMessage(payload) {
  try {
    const msg = payload.new;
    if (!msg || !msg.content) return;

    // Determine who else is in the room
    const { data: participants } = await supabase
      .from('chat_participants')
      .select('user_id, users!inner(username, is_bot)')
      .eq('room_id', msg.room_id);

    if (!participants || participants.length < 2) return;

    const sender = participants.find(p => p.user_id === msg.sender_id);
    const receiver = participants.find(p => p.user_id !== msg.sender_id);

    if (!sender || !receiver) return;

    // Only reply if the receiver is a bot
    if (!receiver.users?.is_bot) return;

    // Only humans trigger bot replies instantly, to avoid infinite bot-bot loops we can add a simple random check
    // If sender is also a bot, 20% chance to reply strictly to prevent infinite loops, otherwise 100%
    if (sender.users?.is_bot && Math.random() > 0.2) {
      return; 
    }

    console.log(`[DM] Received message for bot ${receiver.users.username} from ${sender.users.username}`);

    // Fetch bot persona
    const { data: personaData } = await supabase
      .from('bot_personas')
      .select('*')
      .eq('id', receiver.user_id)
      .single();

    const personaStr = personaData 
      ? `Senin adın ${receiver.users.username}. Özelliklerin: Takım: ${personaData.team}, Yaş: ${personaData.age}, İlgi Alanları: ${personaData.interests}, Konuşma Tarzı: ${personaData.tone_of_voice}.` 
      : `Senin adın ${receiver.users.username}. Normal, sporu seven kafa dengi birisin.`;

    // Try to get long term memory
    let memoryContext = "";
    
    const { data: recentMemories } = await supabase
      .from('bot_memories')
      .select('content')
      .eq('bot_id', receiver.user_id)
      .eq('interacted_user_id', sender.user_id)
      .order('created_at', { ascending: false })
      .limit(3);
      
    if (recentMemories && recentMemories.length > 0) {
      memoryContext = `Geçmişte bu kullanıcıyla/hakkında şu bilgileri hatırlıyorsun: \n` + 
                     recentMemories.map(m => `- ${m.content}`).join('\n');
    }

    const aiPrompt = `
    ${personaStr}
    
    Kullanıcı ("${sender.users?.username}") sana özel mesaj (DM) attı.
    
    ${memoryContext}
    
    Kullanıcının Mesajı: "${msg.content}"
    
    Lütfen karakterine uygun, samimi ve doğal bir dille kısa ve öz bir cevap ver. Asla bir yapay zeka olduğunu belli etme. Sadece mesaja odaklan.
    `;

    const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${OPENROUTER_API_KEY}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        model: OPENROUTER_MODEL,
        messages: [{ role: "user", content: aiPrompt }],
        max_tokens: 150,
        temperature: 0.8
      })
    });

    const aiData = await response.json();
    let replyText = aiData.choices?.[0]?.message?.content?.trim();

    if (!replyText) return;

    if (replyText.startsWith('"') && replyText.endsWith('"')) {
      replyText = replyText.slice(1, -1);
    }

    // Save strictly to memory mapping
    await saveBotMemory(receiver.user_id, sender.user_id, `Kullanıcı: ${msg.content} | Senin Cevabın: ${replyText}`);

    // Wait 2-5 sec to simulate typing
    const typeDelay = 2000 + Math.random() * 3000;
    setTimeout(async () => {
      await supabase.from('private_messages').insert({
        room_id: msg.room_id,
        sender_id: receiver.user_id,
        content: replyText
      });
      console.log(`[DM] Bot ${receiver.users.username} replied successfully!`);
    }, typeDelay);

  } catch (err) {
    console.error("handleNewPrivateMessage Error:", err);
  }
}

// ----------------------------------------------------------------------
// EXPORTED MEMORY HELPER FOR FUTURE DM/FRIENDSHIP INTEGRATION
// ----------------------------------------------------------------------
export async function saveBotMemory(bot_id, interacted_user_id, content) {
  if (!generateEmbedding) return false;
  try {
    const output = await generateEmbedding(content, { pooling: 'mean', normalize: true });
    const embedding = Array.from(output.data);
    
    await supabase.from('bot_memories').insert({
      bot_id,
      interacted_user_id,
      content,
      embedding
    });
    console.log(`[LTM] Bot memory saved for ${bot_id}`);
    return true;
  } catch(e) {
    console.error("Failed to save bot memory:", e);
    return false;
  }
}

runSimulation();
