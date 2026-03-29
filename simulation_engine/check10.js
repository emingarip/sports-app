import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
dotenv.config();

// USE ANON KEY to simulate frontend
const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_ANON_KEY || 'MISSING');
(async () => {
    // 1. Get the latest active game
    const supabaseAdmin = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_KEY);
    const { data: latestLog } = await supabaseAdmin.from('mini_game_logs').select('*').order('created_at', { ascending: false }).limit(1).single();
    if (!latestLog) return console.log("No logs");
    
    // 2. Run the exact query from the frontend using ANON key
    const { data, error } = await supabase
        .from('mini_game_logs')
        .select('id, user_id, score, users(username)')
        .eq('game_id', latestLog.game_id)
        .order('score', { ascending: false })
        .limit(3);
        
    console.log("ANON Query Error:", error);
    console.log("ANON Query Result Length:", data ? data.length : 0);
    console.log("ANON Query Data:", JSON.stringify(data, null, 2));

})();
