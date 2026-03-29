import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
dotenv.config();

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_KEY);
(async () => {
    // 1. Get a bot
    const { data: bot } = await supabase.from('bot_personas').select('user_id').limit(1).single();
    
    // 2. Try to insert it into mini_game_logs
    const { error } = await supabase.from('mini_game_logs').insert({
        user_id: bot.user_id,
        game_id: 'test_game_123',
        score: 10
    });
    
    console.log("Insert Error:", error);
})();
