import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
dotenv.config();

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_KEY);
(async () => {
    // 1. Get the latest active game
    const { data: latestLog } = await supabase.from('mini_game_logs').select('*').order('created_at', { ascending: false }).limit(1).single();
    if (!latestLog) return console.log("No logs");
    
    console.log("Latest game_id:", latestLog.game_id);

    // 2. Run the exact query from the frontend
    const { data, error } = await supabase
        .from('mini_game_logs')
        .select('id, user_id, score, users(username)')
        .eq('game_id', latestLog.game_id)
        .order('score', { ascending: false })
        .limit(3);
        
    console.log("Query Error:", error);
    console.log("Query Result Length:", data ? data.length : 0);
    console.log("Query Data:", JSON.stringify(data, null, 2));

})();
