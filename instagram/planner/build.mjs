import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
import fs from 'fs';
const A='#C97A12', INK='#141416', MUTE='#6f6a62';
const lines=(n,h=30,f=' fld')=>Array.from({length:n},()=>`<div class="ln${f}" style="height:${h}px"></div>`).join('');
const box=(label,n,h,id='')=>`<div class="lab">${label}</div><div class="fld ml nbx" ${id?`data-n="${id}"`:''} style="height:${n*h}px"></div>`;
const page=(inner,foot='',cls='')=>`<section class="pg ${cls}">${inner}<div class="ft"><span>12-Week Goal Planner</span><span>${foot}</span></div></section>`;
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
    const gm=(label,id,fl)=>`<div class="grow" style="flex:${fl}"><div class="lab">${label}</div><div class="fld ml nbx" data-n="${id}" style="flex:1"></div></div>`;
    pages.push(page(`<div class="wk"><div><div class="k">Week ${w} · Day ${di+1} · ${theme}</div><h2 style="margin-top:6px;font-size:40px">${dn}</h2></div><div class="wd">Date ${dtf()}</div></div><div class="rule" style="margin:10px 0 6px"></div>
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
.pg.day{display:flex;flex-direction:column}.grow{display:flex;flex-direction:column;min-height:46px;margin-top:2px}
.ft{position:absolute;left:.75in;right:.75in;bottom:.35in;display:flex;justify-content:space-between;font:500 9px 'IBM Plex Mono',monospace;color:${MUTE};letter-spacing:.08em;text-transform:uppercase}`;
const ff=(n,f,w,s='normal')=>`@font-face{font-family:'${n}';src:url(data:font/woff2;base64,${fs.readFileSync('../posts/fonts/'+f).toString('base64')});font-weight:${w};font-style:${s}}`;
const fonts=[ff('Inter','Inter-400-normal.woff2',400),ff('Inter','Inter-600-normal.woff2',600),ff('Inter','Inter-500-normal.woff2',500),ff('Oswald','Oswald-700-normal.woff2',700),ff('IBM Plex Mono','IBMPlexMono-400-normal.woff2',500),ff('IBM Plex Mono','IBMPlexMono-600-normal.woff2',600),ff('Lora','Lora-500-italic.woff2',500,'italic')].join('');
// ---- example values for the pre-filled version ----
const V={};
const TRAIN=['Learn the movements','Build the habit','Add load','Deload and review','Push volume','Push pace','Stay consistent','Deload and review','Peak week 1','Peak week 2','Race prep','5K test'];
const MS=['Define the offer and who it is for','Outline the product','Draft the core content','Finish draft v1','Get 3 people to review it','Revise from feedback','Build the sales page','Set up payment and delivery','Soft launch to 10 people','Fix what broke','Public launch','Follow up and plan the next 12 weeks'];
const WT=['Lay the foundation','Build the rhythm','Hold the line','Review and reset','Raise the bar','Midpoint push','Stay steady','Review and reset','Sharpen','Finish what is open','Launch focus','Finish and plan the next 12'];
const DVIS=['I start the week on purpose: calm, prepared and moving before the world asks anything of me.','I do the hard thing first and I do not negotiate with myself.','I check my pace honestly and adjust without excuses.','I stay steady when the novelty is gone. Boring consistency wins.','I finish what I started, so the weekend is free and my word is kept.','I show up fully for my family and my body, with no phone in the way.','I rest, worship and reset so next week starts from a clear head.'];
V.vis_where='In 12 weeks I train four days a week and can run a 5K in under 28 minutes. I pray and read Scripture every morning before my phone. My wife and I have had 12 real date nights. The project I have been putting off is launched and ten people are using it.';
V.vis_why='This is who I told myself I would be. My family needs a man who keeps his word to himself first. If I do not do this, I will be having the same conversation with myself 12 weeks from now, with less energy and less trust in my own word.';
V.vis_obs='Late nights and my phone in bed: phone charges outside the bedroom and lights are out by 10pm. Work interruptions: I block 90 minutes on the calendar and turn notifications off. Missing a day: never miss twice. I log it and do the next action.';
V.g1_goal='Train 4 times a week for 12 weeks and run a 5K in under 28:00'; V.g1_start='Not training consistently'; V.g1_target='48 workouts logged; 5K in under 28:00';
V.g1_a1='Train 4 days: strength Mon, Wed, Thu and a run Sat'; V.g1_a2='Hit 8,000 steps every day'; V.g1_a3='Log meals at least 6 days';
V.g2_goal='Pray and read Scripture 15 minutes every morning and have a date night every week'; V.g2_start='Praying about 2 days a week'; V.g2_target='84 of 84 days; 12 date nights';
V.g2_a1='Pray and read Scripture for 15 minutes before touching my phone'; V.g2_a2='10 minutes of undistracted time with my wife each night'; V.g2_a3='One planned date night every Saturday';
V.g3_goal='Launch the one project that matters by the end of week 12'; V.g3_start='An idea and rough notes'; V.g3_target='Launched, with 10 people using it';
V.g3_a1='One 90-minute deep work block Monday to Friday'; V.g3_a2='Ship the week\'s milestone every Friday'; V.g3_a3='Plan the next week every Sunday';
V.ms1_1='Daily prayer and training habits are running without negotiating'; V.ms1_2='The offer is defined and the first draft of the product is done'; V.ms1_3='Date night and nightly check-ins are on the calendar and happening';
V.ms5_1='Training is up to four days a week with added load and pace'; V.ms5_2='Feedback is in and the product is revised; sales page is built'; V.ms5_3='Payment and delivery work end to end';
V.ms9_1='5K race prep is underway and the pace is on target'; V.ms9_2='Soft launch is done, fixes are made and the public launch is out'; V.ms9_3='84 days of prayer logged and next 12 weeks are planned';
for(let w=1;w<=12;w++){
  const ms=MS[w-1], tr=TRAIN[w-1], deload=(w===4||w===8);
  V[`w${w}_pri1`]=`Finish: ${ms}`; V[`w${w}_pri2`]=`Train four times (${tr})`; V[`w${w}_pri3`]='Pray every morning and keep date night';
  [`Strength: Monday, Wednesday, Thursday${deload?' (light, deload week)':''}`,'Cardio: Tuesday, Friday; long run or hike Saturday','90-minute work block, Monday to Friday',"Pray and read Scripture for 15 minutes daily","Date night on Saturday evening","Weekly review and plan: Sunday evening"].forEach((t,i)=>V[`w${w}_plan_a${i+1}`]=t);
  V[`w${w}_cal`]='Prayer 6:00-6:15am daily. Training 6:30am Mon/Wed/Thu, cardio Tue/Fri. Deep work 9:00-10:30am Mon-Fri. Family time 8:00pm nightly. Date night Saturday 6:00pm. Review and plan Sunday 7:00pm.';
  V[`w${w}_obs`]='Late nights and phone use in bed: phone charges outside the bedroom, lights out by 10pm. Work interruptions: notifications off during the block. If I miss an action, I do the next one on time and never miss twice.';
  for(let d=1;d<=7;d++){
    const k=`w${w}_d${d}_`;
    V[k+'vis']=`${DVIS[d-1]} Week ${w} theme: ${WT[w-1]}.`;
    const strength=deload?'Light workout (deload week)':`Strength workout (${tr})`;
    const A=[
     ['Pray and read Scripture, 15 minutes, before my phone',strength,`90-minute deep work: ${ms}`,'Plan the week: priorities on the calendar','10 minutes undistracted time with my wife'],
     ['Pray and read Scripture, 15 minutes, before my phone','Cardio: 30 minutes, intervals or run',`90-minute deep work: ${ms}`,'Log all meals today','10 minutes undistracted time with my wife'],
     ['Pray and read Scripture, 15 minutes, before my phone',strength,`90-minute deep work: be at 50% on ${ms}`,'Midweek check: compare to plan and adjust','10 minutes undistracted time with my wife'],
     ['Pray and read Scripture, 15 minutes, before my phone',strength,`90-minute deep work: push ${ms} to 80%`,'Log all meals today','10 minutes undistracted time with my wife'],
     ['Pray and read Scripture, 15 minutes, before my phone','Cardio or a 30-minute brisk walk',`Ship it: finish and send "${ms}"`,'Clear open loops: messages, email, errands','Plan the weekend with my wife'],
     ['Pray and read Scripture, 15 minutes, before my phone',w===12?'5K time trial: goal under 28:00':'Long run or hike, building toward the 5K','Date night: phones away','Log meals and prep food for Sunday','One project at home: finish it'],
     ['Worship and pray; rest with my family','20-minute easy walk and stretching','Weekly review: fill in this week\'s review page','Plan next week: priorities and calendar','Prep meals and gear for Monday']][d-1];
    A.forEach((t,i)=>V[k+`a${i+1}`]=t);
    const G=[`Train and start "${ms}" with a clean plan`,`Intervals done and 90 minutes on "${ms}"`,`Be halfway through "${ms}" and lift`,`Push "${ms}" to 80% and train`,`Ship "${ms}" and clear the open loops`,`Long run/hike and a real date night`,'Worship, weekly review and next week planned'][d-1];
    V[k+'goal']=G;
    V[k+'pri']=['Plan the week, then start the milestone','Do the workout and the work block before noon',`Honest midweek check on "${ms}"`,'Do not let today be ordinary: finish the block','Finish and send the milestone','Be fully present with my family','Review the week and plan the next'][d-1];
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
