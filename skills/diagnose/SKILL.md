---
name: diagnose
description: Use when the user invokes `/diagnose`, optionally with a bug, symptom, or failure. Investigate before hypothesizing. Gather contrasting data points, list three checks that would tell candidate causes apart and wait for the answers, then reason step by step to the root cause. With no argument, apply it to the problem currently under discussion.
disable-model-invocation: true
---

Find the root cause of what follows `/diagnose` (or, if nothing follows, the problem currently under discussion). Evidence first, hypothesis second:

1. Gather several data points before forming any hypothesis: reproduce the failure, read the code path, logs and recent changes, and compare views that should differ (filtered vs unfiltered, edge cases, other environments). One observation fits many causes; contrasting ones rule most of them out.
2. List 3 contrasting observations or test cases for the user to check, each chosen to split the candidate causes (e.g. does it happen with filter X vs all, small vs large datasets, fresh vs cached). Say what each outcome would point to.
3. Stop and wait for the answers. Do not name a root cause yet; an early guess anchors the investigation.
4. With the answers, analyze deeply and step by step: rule out the causes the evidence contradicts and trace the remaining one through the code to the exact line or condition. If the evidence still fits more than one cause, go back to step 2 with sharper checks instead of guessing.
5. Report the root cause, the chain of evidence behind it, and what was ruled out. Propose a fix but do not apply it unless asked; when asked, use TDD.
