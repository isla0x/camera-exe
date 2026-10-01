const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
  const p = await b.newPage({ viewport: { width: 1024, height: 500 } });
  await p.goto(`file://${__dirname}/feature.html`);
  await p.evaluate(() => document.fonts.ready); await p.waitForTimeout(150);
  await p.screenshot({ path: `${__dirname}/out/feature-1024x500.png` });
  await b.close();
})();
