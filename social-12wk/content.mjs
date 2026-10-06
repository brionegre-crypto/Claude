// All copy for the 12-week calendar (Oct 5 – Dec 27, 2026).
// theme: 'btm' (Be The Man, dark) | 'cpl' (Couples, cream)
// slot: r1/p1/c/p2/r2 → see SLOTS in render.mjs
// Markup in on-image text: *amber words*, **bold**, \n line break.
import { btm } from './content-btm.mjs';
import { cpl } from './content-cpl.mjs';
import { existing } from './content-existing.mjs';

const BIO = 'go.bethemansystem.com/28016a3c';
export const CTA = {
  step1: {
    ig: '👇 Comment "STEP1" and I\'ll send you the free worksheet.',
    fb: 'Get Step 1 free (20 minutes and a pen): https://go.bethemansystem.com/framework',
    th: 'Step 1 is free → go.bethemansystem.com/framework',
    foot: 'Step 1 is free · link in bio', btn: 'Comment “STEP1” →',
  },
  challenge: {
    ig: '🗓 The free 7-week challenge starts Oct 20. One email a week, one action with a time on it. Do it with a brother.\n🔗 Link in bio → "Count me in."',
    fb: 'The free 7-week challenge starts Oct 20. One email a week, one action with a time on it. Forward it to one man you trust.\nJoin free: https://go.bethemansystem.com/42f82c9e',
    th: 'Free 7-week challenge, starts Oct 20 → go.bethemansystem.com/42f82c9e',
    foot: 'Free 7-week challenge · link in bio', btn: 'Free challenge → link in bio',
  },
  challengeOn: {
    ig: '🗓 The free 7-week challenge is running now. Join any week, and the first step comes in your welcome email.\n🔗 Link in bio → "Count me in."',
    fb: 'The free 7-week challenge is running now. Join any week: https://go.bethemansystem.com/42f82c9e',
    th: 'The free 7-week challenge is running. Join any week → go.bethemansystem.com/42f82c9e',
    foot: 'Free 7-week challenge · link in bio', btn: 'Join the challenge →',
  },
  workshop: {
    ig: '🎟 Live workshop: Fix Your Wednesday. Sunday, Oct 25, 7 PM Central, on Google Meet. One hour, $27. You leave with your sentence, one goal with a date, and your first Scorecard. Can\'t make it live? The recording is included.\n🔗 Link in bio → "Reserve my spot."',
    fb: 'Live workshop: Fix Your Wednesday. Sunday, Oct 25, 7 PM Central, on Google Meet. One hour, $27, recording included. You leave with your sentence, one goal with a date, and your first Scorecard.\nReserve your spot: https://go.bethemansystem.com/f0217426',
    th: 'Fix Your Wednesday: live, Sun Oct 25, 7 PM CT. $27, recording included → go.bethemansystem.com/f0217426',
    foot: 'Sun Oct 25 · 7 PM CT · link in bio', btn: 'Oct 25 workshop → link in bio',
  },
  group: {
    ig: '🪑 A 6-week live group for husbands and fathers. Sundays, 7–8 PM Central, on Google Meet, Nov 15 – Dec 20. Four seats.\n🔗 Link in bio → "Reserve my seat."',
    fb: 'A 6-week live group for husbands and fathers. Sundays, 7–8 PM Central, on Google Meet, Nov 15 – Dec 20. Four seats.\nReserve a seat: https://go.bethemansystem.com/b1c774c0',
    th: '6-week live group for husbands and fathers. Sundays Nov 15 – Dec 20, 7 PM CT. Four seats → go.bethemansystem.com/b1c774c0',
    foot: 'Four seats · link in bio', btn: 'Reserve a seat → link in bio',
  },
  club: {
    ig: '🔑 The Be The Man Club: the tools in the store plus a new one every month, $19 a month. Cancel anytime; the files are yours to keep.\n🔗 Link in bio → "Join the Club."',
    fb: 'The Be The Man Club: the tools plus a new one every month, $19 a month. Cancel anytime; the files are yours to keep.\nJoin: https://go.bethemansystem.com/d6dd7931',
    th: 'The Be The Man Club, $19 a month → go.bethemansystem.com/d6dd7931',
    foot: 'The Club · link in bio', btn: 'Join the Club → link in bio',
  },
  clubYear: {
    ig: '🎁 The Be The Man Club, yearly: $149 for twelve months of tools. A gift that\'s still working in March.\n🔗 Link in bio → "Join the Club."',
    fb: 'The Be The Man Club, yearly: $149 for twelve months of tools. A gift that\'s still working in March.\nhttps://go.bethemansystem.com/c24bf36b',
    th: 'The Club, yearly: $149. A gift that\'s still working in March → go.bethemansystem.com/c24bf36b',
    foot: 'Club yearly $149 · link in bio', btn: 'Club yearly → link in bio',
  },
  library: {
    ig: '📚 The Complete Library: all 11 tools in one download, $97. Field guides, workbooks, devotional, Bible study, prayer strategy, card decks and trackers.\n🔗 Link in bio.',
    fb: 'The Complete Library: all 11 tools in one download, $97. Field guides, workbooks, devotional, Bible study, prayer strategy, card decks and trackers.\nhttps://5e95-brian.systeme.io/593d3b68',
    th: 'All 11 tools in one download, $97 → 5e95-brian.systeme.io/593d3b68',
    foot: 'Complete Library · link in bio', btn: 'All 11 tools → link in bio',
  },
  scorecard: {
    ig: '📋 The Weekly Scorecard: your week on one page, $7. Four decisions, each with a time and a written miss.\n🔗 Link in bio.',
    fb: 'The Weekly Scorecard: your week on one page, $7. Four decisions, each with a time and a written miss.\nhttps://go.bethemansystem.com/7d78815c',
    th: 'Your week on one page, $7 → go.bethemansystem.com/7d78815c',
    foot: 'The Scorecard $7 · link in bio', btn: 'The Scorecard → link in bio',
  },
  husbandKit: {
    ig: '🧰 The Husband Kit, $39. The tools for leading your marriage, in one download.\n🔗 Link in bio.',
    fb: 'The Husband Kit, $39. The tools for leading your marriage, in one download.\nhttps://5e95-brian.systeme.io/d1d8c97d',
    th: 'The Husband Kit, $39 → 5e95-brian.systeme.io/d1d8c97d',
    foot: 'The Husband Kit · link in bio', btn: 'Husband Kit → link in bio',
  },
  fatherKit: {
    ig: '🧰 The Father Kit, $29. The tools for leading your kids, in one download.\n🔗 Link in bio.',
    fb: 'The Father Kit, $29. The tools for leading your kids, in one download.\nhttps://5e95-brian.systeme.io/5cbc7892',
    th: 'The Father Kit, $29 → 5e95-brian.systeme.io/5cbc7892',
    foot: 'The Father Kit · link in bio', btn: 'Father Kit → link in bio',
  },
  faithKit: {
    ig: '🧰 The Faith Kit, $29. Prayer, Scripture and discipleship tools with a time attached.\n🔗 Link in bio.',
    fb: 'The Faith Kit, $29. Prayer, Scripture and discipleship tools with a time attached.\nhttps://5e95-brian.systeme.io/d616652a',
    th: 'The Faith Kit, $29 → 5e95-brian.systeme.io/d616652a',
    foot: 'The Faith Kit · link in bio', btn: 'Faith Kit → link in bio',
  },
  call: {
    ig: '📞 Stuck somewhere? Book a free 15-minute call with me.\n🔗 Link in bio → "Book a free call."',
    fb: 'Stuck somewhere? Book a free 15-minute call: https://go.bethemansystem.com/085b95e4',
    th: 'Free 15-minute call: where are you stuck? → go.bethemansystem.com/085b95e4',
    foot: 'Free 15-min call · link in bio', btn: 'Free call → link in bio',
  },
  training: {
    ig: '▶️ Free 6-minute training: why you keep breaking the same promise.\n🔗 Link in bio → "Watch it free."',
    fb: 'Free 6-minute training: why you keep breaking the same promise.\nhttps://go.bethemansystem.com/782480a3',
    th: 'Free 6-min training: why you keep breaking the same promise → go.bethemansystem.com/782480a3',
    foot: 'Free training · link in bio', btn: 'Watch free → link in bio',
  },
  couples: {
    ig: '💬 Engaged or married? Comment "COUPLES" and I\'ll send you how certified marriage counseling works: a validated assessment, then three sessions built on your results.',
    fb: 'Certified marriage counseling for engaged and married couples, with Brian Greene, pastor and certified marriage counselor. A validated assessment, then three sessions built on your results.\nhttps://5e95-brian.systeme.io/0d29fa39',
    th: 'Engaged or married? Certified marriage counseling → 5e95-brian.systeme.io/0d29fa39',
    foot: 'Comment “COUPLES”', btn: 'Comment “COUPLES” →',
  },
  share: {
    ig: '📤 Send this to your spouse. Then talk about it tonight.\n💬 Want help? Comment "COUPLES."',
    fb: '📤 Share this with your spouse, then talk about it tonight.\nCertified marriage counseling: https://5e95-brian.systeme.io/0d29fa39',
    th: 'Send this to your spouse. Talk about it tonight.',
    foot: 'Send this to your spouse', btn: 'Send this to your spouse',
  },
  save: {
    ig: '💾 Save this for your next date night.\n💬 Want help as a couple? Comment "COUPLES."',
    fb: 'Save this for your next date night.\nCertified marriage counseling: https://5e95-brian.systeme.io/0d29fa39',
    th: 'Save this for your next date night.',
    foot: 'Save this for date night', btn: 'Save for date night',
  },
};

export const TAGS = {
  btm: ['#christianmen', '#blackchristianmen', '#godlyhusband', '#christianfather', '#mensdiscipline', '#blackfathers', '#faithandfamily', '#christianhusband', '#selfdisciplineformen', '#blackmenwholead'],
  cpl: ['#christianmarriage', '#blackmarriage', '#christiancouples', '#marriagetips', '#blacklove', '#godlymarriage', '#husbandandwife', '#marriagecounseling', '#premaritalcounseling', '#blackcouples'],
};

export const items = [...btm, ...cpl];
export { existing };
