---
description: Grill the user about a task, then convert it into a structured, checkable todo-list
argument-hint: <task or text to convert into a todo-list>
---

You are converting a task into a structured, actionable todo-list. The raw input is:

<input>
$ARGUMENTS
</input>

Work through these steps in order:

1. **Handle empty input.** If `<input>` is empty or just whitespace, ask the user what task or text they want to convert, then wait for their reply before continuing.

2. **Grill for detail.** Invoke the `grill-me` skill to interview the user about this task before writing any items. Surface what's missing to write *concrete* steps: scope and boundaries, constraints, dependencies/order, required tools or access, edge cases, and the definition of done. Keep it high-signal — a few sharp questions, resolved one decision at a time — not an exhaustive interrogation. Stop grilling once you have enough to write steps that are unambiguous and verifiable.

3. **Convert to a todo-list.** Turn the refined understanding into a checklist where every item is:
   - a single concrete action that starts with a verb,
   - independently verifiable (you can tell when it's done),
   - ordered so dependencies come first.
   Add a short `—` sub-note only for non-obvious items. If the task is large, group items under `##` phase headings. Don't invent work the user didn't imply; if a step is a recommended-but-optional addition, mark it `(optional)`.

4. **Render** the list as GitHub-style markdown checkboxes (`- [ ] ...`) so each item is tickable.

5. **Offer to persist it.** Ask whether to save the checklist as a new Notion checklist page (Notion is connected; Todoist is not). Only create the page if the user confirms. If they decline, leave the list in the conversation.

Keep your own commentary minimal — the value is the questions you ask and the quality of the resulting list.
