import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
dotenv.config();

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_KEY);
(async () => {
    const { data } = await supabase.from('matches').select('*').limit(1);
    console.log(data ? Object.keys(data[0]) : 'no data');
})();
