import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
import * as fs from 'fs';
dotenv.config();

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_KEY);
(async () => {
    const { data } = await supabase.from('matches').select('*').limit(1);
    fs.writeFileSync("columns.json", JSON.stringify(data ? Object.keys(data[0]) : 'no data', null, 2), "utf8");
})();
