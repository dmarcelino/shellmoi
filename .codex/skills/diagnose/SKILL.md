---
name: diagnose
description: Use when the user invokes `/diagnose`, optionally with a bug, symptom, or failure. Investigate before hypothesizing. Gather contrasting data points, name the plausible causes with a check that tells them apart, run those checks (asking the user only for the ones you cannot run), then reason step by step to the root cause. With no argument, apply it to the problem currently under discussion.
disable-model-invocation: true
---

Find the root cause of what follows `/diagnose` (or, if nothing follows, the problem currently under discussion). Evidence first, hypothesis second:

1. Gather several data points before forming any hypothesis: reproduce the failure, read the code path, logs and recent changes, and compare views that should differ (filtered vs unfiltered, edge cases, other environments). One observation fits many causes; contrasting ones rule most of them out.
2. Name the 2-3 most plausible causes and, for each, a contrasting check that would rule it in or out (e.g. filter X vs all, small vs large dataset, fresh vs cached). Say what each outcome would point to.
3. Run the checks you can run yourself. Ask the user only for checks you cannot run (production data, their environment, something only they know), and wait for those answers. Do not settle on a root cause until the evidence rules out the alternatives; a hunch is not evidence, however confident it feels.
4. With the results, analyze deeply and step by step: rule out the causes the evidence contradicts and trace the remaining one through the code to the exact line or condition. If the evidence still fits more than one cause, go back to step 2 with sharper checks instead of guessing.
5. Report the root cause and the chain of evidence behind it: each check, who ran it (you or the user), what it showed, and which alternative it ruled out, so the user can see why each one was dropped. Propose a fix but do not apply it unless asked; when asked, use TDD.
