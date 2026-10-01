// .exe 시리즈 앱 아이콘 (05 / MONO CURSOR): >  + 앱 첫 글자 + 색 커서.
// 다시 그리기: node design/icons/make-mono-cursor.js  (playwright 필요)
//   → design/icons/<앱>.png, <앱>-fg.png 가 생긴다. 이 앱 것을 assets/icon/icon.png, icon-foreground.png 로 복사하고
//     dart run flutter_launcher_icons
const { chromium } = require('playwright'); const fs = require('fs');
const apps = { diary: ['d', '#FDDA62'], todo: ['t', '#6ED285'], ink: ['i', '#8DECFE'], camera: ['c', '#F45B52'] };
const font = fs.readFileSync(__dirname + '/../../assets/fonts/JetBrainsMono-Bold.ttf').toString('base64');
function svg(letter, color, bg) {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
${bg ? '<rect width="1024" height="1024" fill="#191918"/>' : ''}
<polyline points="168,424 298,525 168,626" fill="none" stroke="#777775" stroke-width="58" stroke-linejoin="miter" stroke-linecap="butt"/>
<text x="508" y="706" text-anchor="middle" font-family="JBM" font-weight="700" font-size="398" fill="#F6F4EE">${letter}</text>
<rect x="707" y="487" width="150" height="219" fill="${color}"/>
</svg>`;
}
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
  const p = await b.newPage({ viewport: { width: 1024, height: 1024 } });
  for (const [name, [letter, color]] of Object.entries(apps)) {
    for (const bg of [true, false]) {
      const s = svg(letter, color, bg);
      await p.setContent(`<html><head><style>@font-face{font-family:JBM;src:url(data:font/ttf;base64,${font});font-weight:700}</style></head><body style="margin:0;background:transparent">${s}</body></html>`);
      await p.evaluate(() => document.fonts.ready);
      await p.waitForTimeout(100);
      await p.screenshot({ path: `${__dirname}/${name}${bg ? '' : '-fg'}.png`, omitBackground: !bg, clip: { x: 0, y: 0, width: 1024, height: 1024 } });
      // 원본 SVG (글자는 글꼴 이름만: 다시 그릴 때 make.js 를 쓴다)
      if (bg) fs.writeFileSync(`${__dirname}/${name}.svg`, s);
    }
  }
  await b.close();
})();
