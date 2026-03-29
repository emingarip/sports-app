import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
dotenv.config();

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_KEY);
(async () => {
    const { error } = await supabase.from('active_mini_games').delete().neq('id', '00000000-0000-0000-0000-000000000000');
    console.log("Database active games successfully wiped clean. Error:", error);
})();
