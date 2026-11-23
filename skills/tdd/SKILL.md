---
name: tdd
description: Use when the user invokes `/tdd`, optionally with a bug, behavior, or change to make. Work test first. Write a failing test, confirm it fails for the expected reason, make the smallest fix, confirm it passes, and keep the test to prevent regressions. With no argument, apply it to the problem currently under discussion.
disable-model-invocation: true
---

Apply Test Driven Development to what follows `/tdd` (or, if nothing follows, the problem currently under discussion):

1. Write a test that reproduces the bug or describes the new behavior, next to the existing tests and in their style.
2. Run it and confirm it fails, and that it fails for the expected reason: the assertion, not a compile error, a missing import or broken setup. A test that passes before the fix proves nothing; correct the test until it fails for the right reason.
3. Make the smallest code change that fixes the problem. Do not weaken the test to make it pass.
4. Run the test again and confirm it passes, then run the surrounding suite to check nothing else broke.
5. Keep the test so the problem cannot come back unnoticed.

Report the test added, the failing output before the fix, and the passing output after. If the problem cannot be reproduced in a test, explain why and ask how to proceed instead of fixing it untested.
