// camera.exe 스토어 스크린샷: node render.js  → out/
const { chromium } = require('playwright');
const fs = require('fs');
(async () => {
  fs.mkdirSync(__dirname + '/out', { recursive: true });
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
  const jobs = [];
  for (let s = 1; s <= 6; s++) {
    jobs.push(['iphone', '', 440, 956, 3, s, `iphone-0${s}`]);      // 1320 x 2868 (6.9형)
    jobs.push(['iphone', '65', 428, 926, 3, s, `iphone65-0${s}`]);  // 1284 x 2778 (6.5형)
    jobs.push(['ipad', '', 1032, 1376, 2, s, `ipad-0${s}`]);        // 2064 x 2752 (13형)
    jobs.push(['play', '', 360, 640, 3, s, `play-0${s}`]);          // 1080 x 1920 (Google Play 폰)
  }
  for (const [dev, size, w, h, dpr, shot, name] of jobs) {
    const p = await b.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: dpr });
    await p.goto(`file://${__dirname}/shots.html?device=${dev}&size=${size}&shot=${shot}`);
    await p.evaluate(() => document.fonts.ready);
    await p.evaluate(() => Promise.all([...document.images].map(i => i.decode().catch(() => {}))));
    await p.waitForTimeout(100);
    await p.screenshot({ path: `${__dirname}/out/${name}.png`, clip: { x: 0, y: 0, width: w, height: h } });
    await p.close();
  }
  await b.close();
})();
