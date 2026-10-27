// All copy for the 12-week calendar (Oct 5 – Dec 27, 2026).
// theme: 'btm' (Be The Man, dark) | 'cpl' (Couples, cream)
// slot: r1/p1/c/p2/r2 → see SLOTS in render.mjs
// Markup in on-image text: *amber words*, **bold**, \n line break.
import { btm } from './content-btm.mjs';
import { cpl } from './content-cpl.mjs';
import { existing } from './content-existing.mjs';
import { boost } from './content-boost.mjs';
import { boost2 } from './content-boost2.mjs';

const BIO = 'www.bethemansystem.com/step-1/#get';
export const CTA = {
  step1: {
    ig: '👇 Comment "STEP1" and I\'ll send you the free worksheet.',
    fb: 'Get Step 1 free (20 minutes and a pen): https://www.bethemansystem.com/step-1/#get',
    th: 'Step 1 is free → www.bethemansystem.com/step-1/#get',
    foot: 'Step 1 is free · link in bio', btn: 'Comment “STEP1” →',
  },
  challenge: {
    ig: '🗓 The free 7-week challenge starts Oct 20. One email a week, one action with a time on it. Do it with a brother.\n🔗 Link in bio → "Count me in."',
    fb: 'The free 7-week challenge starts Oct 20. One email a week, one action with a time on it. Forward it to one man you trust.\nJoin free: https://www.bethemansystem.com/7-week-challenge/',
    th: 'Free 7-week challenge, starts Oct 20 → www.bethemansystem.com/7-week-challenge/',
    foot: 'Free 7-week challenge · link in bio', btn: 'Free challenge → link in bio',
  },
  challengeOn: {
    ig: '🗓 The free 7-week challenge is running now. Join any week, and the first step comes in your welcome email.\n🔗 Link in bio → "Count me in."',
    fb: 'The free 7-week challenge is running now. Join any week: https://www.bethemansystem.com/7-week-challenge/',
    th: 'The free 7-week challenge is running. Join any week → www.bethemansystem.com/7-week-challenge/',
    foot: 'Free 7-week challenge · link in bio', btn: 'Join the challenge →',
  },
  workshop: {
    ig: '🎟 Live workshop: Fix Your Wednesday. Sunday, Oct 25, 7 PM Central, on Google Meet. One hour, $27. You leave with your sentence, one goal with a date, and your first Scorecard. Can\'t make it live? The recording is included.\n🔗 Link in bio → "Reserve my spot."',
    fb: 'Live workshop: Fix Your Wednesday. Sunday, Oct 25, 7 PM Central, on Google Meet. One hour, $27, recording included. You leave with your sentence, one goal with a date, and your first Scorecard.\nReserve your spot: https://www.bethemansystem.com/workshop/',
    th: 'Fix Your Wednesday: live, Sun Oct 25, 7 PM CT. $27, recording included → www.bethemansystem.com/workshop/',
    foot: 'Sun Oct 25 · 7 PM CT · link in bio', btn: 'Oct 25 workshop → link in bio',
  },
  workshopWed: {
    ig: '🎟 Fix Your Wednesday, live: every other Wednesday, 7–8 PM Central, on Google Meet. $27, recording included. Next sessions: Nov 18 and Dec 2. You leave with your sentence, one goal with a date and a time, and your first Scorecard.\n🔗 Link in bio → "Fix Your Wednesday."',
    fb: 'Fix Your Wednesday, live: every other Wednesday, 7–8 PM Central, on Google Meet. $27, recording included. Next sessions: Nov 18 and Dec 2.\nReserve your spot: https://www.bethemansystem.com/workshop/',
    th: 'Fix Your Wednesday, live every other Wed, 7 PM CT. $27 → www.bethemansystem.com/workshop/',
    foot: 'Wed 7 PM CT · link in bio', btn: 'Fix Your Wednesday → link in bio',
  },
  lowSeat: {
    ig: '🪑 The Low Seat Check: free, 5 minutes. Twenty statements about what you actually do when you\'re corrected, when you miss, and when someone else gets the credit. You get a score across five postures and one action for this week.\n🔗 Link in bio → "The Low Seat Check."',
    fb: 'The Low Seat Check: free, 5 minutes. How humble are you on a Tuesday? You get a score across five postures and one action for this week. Nothing is saved or sent anywhere.\nhttps://www.bethemansystem.com/humility/',
    th: 'How humble are you on a Tuesday? Free 5-minute check → www.bethemansystem.com/humility/',
    foot: 'Free 5-min check · link in bio', btn: 'Take the check → link in bio',
  },
  innerCircle: {
    ig: '🔒 The Inner Circle: ten men, a weekly class with me every Thursday, a monthly one-on-one, and someone checking your Scorecard. By application.\n🔗 Link in bio → "The Inner Circle."',
    fb: 'The Inner Circle: ten men, a private weekly class with Brian every Thursday, a monthly one-on-one, and a weekly Scorecard review. By application; the first step is a free 15-minute call.\nhttps://www.bethemansystem.com/inner-circle/',
    th: 'The Inner Circle: ten men, a weekly class with me. By application → www.bethemansystem.com/inner-circle/',
    foot: 'By application · link in bio', btn: 'Apply → link in bio',
  },
  group: {
    ig: '🪑 A 6-week live group for husbands and fathers. Sundays, 7–8 PM Central, on Google Meet, Nov 15 – Dec 20. Four seats.\n🔗 Link in bio → "Reserve my seat."',
    fb: 'A 6-week live group for husbands and fathers. Sundays, 7–8 PM Central, on Google Meet, Nov 15 – Dec 20. Four seats.\nReserve a seat: https://www.bethemansystem.com/group/',
    th: '6-week live group for husbands and fathers. Sundays Nov 15 – Dec 20, 7 PM CT. Four seats → www.bethemansystem.com/group/',
    foot: 'Four seats · link in bio', btn: 'Reserve a seat → link in bio',
  },
  club: {
    ig: '🔑 The Be The Man Club: the tools in the store plus a new one every month, $19 a month. Cancel anytime; the files are yours to keep.\n🔗 Link in bio → "Join the Club."',
    fb: 'The Be The Man Club: the tools plus a new one every month, $19 a month. Cancel anytime; the files are yours to keep.\nJoin: https://www.bethemansystem.com/the-club/',
    th: 'The Be The Man Club, $19 a month → www.bethemansystem.com/the-club/',
    foot: 'The Club · link in bio', btn: 'Join the Club → link in bio',
  },
  clubYear: {
    ig: '🎁 The Be The Man Club, yearly: $149 for twelve months of tools. A gift that\'s still working in March.\n🔗 Link in bio → "Join the Club."',
    fb: 'The Be The Man Club, yearly: $149 for twelve months of tools. A gift that\'s still working in March.\nhttps://www.bethemansystem.com/the-club/',
    th: 'The Club, yearly: $149. A gift that\'s still working in March → www.bethemansystem.com/the-club/',
    foot: 'Club yearly $149 · link in bio', btn: 'Club yearly → link in bio',
  },
  library: {
    ig: '📚 The Complete Library: all 11 tools in one download, $97. Field guides, workbooks, devotional, Bible study, prayer strategy, card decks and trackers.\n🔗 Link in bio.',
    fb: 'The Complete Library: all 11 tools in one download, $97. Field guides, workbooks, devotional, Bible study, prayer strategy, card decks and trackers.\nhttps://www.bethemansystem.com/products/#the-system',
    th: 'All 11 tools in one download, $97 → www.bethemansystem.com/products/#the-system',
    foot: 'Complete Library · link in bio', btn: 'All 11 tools → link in bio',
  },
  scorecard: {
    ig: '📋 The Weekly Scorecard: your week on one page, $7. Four decisions, each with a time and a written miss.\n🔗 Link in bio.',
    fb: 'The Weekly Scorecard: your week on one page, $7. Four decisions, each with a time and a written miss.\nhttps://www.bethemansystem.com/products/#the-system',
    th: 'Your week on one page, $7 → www.bethemansystem.com/products/#the-system',
    foot: 'The Scorecard $7 · link in bio', btn: 'The Scorecard → link in bio',
  },
  husbandKit: {
    ig: '🧰 The Husband Kit, $39. The tools for leading your marriage, in one download.\n🔗 Link in bio.',
    fb: 'The Husband Kit, $39. The tools for leading your marriage, in one download.\nhttps://www.bethemansystem.com/products/#your-marriage',
    th: 'The Husband Kit, $39 → www.bethemansystem.com/products/#your-marriage',
    foot: 'The Husband Kit · link in bio', btn: 'Husband Kit → link in bio',
  },
  fatherKit: {
    ig: '🧰 The Father Kit, $29. The tools for leading your kids, in one download.\n🔗 Link in bio.',
    fb: 'The Father Kit, $29. The tools for leading your kids, in one download.\nhttps://www.bethemansystem.com/products/#fatherhood',
    th: 'The Father Kit, $29 → www.bethemansystem.com/products/#fatherhood',
    foot: 'The Father Kit · link in bio', btn: 'Father Kit → link in bio',
  },
  faithKit: {
    ig: '🧰 The Faith Kit, $29. Prayer, Scripture and discipleship tools with a time attached.\n🔗 Link in bio.',
    fb: 'The Faith Kit, $29. Prayer, Scripture and discipleship tools with a time attached.\nhttps://www.bethemansystem.com/products/#your-faith',
    th: 'The Faith Kit, $29 → www.bethemansystem.com/products/#your-faith',
    foot: 'The Faith Kit · link in bio', btn: 'Faith Kit → link in bio',
  },
  call: {
    ig: '📞 Stuck somewhere? Book a free 15-minute call with me.\n🔗 Link in bio → "Book a free call."',
    fb: 'Stuck somewhere? Book a free 15-minute call: https://www.bethemansystem.com/call/',
    th: 'Free 15-minute call: where are you stuck? → www.bethemansystem.com/call/',
    foot: 'Free 15-min call · link in bio', btn: 'Free call → link in bio',
  },
  training: {
    ig: '▶️ Free 6-minute training: why you keep breaking the same promise.\n🔗 Link in bio → "Watch it free."',
    fb: 'Free 6-minute training: why you keep breaking the same promise.\nhttps://www.bethemansystem.com/training/',
    th: 'Free 6-min training: why you keep breaking the same promise → www.bethemansystem.com/training/',
    foot: 'Free training · link in bio', btn: 'Watch free → link in bio',
  },
  couples: {
    ig: '💬 Engaged or married? Comment "COUPLES" and I\'ll send you how certified marriage counseling works: a validated assessment, then three sessions built on your results.',
    fb: 'Certified marriage counseling for engaged and married couples, with Brian Greene, pastor and certified marriage counselor. A validated assessment, then three sessions built on your results.\nhttps://www.bethemansystem.com/couples/',
    th: 'Engaged or married? Certified marriage counseling → www.bethemansystem.com/couples/',
    foot: 'Comment “COUPLES”', btn: 'Comment “COUPLES” →',
  },
  share: {
    ig: '📤 Send this to your spouse. Then talk about it tonight.\n💬 Want help? Comment "COUPLES."',
    fb: '📤 Share this with your spouse, then talk about it tonight.\nCertified marriage counseling: https://www.bethemansystem.com/couples/',
    th: 'Send this to your spouse. Talk about it tonight.',
    foot: 'Send this to your spouse', btn: 'Send this to your spouse',
  },
  comment: {
    ig: '💬 Answer in the comments. I read every one.',
    fb: '💬 Answer in the comments. I read every one.',
    th: 'Reply below. I read every one.',
    foot: 'Answer in the comments', btn: 'Answer below ↓',
  },
  save: {
    ig: '💾 Save this for your next date night.\n💬 Want help as a couple? Comment "COUPLES."',
    fb: 'Save this for your next date night.\nCertified marriage counseling: https://www.bethemansystem.com/couples/',
    th: 'Save this for your next date night.',
    foot: 'Save this for date night', btn: 'Save for date night',
  },
};

export const TAGS = {
  btm: ['#christianmen', '#blackchristianmen', '#godlyhusband', '#christianfather', '#mensdiscipline', '#blackfathers', '#faithandfamily', '#christianhusband', '#selfdisciplineformen', '#blackmenwholead'],
  cpl: ['#christianmarriage', '#blackmarriage', '#christiancouples', '#marriagetips', '#blacklove', '#godlymarriage', '#husbandandwife', '#marriagecounseling', '#premaritalcounseling', '#blackcouples'],
};

export const items = [...btm, ...cpl, ...boost, ...boost2];
export { existing };
