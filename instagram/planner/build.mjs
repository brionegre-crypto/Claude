import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
import fs from 'fs';
const A='#C97A12', INK='#141416', MUTE='#6f6a62';
const lines=(n,h=30,f=' fld')=>Array.from({length:n},()=>`<div class="ln${f}" style="height:${h}px"></div>`).join('');
const box=(label,n,h)=>`<div class="lab">${label}</div><div class="fld ml nbx" style="height:${n*h}px"></div>`;
const page=(inner,foot='')=>`<section class="pg">${inner}<div class="ft"><span>12-Week Goal Planner</span><span>${foot}</span></div></section>`;
const head=(k,t)=>`<div class="k">${k}</div><h2>${t}</h2><div class="rule"></div>`;

let pages=[];
pages.push(`<section class="pg cover"><div class="cb"><div class="k">Plan it. Run it. Review it.</div><h1>12-Week<br>Goal Planner</h1><div class="rule w"></div><p>Twelve weeks is long enough to change something and short enough to stay serious. Pick a few goals, define the weekly actions that drive them, and review every week.</p><div class="nm">Name: <span class="fld di" style="width:300px"></span></div><div class="nm">Start: <span class="fld di" style="width:30px"></span> / <span class="fld di" style="width:30px"></span> / <span class="fld di" style="width:46px"></span> &nbsp;&nbsp; End: <span class="fld di" style="width:30px"></span> / <span class="fld di" style="width:30px"></span> / <span class="fld di" style="width:46px"></span></div></div></section>`);

pages.push(page(`${head('Start here','How to use this planner')}
<ol class="how">
<li><b>Pick 1–3 goals.</b> Fewer is better. Each must be measurable and have a finish line inside 12 weeks.</li>
<li><b>Break each goal into weekly actions.</b> Things you control: the workouts, the calls, the pages written — not the outcome.</li>
<li><b>Set the week.</b> Every Sunday, fill in the weekly page: top priorities, the day and time each action happens.</li>
<li><b>Score yourself.</b> Divide actions completed by actions planned. 85% or higher is a winning week.</li>
<li><b>Review honestly.</b> Name what worked, what didn't, and one adjustment for next week.</li>
<li><b>Finish with the 12-week review.</b> Then pick the next 12 weeks.</li></ol>
<div class="callout"><b>Rule of thumb:</b> if the week didn't happen on the calendar, it didn't happen. Put every action on a specific day and time.</div>`));

pages.push(page(`${head('Step 1','Vision & why')}
${box('Where do I want to be in 12 weeks?',5,34)}
${box('Why does this matter? What does it cost me if I don\'t do it?',5,34)}
${box('What could get in the way, and what will I do about it?',4,34)}`));

const goal=n=>`<div class="goal"><div class="gh">Goal ${n}</div>
<div class="row"><div class="lab">Goal (specific and measurable)</div><div class="ln fld"></div></div>
<div class="row two"><div><div class="lab">Starting point</div><div class="ln fld"></div></div><div><div class="lab">Target by week 12</div><div class="ln fld"></div></div></div>
<div class="lab">Weekly actions that drive it</div>
<div class="acts"><span class="fld chk box">▢</span><div class="ln fld"></div></div><div class="acts"><span class="fld chk box">▢</span><div class="ln fld"></div></div><div class="acts"><span class="fld chk box">▢</span><div class="ln fld"></div></div></div>`;
pages.push(page(`${head('Step 2','My 12-week goals')}${goal(1)}${goal(2)}${goal(3)}`));

// milestone map
const ms=[[1,4],[5,8],[9,12]].map(([a,b])=>`<div class="ms"><div class="gh">Weeks ${a}–${b}</div><div class="lab">What must be true by the end of week ${b}?</div>${lines(3,28)}</div>`).join('');
pages.push(page(`${head('Step 3','Milestones')}${ms}`));

// weekly
for(let w=1;w<=12;w++){
  const days=['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
  const rows=Array.from({length:6},(_,i)=>`<tr><td class="n">${i+1}</td><td class="act fld"></td>${days.map(()=>'<td class="c fld chk"></td>').join('')}</tr>`).join('');
  pages.push(page(`<div class="wk"><div><div class="k">Week</div><div class="big">${String(w).padStart(2,'0')}</div></div><div class="wd">Week of <span class="fld di" style="width:34px"></span> / <span class="fld di" style="width:34px"></span> / <span class="fld di" style="width:50px"></span></div></div><div class="rule"></div>
<div class="lab">Top 3 priorities this week</div><div class="acts"><span>1</span><div class="ln fld"></div></div><div class="acts"><span>2</span><div class="ln fld"></div></div><div class="acts"><span>3</span><div class="ln fld"></div></div>
<div class="lab" style="margin-top:14px">Weekly actions — mark each day done</div>
<table><thead><tr><th></th><th class="al">Action (with day &amp; time)</th>${days.map(d=>`<th>${d}</th>`).join('')}</tr></thead><tbody>${rows}</tbody></table>
<div class="score"><div>Actions planned <i class="fld"></i></div><div>Completed <i class="fld"></i></div><div>Score % <i class="fld"></i></div></div>
<div class="two2"><div>${box('What went well',3,44)}</div><div>${box('What got in the way',3,44)}</div></div>
${box('One adjustment for next week',2,44)}`,`Week ${w}`));
  if(w===6) pages.push(page(`${head('Midpoint check','Week 6 review')}
${box('Am I on track for each goal? Where am I vs. target?',5,30)}
${box('What\'s working that I should do more of?',3,30)}
${box('What needs to change for the second half?',4,30)}`));
}

// scorecard
const sc=Array.from({length:12},(_,i)=>`<tr><td class="n">Week ${i+1}</td><td class="fld"></td><td class="fld"></td><td class="fld"></td><td class="fld"></td></tr>`).join('');
pages.push(page(`${head('Track','Weekly scorecard')}<table class="sct"><thead><tr><th class="al">Week</th><th>Planned</th><th>Done</th><th>Score %</th><th class="al">Note</th></tr></thead><tbody>${sc}</tbody></table>
<div class="callout" style="margin-top:18px"><b>Target:</b> 85%+ each week. A miss is data, not a verdict. Fix the plan and keep going.</div>`));

pages.push(page(`${head('Finish','12-week review')}
${box('Results: where did I land on each goal?',4,30)}
${box('Biggest wins',3,30)}
${box('Biggest lessons',3,30)}
${box('What I\'ll carry into the next 12 weeks',3,30)}
<div class="lab" style="margin-top:12px">Next 12 weeks starts: <span class="fld di" style="width:34px"></span> / <span class="fld di" style="width:34px"></span> / <span class="fld di" style="width:50px"></span></div>`));

const css=`@page{size:Letter;margin:0}*{box-sizing:border-box}body{margin:0;font-family:Inter,sans-serif;color:${INK}}
.pg{width:8.5in;height:11in;padding:.7in .75in .6in;position:relative;page-break-after:always;overflow:hidden}
.k{font:600 10px 'IBM Plex Mono',monospace;letter-spacing:.18em;text-transform:uppercase;color:${A}}
h1{font:700 64px/1.02 Oswald,sans-serif;text-transform:uppercase;margin:14px 0 0}h2{font:700 34px Oswald,sans-serif;text-transform:uppercase;margin:6px 0 0}
.rule{height:3px;width:60px;background:${A};margin:14px 0 22px}.rule.w{margin:26px 0}
.cover{background:${INK};color:#F2EEE6;padding:0}.cb{position:absolute;left:.9in;right:.9in;top:2.6in}.cover p{font:500 italic 17px/1.6 Lora,serif;color:#BFBCB6;max-width:5.2in}
.nm{margin-top:34px;font:500 13px 'IBM Plex Mono',monospace;color:#F2EEE6}
.lab{font:600 10.5px 'IBM Plex Mono',monospace;letter-spacing:.08em;text-transform:uppercase;color:${MUTE};margin:16px 0 2px}
.ln{border-bottom:1px solid #bdb8ae;height:30px;width:100%}
.how{padding-left:20px;font-size:14px;line-height:1.55}.how li{margin-bottom:12px}
.callout{border-left:4px solid ${A};background:#f6f1e7;padding:14px 16px;font-size:13.5px;line-height:1.5;margin-top:24px}
.goal{border:1.5px solid ${INK};padding:8px 16px 6px;margin-bottom:12px}.goal .ln{height:24px}.goal .lab{margin:8px 0 0}.goal .acts .ln{height:24px}.goal .acts span{line-height:24px}.gh{font:700 15px Oswald,sans-serif;text-transform:uppercase;letter-spacing:.06em;color:${A}}
.two{display:grid;grid-template-columns:1fr 1fr;gap:20px}.acts{display:flex;align-items:flex-end;gap:8px}.acts span{font-size:14px;color:${MUTE};line-height:28px}.acts .ln{height:28px}
.ms{border:1.5px solid ${INK};padding:12px 16px 12px;margin-bottom:18px}
.wk{display:flex;justify-content:space-between;align-items:flex-end}.big{font:700 54px/1 Oswald,sans-serif}.wd{font:500 12px 'IBM Plex Mono',monospace}
table{width:100%;border-collapse:collapse;margin-top:6px}th{font:600 9px 'IBM Plex Mono',monospace;text-transform:uppercase;color:${MUTE};padding:4px 2px;text-align:center}th.al{text-align:left}
td{border:1px solid #bdb8ae;height:34px}td.n{width:24px;text-align:center;font-size:11px;color:${MUTE}}td.c{width:36px}
.score{display:flex;gap:24px;margin:14px 0 4px;font:600 10.5px 'IBM Plex Mono',monospace;text-transform:uppercase;color:${MUTE}}.score i{display:inline-block;width:60px;border-bottom:1px solid ${INK};margin-left:6px;height:14px}
.two2{display:grid;grid-template-columns:1fr 1fr;gap:24px}
.sct td{height:36px}.sct td.n{width:70px;text-align:left;padding-left:8px;font-size:12px}
.nbx{border:1px solid #bdb8ae;background:#fbfaf7;margin-top:4px}.di{display:inline-block;border-bottom:1px solid currentColor;height:14px;vertical-align:bottom}.box{font-size:14px}
.ft{position:absolute;left:.75in;right:.75in;bottom:.35in;display:flex;justify-content:space-between;font:500 9px 'IBM Plex Mono',monospace;color:${MUTE};letter-spacing:.08em;text-transform:uppercase}`;
const ff=(n,f,w,s='normal')=>`@font-face{font-family:'${n}';src:url(data:font/woff2;base64,${fs.readFileSync('../posts/fonts/'+f).toString('base64')});font-weight:${w};font-style:${s}}`;
const fonts=[ff('Inter','Inter-400-normal.woff2',400),ff('Inter','Inter-600-normal.woff2',600),ff('Inter','Inter-500-normal.woff2',500),ff('Oswald','Oswald-700-normal.woff2',700),ff('IBM Plex Mono','IBMPlexMono-400-normal.woff2',500),ff('IBM Plex Mono','IBMPlexMono-600-normal.woff2',600),ff('Lora','Lora-500-italic.woff2',500,'italic')].join('');
const html=`<!doctype html><meta charset=utf8><style>${fonts}${css}</style>${pages.join('')}`;
fs.writeFileSync('planner.html',html);
const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});const p=await b.newPage();
await p.setContent(html);await p.evaluate(()=>document.fonts.ready);
const rects=await p.evaluate(()=>[...document.querySelectorAll('.pg')].map((pg,i)=>{const o=pg.getBoundingClientRect();return [...pg.querySelectorAll('.fld')].map(e=>{const r=e.getBoundingClientRect();return {cb:e.classList.contains("chk"),ml:e.classList.contains('ml'),x:r.x-o.x,y:r.y-o.y,w:r.width,h:r.height,cover:i===0}})}));
fs.writeFileSync('fields.json',JSON.stringify(rects));
await p.pdf({path:'12-week-goal-planner.pdf',width:'8.5in',height:'11in',printBackground:true});await b.close();
