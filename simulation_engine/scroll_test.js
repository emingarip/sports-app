import puppeteer from 'puppeteer';

(async () => {
    const browser = await puppeteer.launch({ headless: true });
    const page = await browser.newPage();
    const url = 'https://www.mackolik.com/canli-sonuclar';
    
    await page.goto(url, { waitUntil: 'domcontentloaded' });
    await new Promise(r => setTimeout(r, 2000));
    
    const prevDateUrls = await page.evaluate(() => {
        const links = Array.from(document.querySelectorAll('a'));
        return links.filter(l => l.innerText.includes('<') || l.className.includes('prev')).map(l => l.href);
    });
    
    console.log(prevDateUrls);
    await browser.close();
})();
