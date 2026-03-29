import fs from 'fs';
import path from 'path';

const gamesDir = path.join('d:', 'Projects', 'SportsApp', 'sports_games_web', 'src', 'games');
const games = fs.readdirSync(gamesDir).filter(f => f.endsWith('.tsx'));

for (const game of games) {
    const filePath = path.join(gamesDir, game);
    let content = fs.readFileSync(filePath, 'utf8');

    // This matches the one-liner or multi-liner setTopScores array map for leaderboards
    const searchRegex = /if\s*\(data\)\s*setTopScores\(data\.map\(\(d:\s*any\)\s*=>\s*\(\{\s*id:\s*d\.id,\s*score:\s*d\.score,\s*username:\s*d\.users\?\.username\s*\|\|\s*'Anonim'\s*\}\)\)\);/s;
      
    const replaceWith = `if (data) {
        // Resolve bot usernames for 'Anonim' entries
        const anonIds = data.filter((d: any) => !d.users?.username).map((d: any) => d.user_id);
        let botLogos: Record<string, string> = {};
        if (anonIds.length > 0) {
            const { data: bots } = await supabase.from('bot_personas').select('user_id, username').in('user_id', anonIds);
            if (bots) {
                bots.forEach((b: any) => { botLogos[b.user_id] = b.username; });
            }
        }

        setTopScores(data.map((d: any) => ({
          id: d.id,
          score: d.score,
          username: d.users?.username || botLogos[d.user_id] || 'Anonim'
        })));
      }`;
      
    if (searchRegex.test(content)) {
        content = content.replace(searchRegex, replaceWith);
        fs.writeFileSync(filePath, content, 'utf8');
        console.log("Updated", game);
    } else {
        console.log("Not found in", game);
    }
}
