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
<li><b>Plan the week.</b> Every Sunday, fill in the week's plan page: priorities, weekly actions, and where each one lives on the calendar.</li>
<li><b>Run each day.</b> Each day has its own page: a top priority, up to five actions to check off, and morning and evening reflection questions.</li>
<li><b>Score the week.</b> The week's final page adds up your daily actions automatically (open the file in Acrobat or another full PDF reader). 85% or higher is a winning week.</li>
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

// weekly: plan page, 7 daily pages, review page
const DAYS=['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
const DQ=[ // [theme, morning question, evening question]
['Set the tone','What does a winning week look like, and what is the first move today?','Where did I start the week strong, and where did I drift?'],
['Hold the line','Where am I most tempted to cut a corner today, and how will I stop it?','Did I do the hard thing first? What got in the way?'],
['Midweek check','Am I on pace for the week? What has to change by Friday?','What am I avoiding, and what is the smallest step toward it?'],
['Stay on it','What is the one action today that moves my biggest goal?','What did I do today that I would do again? What would I drop?'],
['Finish strong','What must be finished before the weekend starts?','What is still open, and what will I do about it Monday?'],
['Whole life','What will I do today for my health, family or faith?','Who did I serve or show up for today?'],
['Reset','What carried over this week, and what do I drop for good?','What am I grateful for this week? What do I want next week to look like?']];
const nm=(n,tag)=>`data-n="${n}"`;
const fld=(n,extra='')=>`<div class="ln fld" data-n="${n}" ${extra}></div>`;
const dtf=()=>`<span class="fld di" style="width:34px"></span> / <span class="fld di" style="width:34px"></span> / <span class="fld di" style="width:50px"></span>`;
const calcBox=(label,calc,W,D)=>`<div class="cbx"><div class="cl">${label}</div><div class="fld calc" data-calc="${calc}" data-w="${W}" data-d="${D}" data-n="calc_${calc}_w${W}_d${D}"></div></div>`;
const mlf=(label,n,h,id)=>`<div class="lab">${label}</div><div class="fld ml nbx" data-n="${id}" style="height:${n*h}px"></div>`;
for(let w=1;w<=12;w++){
  // plan
  const acts=Array.from({length:6},(_,i)=>`<div class="acts"><span>${i+1}</span>${fld(`w${w}_plan_a${i+1}`)}</div>`).join('');
  pages.push(page(`<div class="wk"><div><div class="k">Week</div><div class="big">${String(w).padStart(2,'0')}</div></div><div class="wd">Week of ${dtf()}</div></div><div class="rule"></div>
<div class="lab">Top 3 priorities this week</div>${[1,2,3].map(i=>`<div class="acts"><span>${i}</span>${fld(`w${w}_pri${i}`)}</div>`).join('')}
<div class="lab" style="margin-top:14px">Weekly actions — what has to happen this week</div>${acts}
${mlf('Where does each action live on the calendar? (day and time)',4,36,`w${w}_cal`)}
${mlf('What could get in the way, and what is my plan for it?',3,36,`w${w}_obs`)}
<div class="callout" style="margin-top:14px">Log each day's actions on its daily page. Planned, completed and score fill in automatically on the week review.</div>`,`Week ${w} · Plan`));
  // days
  DAYS.forEach((dn,di)=>{
    const d=di+1,[theme,mq,eq]=DQ[di];
    const rows=Array.from({length:5},(_,i)=>`<div class="acts"><span class="fld chk box" data-n="w${w}_d${d}_c${i+1}">▢</span>${fld(`w${w}_d${d}_a${i+1}`)}</div>`).join('');
    pages.push(page(`<div class="wk"><div><div class="k">Week ${w} · Day ${di+1} · ${theme}</div><h2 style="margin-top:6px;font-size:40px">${dn}</h2></div><div class="wd">Date ${dtf()}</div></div><div class="rule"></div>
<div class="lab">Today's top priority</div>${fld(`w${w}_d${d}_pri`)}
<div class="lab" style="margin-top:14px">Today's actions — type each one, check it when done</div>${rows}
<div class="mini"><div>Planned ${calcBox('','planned',w,d)}</div><div>Done ${calcBox('','done',w,d)}</div></div>
${mlf('Morning — '+mq,2,34,`w${w}_d${d}_am`)}
${mlf('Evening — '+eq,3,30,`w${w}_d${d}_pm1`)}
${mlf('Biggest win today',2,26,`w${w}_d${d}_win`)}
${mlf('What I would do differently',2,26,`w${w}_d${d}_diff`)}
<div class="mini" style="margin-top:12px"><div><span class="fld chk box" data-n="w${w}_d${d}_word">▢</span> I kept my word today</div><div>Day rating (1–10) <span class="fld di" data-n="w${w}_d${d}_rate" style="width:40px"></span></div></div>`,`Week ${w} · ${dn}`));
  });
  // review
  const rowsR=DAYS.map((dn,di)=>`<tr><td class="n" style="width:110px;text-align:left;padding-left:8px">${dn}</td><td><div class="fld calc" data-calc="planned" data-w="${w}" data-d="${di+1}" data-n="rv_p_w${w}_d${di+1}"></div></td><td><div class="fld calc" data-calc="done" data-w="${w}" data-d="${di+1}" data-n="rv_d_w${w}_d${di+1}"></div></td><td><div class="fld calc" data-calc="score" data-w="${w}" data-d="${di+1}" data-n="rv_s_w${w}_d${di+1}"></div></td></tr>`).join('');
  pages.push(page(`<div class="wk"><div><div class="k">Week ${w} · Final page</div><h2 style="margin-top:6px;font-size:40px">Week ${w} review</h2></div></div><div class="rule"></div>
<div class="big3">${calcBox('Actions planned','planned',w,0)}${calcBox('Completed','done',w,0)}${calcBox('Score','score',w,0)}</div>
<table class="sct" style="margin-top:14px"><thead><tr><th class="al">Day</th><th>Planned</th><th>Done</th><th>Score</th></tr></thead><tbody>${rowsR}</tbody></table>
<div class="two2"><div>${mlf('What went well',3,36,`w${w}_rv_well`)}</div><div>${mlf('What got in the way',3,36,`w${w}_rv_way`)}</div></div>
${mlf('Am I closer to each goal? What moved?',2,36,`w${w}_rv_goal`)}
${mlf('One adjustment for next week',2,32,`w${w}_rv_adj`)}
<div class="mini" style="margin-top:12px"><div><span class="fld chk box" data-n="w${w}_rv_win">▢</span> Winning week (85%+)</div><div>Week rating (1–10) <span class="fld di" data-n="w${w}_rv_rate" style="width:40px"></span></div></div>`,`Week ${w} · Review`));
  if(w===6) pages.push(page(`${head('Midpoint check','Week 6 review')}
${box('Am I on track for each goal? Where am I vs. target?',5,30)}
${box('What\'s working that I should do more of?',3,30)}
${box('What needs to change for the second half?',4,30)}`));
}

// scorecard (auto)
const sc=Array.from({length:12},(_,i)=>`<tr><td class="n" style="width:70px;text-align:left;padding-left:8px">Week ${i+1}</td><td><div class="fld calc" data-calc="planned" data-w="${i+1}" data-d="0" data-n="sc_p_${i+1}"></div></td><td><div class="fld calc" data-calc="done" data-w="${i+1}" data-d="0" data-n="sc_d_${i+1}"></div></td><td><div class="fld calc" data-calc="score" data-w="${i+1}" data-d="0" data-n="sc_s_${i+1}"></div></td><td class="fld" data-n="sc_note_${i+1}"></td></tr>`).join('');
const tot=`<tr><td class="n" style="width:70px;text-align:left;padding-left:8px"><b>Total</b></td><td><div class="fld calc" data-calc="planned" data-w="0" data-d="0" data-n="sc_p_all"></div></td><td><div class="fld calc" data-calc="done" data-w="0" data-d="0" data-n="sc_d_all"></div></td><td><div class="fld calc" data-calc="score" data-w="0" data-d="0" data-n="sc_s_all"></div></td><td></td></tr>`;
pages.push(page(`${head('Track','12-week scorecard')}<table class="sct"><thead><tr><th class="al">Week</th><th>Planned</th><th>Done</th><th>Score</th><th class="al">Note</th></tr></thead><tbody>${sc}${tot}</tbody></table>
<div class="callout" style="margin-top:18px"><b>Target:</b> 85%+ each week. Planned, done and score fill in from your daily pages. A miss is data, not a verdict. Fix the plan and keep going.</div>`));

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
.cbx{text-align:center}.cbx .cl{font:600 10.5px 'IBM Plex Mono',monospace;letter-spacing:.08em;text-transform:uppercase;color:${MUTE}}.calc{border:1.5px solid ${INK};height:40px;background:#fbfaf7}.sct .calc{border:0;height:30px;background:none}.big3{display:grid;grid-template-columns:1fr 1fr 1fr;gap:18px}.big3 .calc{height:54px}
.mini{display:flex;gap:30px;align-items:center;font:600 11px 'IBM Plex Mono',monospace;text-transform:uppercase;color:${MUTE};margin-top:8px}.mini .cbx{display:inline-block;width:70px;vertical-align:middle;margin-left:6px}.mini .calc{height:24px}
.ft{position:absolute;left:.75in;right:.75in;bottom:.35in;display:flex;justify-content:space-between;font:500 9px 'IBM Plex Mono',monospace;color:${MUTE};letter-spacing:.08em;text-transform:uppercase}`;
const ff=(n,f,w,s='normal')=>`@font-face{font-family:'${n}';src:url(data:font/woff2;base64,${fs.readFileSync('../posts/fonts/'+f).toString('base64')});font-weight:${w};font-style:${s}}`;
const fonts=[ff('Inter','Inter-400-normal.woff2',400),ff('Inter','Inter-600-normal.woff2',600),ff('Inter','Inter-500-normal.woff2',500),ff('Oswald','Oswald-700-normal.woff2',700),ff('IBM Plex Mono','IBMPlexMono-400-normal.woff2',500),ff('IBM Plex Mono','IBMPlexMono-600-normal.woff2',600),ff('Lora','Lora-500-italic.woff2',500,'italic')].join('');
const html=`<!doctype html><meta charset=utf8><style>${fonts}${css}</style>${pages.join('')}`;
fs.writeFileSync('planner.html',html);
const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});const p=await b.newPage();
await p.setContent(html);await p.evaluate(()=>document.fonts.ready);
const rects=await p.evaluate(()=>[...document.querySelectorAll('.pg')].map((pg,i)=>{const o=pg.getBoundingClientRect();return [...pg.querySelectorAll('.fld')].map(e=>{const r=e.getBoundingClientRect();return {n:e.dataset.n||null,calc:e.dataset.calc||null,w0:+(e.dataset.w||0),d0:+(e.dataset.d||0),cb:e.classList.contains("chk"),ml:e.classList.contains('ml'),x:r.x-o.x,y:r.y-o.y,w:r.width,h:r.height,cover:i===0}})}));
fs.writeFileSync('fields.json',JSON.stringify(rects));
await p.pdf({path:'12-week-goal-planner.pdf',width:'8.5in',height:'11in',printBackground:true});await b.close();
