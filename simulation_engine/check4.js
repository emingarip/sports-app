import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
dotenv.config();

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_KEY);
(async () => {
    // get a bot
    const { data: bot } = await supabase.from('bot_personas').select('user_id, username').limit(1).single();
    if (!bot) return console.log("No bots");
    
    // check if this bot is in public.users
    const { data: user } = await supabase.from('users').select('*').eq('id', bot.user_id).single();
    if (user) {
       console.log("Bot IS in users table:", user.username);
    } else {
       console.log("Bot is NOT in users table. It only exists in bot_personas.");
    }
})();
