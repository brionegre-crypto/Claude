import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
import fs from 'fs';
const A='#C97A12', INK='#141416', MUTE='#6f6a62';
const lines=(n,h=30,f=' fld')=>Array.from({length:n},()=>`<div class="ln${f}" style="height:${h}px"></div>`).join('');
const box=(label,n,h,id='')=>`<div class="lab">${label}</div><div class="fld ml nbx" ${id?`data-n="${id}"`:''} style="height:${n*h}px"></div>`;
const page=(inner,foot='',cls='')=>`<section class="pg ${cls}">${inner}<div class="ft"><span>12-Week Goal Planner</span><span>${foot}</span></div></section>`;
const head=(k,t)=>`<div class="k">${k}</div><h2>${t}</h2><div class="rule"></div>`;

let pages=[];
pages.push(`<section class="pg cover"><div class="cb"><div class="k">Plan it. Run it. Review it.</div><h1>12-Week<br>Goal Planner</h1><div class="rule w"></div><p>Twelve weeks is long enough to change something and short enough to stay serious. Pick a few goals, define the weekly actions that drive them, and review every week.</p><div class="nm">Name: <span class="fld di" data-n="cover_name" style="width:300px"></span></div><div class="nm">Start: <span class="fld di" data-n="cover_s_m" style="width:30px"></span> / <span class="fld di" data-n="cover_s_d" style="width:30px"></span> / <span class="fld di" data-n="cover_s_y" style="width:46px"></span> &nbsp;&nbsp; End: <span class="fld di" data-n="cover_e_m" style="width:30px"></span> / <span class="fld di" data-n="cover_e_d" style="width:30px"></span> / <span class="fld di" data-n="cover_e_y" style="width:46px"></span></div></div></section>`);

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
${box('Where do I want to be in 12 weeks?',5,34,'vis_where')}
${box('Why does this matter? What does it cost me if I don\'t do it?',5,34,'vis_why')}
${box('What could get in the way, and what will I do about it?',4,34,'vis_obs')}`));

const goal=n=>`<div class="goal"><div class="gh">Goal ${n}</div>
<div class="row"><div class="lab">Goal (specific and measurable)</div><div class="ln fld" data-n="g${n}_goal"></div></div>
<div class="row two"><div><div class="lab">Starting point</div><div class="ln fld" data-n="g${n}_start"></div></div><div><div class="lab">Target by week 12</div><div class="ln fld" data-n="g${n}_target"></div></div></div>
<div class="lab">Weekly actions that drive it</div>
${[1,2,3].map(i=>`<div class="acts"><span class="fld chk box" data-n="g${n}_c${i}">▢</span><div class="ln fld" data-n="g${n}_a${i}"></div></div>`).join('')}</div>`;
pages.push(page(`${head('Step 2','My 12-week goals')}${goal(1)}${goal(2)}${goal(3)}`));

// milestone map
const ms=[[1,4],[5,8],[9,12]].map(([a,b])=>`<div class="ms"><div class="gh">Weeks ${a}–${b}</div><div class="lab">What must be true by the end of week ${b}?</div>${[1,2,3].map(j=>`<div class="ln fld" data-n="ms${a}_${j}" style="height:28px"></div>`).join('')}</div>`).join('');
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
const dtf=(id)=>`<span class="fld di" ${id?`data-n="${id}_m"`:''} style="width:34px"></span> / <span class="fld di" ${id?`data-n="${id}_d"`:''} style="width:34px"></span> / <span class="fld di" ${id?`data-n="${id}_y"`:''} style="width:50px"></span>`;
const calcBox=(label,calc,W,D)=>`<div class="cbx"><div class="cl">${label}</div><div class="fld calc" data-calc="${calc}" data-w="${W}" data-d="${D}" data-n="calc_${calc}_w${W}_d${D}"></div></div>`;
const mlf=(label,n,h,id)=>`<div class="lab">${label}</div><div class="fld ml nbx" data-n="${id}" style="height:${n*h}px"></div>`;
for(let w=1;w<=12;w++){
  // plan
  const acts=Array.from({length:6},(_,i)=>`<div class="acts"><span>${i+1}</span>${fld(`w${w}_plan_a${i+1}`)}</div>`).join('');
  pages.push(page(`<div class="wk"><div><div class="k">Week</div><div class="big">${String(w).padStart(2,'0')}</div></div><div class="wd">Week of ${dtf(`w${w}_wk`)}</div></div><div class="rule"></div>
<div class="lab">Top 3 priorities this week</div>${[1,2,3].map(i=>`<div class="acts"><span>${i}</span>${fld(`w${w}_pri${i}`)}</div>`).join('')}
<div class="lab" style="margin-top:14px">Weekly actions — what has to happen this week</div>${acts}
${mlf('Where does each action live on the calendar? (day and time)',4,36,`w${w}_cal`)}
${mlf('What could get in the way, and what is my plan for it?',3,36,`w${w}_obs`)}
<div class="callout" style="margin-top:14px">Log each day's actions on its daily page. Planned, completed and score fill in automatically on the week review.</div>`,`Week ${w} · Plan`));
  // days
  DAYS.forEach((dn,di)=>{
    const d=di+1,[theme,mq,eq]=DQ[di];
    const rows=Array.from({length:5},(_,i)=>`<div class="acts"><span class="fld chk box" data-n="w${w}_d${d}_c${i+1}">▢</span>${fld(`w${w}_d${d}_a${i+1}`)}</div>`).join('');
    const gm=(label,id,fl)=>`<div class="grow" style="flex:${fl}"><div class="lab">${label}</div><div class="fld ml nbx" data-n="${id}" style="flex:1"></div></div>`;
    pages.push(page(`<div class="wk"><div><div class="k">Week ${w} · Day ${di+1} · ${theme}</div><h2 style="margin-top:6px;font-size:40px">${dn}</h2></div><div class="wd">Date ${dtf(`w${w}_d${d}_dt`)}</div></div><div class="rule" style="margin:10px 0 6px"></div>
${gm("Today's vision — who am I being, and what does a great day look like?",`w${w}_d${d}_vis`,1)}
${gm("Today's goal — the one outcome that makes today a win",`w${w}_d${d}_goal`,1)}
<div class="lab" style="margin-top:8px">Today's top priority</div>${fld(`w${w}_d${d}_pri`)}
<div class="lab" style="margin-top:8px">Today's actions — type each one, check it when done</div>${rows}
<div class="mini"><div>Planned ${calcBox('','planned',w,d)}</div><div>Done ${calcBox('','done',w,d)}</div></div>
${gm('Morning — '+mq,`w${w}_d${d}_am`,1.2)}
${gm('Evening — '+eq,`w${w}_d${d}_pm1`,1.8)}
${gm('Biggest win today',`w${w}_d${d}_win`,1)}
${gm('What I would do differently',`w${w}_d${d}_diff`,1)}
<div class="mini" style="margin-top:10px"><div><span class="fld chk box" data-n="w${w}_d${d}_word">▢</span> I kept my word today</div><div>Day rating (1–10) <span class="fld di" data-n="w${w}_d${d}_rate" style="width:40px"></span></div></div>`,`Week ${w} · ${dn}`,'day'));
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
<div class="lab" style="margin-top:12px">Next 12 weeks starts: <span class=\"fld di\" data-n=\"next_m\" style=\"width:34px\"></span> / <span class=\"fld di\" data-n=\"next_d\" style=\"width:34px\"></span> / <span class=\"fld di\" data-n=\"next_y\" style=\"width:50px\"></span></div>`));

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
.pg.day{display:flex;flex-direction:column}.grow{display:flex;flex-direction:column;min-height:46px;margin-top:2px}
.ft{position:absolute;left:.75in;right:.75in;bottom:.35in;display:flex;justify-content:space-between;font:500 9px 'IBM Plex Mono',monospace;color:${MUTE};letter-spacing:.08em;text-transform:uppercase}`;
const ff=(n,f,w,s='normal')=>`@font-face{font-family:'${n}';src:url(data:font/woff2;base64,${fs.readFileSync('../posts/fonts/'+f).toString('base64')});font-weight:${w};font-style:${s}}`;
const fonts=[ff('Inter','Inter-400-normal.woff2',400),ff('Inter','Inter-600-normal.woff2',600),ff('Inter','Inter-500-normal.woff2',500),ff('Oswald','Oswald-700-normal.woff2',700),ff('IBM Plex Mono','IBMPlexMono-400-normal.woff2',500),ff('IBM Plex Mono','IBMPlexMono-600-normal.woff2',600),ff('Lora','Lora-500-italic.woff2',500,'italic')].join('');
// ---- pre-filled values from the "Refining top 3 goals" session ----
const V={};
const start=new Date(2026,9,5);
const dstr=(w,d)=>{const t=new Date(start);t.setDate(t.getDate()+(w-1)*7+(d-1));return [String(t.getMonth()+1),String(t.getDate()),'2026'];};
const setDate=(id,w,d)=>{const [m,dd,y]=dstr(w,d);V[id+'_m']=m;V[id+'_d']=dd;V[id+'_y']=y;};
V.cover_name='Brian';V.cover_s_m='10';V.cover_s_d='5';V.cover_s_y='2026';V.cover_e_m='12';V.cover_e_d='27';V.cover_e_y='2026';
V.next_m='12';V.next_d='28';V.next_y='2026';
V.vis_where='By December 27: the Be the Man pilot is full (4 men) and I have run all six live Sunday sessions. Two couples are booked. Our family money has a plan: savings moving every month, the birth fund started, and a decision made together on Brittney\'s school.';
V.vis_why='Brittney expects a husband who is dependable, determined, driven, ambitious and wants to build wealth. We have a baby due in early May. I only move when a fire is lit, so I am building the fire into the calendar: a set evening block, reminders and this planner. The cost of not doing this is another year of the same promises.';
V.vis_obs='Only moving under pressure: the evening block is fixed, calls and tasks are in my reminders, and Board Meetings with Brittney (Nov 1, Dec 6) keep me accountable. Self-doubt: I do the actions anyway and judge the results at the weekly review. No sales yet: I fix the message, not the goal. Never use household money or credit.';
V.g1_goal='Fill the 4-seat Be the Man pilot ($147 each) and run all six live Sunday sessions';
V.g1_start='Pilot is live; 0 seats sold'; V.g1_target='4 seats sold; 6 sessions run; about $570';
V.g1_a1='Mon-Thu evening block: post check, groups, messages and calls'; V.g1_a2='Reply to every comment and DM within a day'; V.g1_a3='Sundays Nov 15 - Dec 20, 7:00 PM: run the live session (1 hour)';
V.g2_goal='Book 2 couples at $300 each through couples posts and inquiries'; V.g2_start='No couple prospects yet'; V.g2_target='2 couples booked and paid; about $580';
V.g2_a1='Post the couples content on Instagram and Facebook (never TikTok)'; V.g2_a2='Answer every couples inquiry and invite them to a call'; V.g2_a3='Comment in couples groups: 4 of my 10 daily comments';
V.g3_goal='Build family security: savings moving, birth fund started, and the school decision made together'; V.g3_start='$139/mo freed up; no savings plan'; V.g3_target='Savings running; school decided';
V.g3_a1='Move the freed $139 each month and 20-30% of DoorDash to savings'; V.g3_a2='Board Meeting with Brittney: Nov 1 and Dec 6'; V.g3_a3='Be dependable at home: keep my word on the small promises';
V.ms1_1='Daily rhythm runs Mon-Fri without a fire under me'; V.ms1_2='Posts live every day; 6 Facebook groups joined; first calls done'; V.ms1_3='First seats sold; couples content live; Board Meeting Nov 1 held';
V.ms5_1='All 4 pilot seats are sold by Nov 8'; V.ms5_2='Pilot sessions begin Nov 15 and I am running them well'; V.ms5_3='First couples inquiry answered; savings transfers are on time';
V.ms9_1='Pilot sessions 4-6 delivered (Dec 6, 13, 20)'; V.ms9_2='2 couples booked; testimonials collected with permission'; V.ms9_3='Final review with Brittney Dec 27; the next 12 weeks planned';
const WF=['Daily rhythm starts','Build momentum','Move to 10 comments a day','Hold steady; Board Meeting Nov 1','Fill the last seats','Pilot starts Sunday Nov 15','Run the pilot; couples calls','Run the pilot; keep selling couples','Board Meeting Dec 6; pilot session 4','Pilot session 5; follow up on couples','Pilot session 6 Dec 20; close couples','Final review and plan the next 12'];
const PRI=[
 ['Run the evening block every day','Posts live on IG, FB and TikTok daily','Join 3 Facebook groups; move the first savings'],
 ['Get my first 5 calls booked','Join 3 more Facebook groups (6 total)','Keep every commitment to Brittney'],
 ['Switch to 10 helpful comments a day','First pilot seat sold','Couples posts live; answer every inquiry'],
 ['Pilot seat 2 sold','Prepare for the Nov 1 Board Meeting','Savings transfers on time'],
 ['Pilot seat 3 sold','Send the pilot reminders and Meet link','First couples inquiry answered'],
 ['Pilot seat 4 sold; the pilot is full','Run session 1 on Sunday, Nov 15','Set up the session routine: Meet room open at 6:45 PM'],
 ['Run pilot session 2 on Sunday, Nov 22','Couples calls booked','Savings transfers on time'],
 ['Run pilot session 3 on Sunday, Nov 29','Follow up on couples inquiries','Prepare for the Dec 6 Board Meeting'],
 ['Run pilot session 4; Board Meeting with Brittney','Couples calls and follow-ups','Keep evening block on schedule'],
 ['Run pilot session 5 on Sunday, Dec 13','Book the second couple','Collect pilot testimonials with permission'],
 ['Run pilot session 6 on Sunday, Dec 20','Close the couples conversations','Celebrate with my family'],
 ['Final review with Brittney on Sunday, Dec 27','Plan the next 12 weeks','Rest and be present with my family']];
const sess={6:['Nov 15',1],7:['Nov 22',2],8:['Nov 29',3],9:['Dec 6',4],10:['Dec 13',5],11:['Dec 20',6]};
const DVIS=['Dependable: I do what I said I would do before anyone has to ask.','Determined: I do the uncomfortable messages and calls, even when I do not feel like it.','Driven: I keep going when nobody is watching because my family is counting on it.','Ambitious: I am building something that gives Brittney and the kids security.','I finish the week strong, count my numbers honestly and protect the Sabbath.','Sabbath: I rest and I am fully present with my family. I trust the work I did.','I lead my home and plan next week with Brittney in mind.'];
const lc=w=>w<3?'Weeks 1-2: join 3 Facebook groups':'10 helpful comments in Facebook groups';
for(let w=1;w<=12;w++){
  setDate(`w${w}_wk`,w,1);
  V[`w${w}_pri1`]=PRI[w-1][0];V[`w${w}_pri2`]=PRI[w-1][1];V[`w${w}_pri3`]=PRI[w-1][2];
  ['Evening block Mon-Thu, 5:15-7:30 PM: the daily actions','Friday lunch: 30-minute version of the daily actions','Sabbath (Fri sundown to Sat sundown): no work, selling or filming','Sunday 1:00 PM: reply to weekend comments and DMs','Sunday 7:00 PM: '+(sess[w]?`pilot session ${sess[w][1]} (Meet room opens 6:45)`:'family time and one-on-one with Brittney'),'Weekly review: fill in the review page and planner scorecard'].forEach((t,i)=>V[`w${w}_plan_a${i+1}`]=t);
  V[`w${w}_cal`]='Mon-Thu 5:15-7:30 PM evening block. Friday 12:00 PM lunch version. Posts go out 12:15 PM weekdays and Saturday 8:30 PM (scheduled). Sunday 1:00 PM replies.'+(sess[w]?` Sunday 7:00 PM pilot session ${sess[w][1]}.`:'');
  V[`w${w}_obs`]='Only moving under pressure: calls and tasks are in my reminders and the block is fixed. No answers from men yet: change the message, not the plan. Tired evenings: do the 30-minute version, never zero. 18-hour weekly cap; if I go over, drop to the 12 then 4 hour version. Never use household money.';
  for(let d=1;d<=7;d++){
    const k=`w${w}_d${d}_`; setDate(k+'dt',w,d);
    V[k+'vis']=DVIS[d-1]+` This week: ${WF[w-1]}.`;
    let A,G,P;
    const couples=w>=3?'Couples posts go on Instagram and Facebook only.':'';
    if(d<=4){
      A=['Check today\'s post is live; reply to every comment and DM (25 min)',`Facebook groups (40 min): ${lc(w)}`,'Send 5 personal messages to men who engaged; invite each to a 15-minute call (20 min)','Calls from my messages, in the evening block (30 min)','Check off this planner page and my reminders (5 min)'];
      G=`Finish the evening block, 5:15 to 7:30 PM, with every action checked off. ${WF[w-1]}.`;
      P=PRI[w-1][0];
    } else if(d===5){
      A=['Lunch version: check the post and reply to comments and DMs (10 min)','Facebook groups at lunch: 5 helpful comments (10 min)','Send 5 personal messages (10 min)','Set aside 20-30% of this week\'s DoorDash into the savings jar','Check off this planner page; Sabbath starts at sundown, no work or selling'];
      G='Finish the lunch version, count this week\'s numbers honestly and be ready for the Sabbath.'; P='Do the lunch version and protect the Sabbath';
    } else if(d===6){
      A=['Sabbath: rest until sundown; no work, selling or filming','Be fully present with Brittney and the kids','Tonight\'s 8:30 PM post goes out on its own; do not reply until Sunday','One thing I am grateful for about my wife and my children','Plan nothing for the business today'];
      G='Rest. Be dependable at home and trust the work I did this week.'; P='Be fully present with my family';
    } else {
      const sn=sess[w];
      A=['1:00 PM: reply to weekend comments and DMs (30 min)',w===4||w===9?'Board Meeting with Brittney: numbers, wins, what I need to fix':'Family time and church','Weekly review: fill in this week\'s review page and the planner scorecard',sn?`7:00 PM: run pilot session ${sn[1]} (Meet room opens 6:45, one hour)`:(w===12?'Final 12-week review with Brittney: fill in the final review page':'7:00 PM: one-on-one time with Brittney'),'Set next week\'s priorities and set my reminders for Monday'];
      G=sn?`Run pilot session ${sn[1]} well and finish the weekly review.`:(w===12?'Finish the 12-week review with Brittney and plan the next 12 weeks.':'Review the week honestly and plan next week.');
      P=sn?`Pilot session ${sn[1]} at 7:00 PM`:'Review the week and plan the next one';
    }
    A.forEach((t,i)=>V[k+`a${i+1}`]=t); V[k+'goal']=G; V[k+'pri']=P;
  }
}
fs.writeFileSync('values.json',JSON.stringify(V,null,1));
const html=`<!doctype html><meta charset=utf8><style>${fonts}${css}</style>${pages.join('')}`;
fs.writeFileSync('planner.html',html);
const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});const p=await b.newPage();
await p.setContent(html);await p.evaluate(()=>document.fonts.ready);
const rects=await p.evaluate(()=>[...document.querySelectorAll('.pg')].map((pg,i)=>{const o=pg.getBoundingClientRect();return [...pg.querySelectorAll('.fld')].map(e=>{const r=e.getBoundingClientRect();return {n:e.dataset.n||null,calc:e.dataset.calc||null,w0:+(e.dataset.w||0),d0:+(e.dataset.d||0),cb:e.classList.contains("chk"),ml:e.classList.contains('ml'),x:r.x-o.x,y:r.y-o.y,w:r.width,h:r.height,cover:i===0}})}));
const over=await p.evaluate(()=>[...document.querySelectorAll('.pg')].map((e,i)=>e.scrollHeight>e.clientHeight+1?i+1:0).filter(Boolean));console.log('overflow pages:',over);
fs.writeFileSync('fields.json',JSON.stringify(rects));
await p.pdf({path:'12-week-goal-planner.pdf',width:'8.5in',height:'11in',printBackground:true});await b.close();
