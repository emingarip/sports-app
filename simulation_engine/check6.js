import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
dotenv.config();

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_KEY);
(async () => {
    const { data: activeGames } = await supabase.from('active_mini_games').select('*');
    if (!activeGames || activeGames.length === 0) {
        return console.log("No active games.");
    }
    const currentActiveGameId = activeGames[0].game_id;
    console.log("Current active game_id:", currentActiveGameId);

    const { data: logs } = await supabase.from('mini_game_logs').select('*, users(username)').eq('game_id', currentActiveGameId);
    console.log("Mini game logs length:", logs ? logs.length : 0);
    console.log(logs);

    if (logs && logs.length > 0) {
        // check bot personas for these users
        const anonIds = logs.filter(l => !l.users?.username).map(l => l.user_id);
        console.log("Anon IDs:", anonIds);
        if (anonIds.length > 0) {
            const { data: bots } = await supabase.from('bot_personas').select('user_id, username').in('user_id', anonIds);
            console.log("Matching bots:", bots);
        }
    }
})();
