const fs=require('fs'),assert=require('assert');
const html=fs.readFileSync('Assets/ContactMap.html','utf8');
const fn=html.slice(html.indexOf('function gridCenter('),html.indexOf('\nconst svg='));
eval(fn);
assert.deepStrictEqual(gridCenter('AA00'),[-179,-89.5]);
assert.deepStrictEqual(gridCenter('RR99'),[179,89.5]);
assert.deepStrictEqual(gridCenter('FN42'),[-71,42.5]);
for(const g of ['AA00AA','AA00AA00','RR99XX99','FM18FW']){const p=gridCenter(g);assert(p&&p[0]>=-180&&p[0]<=180&&p[1]>=-90&&p[1]<=90)}
for(const g of ['','ZZ99','FN4','FN42<script>','FN42ZZ','FN42AB123'])assert.strictEqual(gridCenter(g),null);
assert(html.includes("connect-src 'none'"));assert(!/<(?:script|link)[^>]+(?:src|href)=/i.test(html));
assert(html.includes('text.textContent=c.call')&&html.includes('button.textContent='));
assert(html.includes('data-theme="CP"')&&html.includes('data-theme="Crimson"'));
assert(!html.includes('innerHTML'));
console.log('PASS: Maidenhead 4/6/8-character centers, invalid-grid rejection, offline map, safe callsign labels and all map themes');
