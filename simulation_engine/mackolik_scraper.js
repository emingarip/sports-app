import puppeteer from 'puppeteer';
import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';

dotenv.config();

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;

if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
  console.error("Missing SUPABASE environment variables.");
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

const MACKOLIK_POPULAR_URLS = [
    // This could dynamically scrape links from homepage, but since forum structures 
    // change, pointing to a few big recent matches (or deriving from recent pages) is enough
    // For automatic approach, we will scrape 'https://www.mackolik.com/' top games widget
    'https://www.mackolik.com/'
];

async function delay(ms) {
    return new Promise(res => setTimeout(res, ms));
}

async function runScraper() {
    console.log("🚀 Starting Mackolik Auto-Scraper...");
    let browser;
    try {
        browser = await puppeteer.launch({ 
            headless: "new",
            args: ['--no-sandbox', '--disable-setuid-sandbox', '--window-size=1280,800']
        });
        const page = await browser.newPage();
        await page.setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36');
        
        console.log(`Navigating to Mackolik Live Results Page...`);
        await page.goto('https://www.mackolik.com/canli-sonuclar', { waitUntil: 'domcontentloaded', timeout: 30000 });
        
        await delay(3000);

        // Find popular match links ending in '/' or without it, typical match URLs
        const matchLinks = await page.evaluate(() => {
            const links = Array.from(document.querySelectorAll('a[href*="/mac/"]'));
            return links.map(l => l.href).filter(href => !href.includes('/forum') && !href.includes('/kadro'));
        });

        // Deduplicate and get top matches (Fetch up to 30 matches to get backlogged data)
        let uniqueMatches = [...new Set(matchLinks)].slice(0, 30);
        
        if (uniqueMatches.length === 0) {
            console.log("No dynamic matches found. Using fallback legendary derbies...");
            uniqueMatches = [
                'https://www.mackolik.com/mac/galatasaray-vs-fenerbahce/7g1k0myow63t09n2x3k2cpeq8'
            ];
        }

        console.log(`Found ${uniqueMatches.length} popular matches. Starting extraction...`);

        let totalScraped = 0;

        for (const url of uniqueMatches) {
            // Convert /mac/teamA-vs-teamB/id to /mac/teamA-vs-teamB/forum/id
            const cleanUrl = url.endsWith('/') ? url.slice(0, -1) : url;
            const parts = cleanUrl.split('/');
            const id = parts.pop();
            const forumUrl = [...parts, 'forum', id].join('/');

            console.log(`\nVisiting: ${forumUrl}`);
            try {
                await page.goto(forumUrl, { waitUntil: 'domcontentloaded', timeout: 20000 });
                await delay(4000);

                // Scroll to load older comments from backlog
                for (let i = 0; i < 3; i++) {
                    await page.evaluate(() => window.scrollBy(0, document.body.scrollHeight));
                    await delay(2000);
                }

                // Extract comments via specific class without the author
                const rawTexts = await page.evaluate(() => {
                    const elements = Array.from(document.querySelectorAll('.single-comment__text'));
                    return elements.map(el => {
                        const clone = el.cloneNode(true);
                        const author = clone.querySelector('.single-comment__author');
                        if (author) author.remove();
                        return clone.innerText.trim();
                    });
                });

                // Clean and filter
                const cleaned = rawTexts.filter(text => {
                    if (!text || text.length < 5 || text.length > 250) return false;
                    const lower = text.toLowerCase();
                    if (lower.includes('eposta') || lower.includes('şifre') || lower.includes('üye') || lower.includes('mackolik') || lower.includes('bulunamadı')) return false;
                    return true;
                });
                
                const uniqueCleaned = [...new Set(cleaned)];
                
                if (uniqueCleaned.length > 0) {
                    console.log(`Extracted ${uniqueCleaned.length} potential comments.`);
                    
                    // Insert into DB
                    for(const c of uniqueCleaned) {
                        try {
                            const { error } = await supabase.from('mackolik_slang_pool').insert({
                                content: c,
                                match_id: forumUrl 
                            });
                            if (!error) totalScraped++;
                        } catch(dbErr) {
                            // Ignore unique errors if any
                        }
                    }
                } else {
                    console.log("No valid comments extracted here.");
                }

            } catch (pageErr) {
                console.error(`Skipping ${forumUrl} due to error:`, pageErr.message);
            }
        }
        
        console.log(`\n✅ Scraper finished successfully. Total new valid comments harvested: ${totalScraped}`);
        
    } catch (e) {
        console.error("Critical scraper error:", e);
    } finally {
        if (browser) await browser.close();
    }
}

export { runScraper };
