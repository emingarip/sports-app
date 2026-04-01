import puppeteer from 'puppeteer';

(async () => {
  const browser = await puppeteer.launch({ headless: "new" });
  const page = await browser.newPage();
  
  page.on('response', async (response) => {
    const url = response.url();
    if (url.includes('comment') || url.includes('forum') || url.includes('msg')) {
      console.log('Found API:', url);
    }
  });

  await page.goto('https://www.mackolik.com/mac/galatasaray-vs-sivasspor/4z90nxyq4xyt7f6t3z9qy1u10/forum', { waitUntil: 'networkidle2' });
  
  await new Promise(r => setTimeout(r, 5000));
  console.log("Done waiting");
  
  await browser.close();
})();
