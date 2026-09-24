# Agent 指南

## Commit messages

**A commit must explain the change well enough to review without reconstructing intent from the diff.**

- Use a specific Conventional Commit subject, such as `feat(web): add collapsible trading navigation`.
- Keep the subject concise, but do not use vague summaries such as `update code`, `fix UI`, or `changes`.
- Include a commit body for every non-trivial commit.
- In the body, explain why the change was needed, what behavior or architecture changed, and how it was verified.
- Call out important constraints, migrations, compatibility effects, or intentionally deferred work when relevant.
- Record concrete verification commands or results instead of writing only `tests passed`.
- Do not pad the message with a file-by-file changelog; summarize the meaningful product and technical outcomes.

Preferred structure:

```text
feat(scope): concise, specific outcome

Explain the user or technical problem that motivated the change.

- Describe the main behavior and implementation changes.
- Note important constraints or compatibility decisions.
- Verification: list the checks or tests that passed.
```
