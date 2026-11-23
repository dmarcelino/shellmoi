---
name: gaps
description: Use when the user invokes `/gaps`, usually at the end of a request or right after one, in any mode including plan mode. Assess the request for gaps, inconsistencies and ambiguity, and ask clarifying questions before doing any of the work.
disable-model-invocation: true
---

# Gaps

Make sure a request is clear before acting on it. The request is the text that comes with `/gaps`; when `/gaps` comes alone, it is the latest request in the conversation, together with the current plan if there is one.

## Assess

Analyze the request and look for:
- **Gaps**: what the work needs but the request leaves out, such as scope boundaries, inputs, expected output, edge cases and what "done" looks like.
- **Inconsistencies**: parts that contradict each other, or contradict the codebase, earlier messages or project guidance.
- **Ambiguity**: words or steps that a reasonable reader could take more than one way.

Read the code, docs and conversation first (read-only) so you ask only what they cannot answer. Keep only the questions whose answer would change what you do.

## Ask

- Ask all questions in one round, most consequential first. Use the agent's question tool when it has one, otherwise a numbered list.
- Make each question concrete: point at the part of the request it is about, give the plausible options, and say which one you recommend and why.
- If nothing material is unclear, say so in one line, name the assumptions you will rely on, and continue with the request.

## Then

Do not start the work (no edits, no commands with side effects, no plan) until the questions are answered. When the answers arrive, check them for new gaps or conflicts and ask a short follow-up round if needed; otherwise restate the clarified request in a few lines and proceed.
