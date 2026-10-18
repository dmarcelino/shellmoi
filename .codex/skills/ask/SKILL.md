---
name: ask
description: Use only when the user explicitly invokes `$ask` with a question and wants a direct answer, not implementation. This skill answers technical questions using the current codebase when relevant and the web when the question depends on external libraries, frameworks, APIs, versions, or current best practices. It does not plan work or make code changes.
disable-model-invocation: true
---

# Ask

Use this skill only for explicit `$ask ...` questions where the user wants an answer, explanation, or opinion rather than implementation.

## Scope

This skill:
- answers the question directly
- may inspect the current repository
- may browse the web for current external technical information
- does not edit files
- does not make code changes
- does not produce implementation plans unless the user explicitly asks for one

## Question classification

First classify the question:

1. **Codebase-specific**
   - Example: `$ask where is authentication enforced?`
   - Use the repository as the primary source.

2. **External technology**
   - Example: `$ask what are good React lightbox libraries?`
   - Use the web as the primary source, preferring official documentation, official repos, and authoritative sources.

3. **Mixed**
   - Example: `$ask are we using the recommended Next.js caching pattern here?`
   - Use both the repository and external authoritative sources.

4. **Design / architecture / tradeoff**
   - Example: `$ask should this service use CQRS?`
   - Answer directly using engineering judgment, grounded in the repo if relevant and external sources if version/framework specifics matter.

## Workflow

1. Parse the question.
   - Treat everything after `$ask` as the question.
   - If the request is actually asking for implementation, planning, or code changes, do not do them. Answer the question only.

2. Gather evidence proportionate to the question.
   - For codebase questions, start with targeted repository search using `rg`, then inspect only the most relevant files.
   - Prefer focused reads over broad exploration.
   - Stop once you have enough evidence to answer confidently.
   - Use git history only if it materially improves the answer.

3. Use the web when external facts matter.
   - Browse the web by default for questions about libraries, frameworks, APIs, cloud services, browser behavior, standards, version compatibility, deprecations, pricing, or current best practices.
   - Prefer official docs, official repositories, vendor documentation, standards/specs, and primary sources.
   - Use secondary sources only when primary sources are insufficient.

4. Synthesize carefully.
   - Separate:
     - what the repository shows
     - what comes from external sources
     - what is inference or opinion

5. Answer directly.
   - Lead with the answer.
   - Keep it concise unless the user asks for depth.
   - Include exact file references when they materially support repo-based claims.
   - Mention versions when relevant and known.
   - If evidence is incomplete, say what was checked and what remains uncertain.

## Response format

Use this structure when helpful:

- **Answer:** direct response to the question
- **In this repo:** concrete evidence from files/config/code paths
- **External guidance:** current library/framework/vendor guidance, if used
- **Uncertainty:** only when needed

Do not force all sections if the question is simple.

## Response rules

- Do not create plans, task breakdowns, or implementation checklists unless explicitly requested.
- Do not edit files, apply patches, or run mutating commands.
- Prefer answering the stated question over proposing changes.
- Do not pad the answer with generic advice.
- Optional recommendations are allowed only if clearly separated from the main answer.
- When the answer depends on a library or framework version, say so explicitly.

## Examples

- `$ask how are users authenticated?`
  - Inspect auth middleware, providers, services, session handling, and relevant config. Explain the actual flow with file references.

- `$ask give examples of react libraries for lightboxes?`
  - Browse the web and answer using current ecosystem information, preferring official docs/repos. Mention whether the current repo already uses related modal/gallery libraries.

- `$ask where is automatic rendering toggled?`
  - Search the repo and answer with the relevant component, handler, configuration, and route context.

- `$ask is this the recommended Spring Security approach now?`
  - Inspect the repo implementation and compare it with current official Spring documentation.

## Constraints

- Explicit invocation only.
- This skill is for answering questions, not doing the work.
- When evidence is mixed, clearly label repo facts, external facts, and inference separately.