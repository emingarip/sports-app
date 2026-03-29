import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
import * as fs from 'fs';
dotenv.config();

const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_KEY);
(async () => {
    // query information_schema.tables
    const response = await fetch(`${process.env.SUPABASE_URL}/rest/v1/?apikey=${process.env.SUPABASE_SERVICE_KEY}`);
    const swagger = await response.json();
    fs.writeFileSync("tables.json", JSON.stringify(Object.keys(swagger.definitions), null, 2), "utf8");
    console.log("Written");
})();
