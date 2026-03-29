import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
dotenv.config();

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_KEY);
(async () => {
    // try removing onConflict
    const bot_id = 'c4c01f66-22c6-4860-84a1-bdfc3d699566'; // replace with a safe ID or just select one
    const { data: bot } = await supabase.from('bot_personas').select('user_id').limit(1).single();
    if (!bot) return;

    // First try a select
    const { data: existing } = await supabase.from('mini_game_logs').select('id, score').eq('user_id', bot.user_id).eq('game_id', 'testgame_123').single();
    if (existing) {
       console.log("Existing log ID:", existing.id);
    } else {
       console.log("No existing log for testgame_123");
    }
})();
