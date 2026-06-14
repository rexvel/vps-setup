---
description: Send the given text/data to Notion as a new page
argument-hint: <text or data to save to Notion>
---

Save the following text/data to Notion. The raw input is:

<input>
$ARGUMENTS
</input>

Steps:

1. **Handle empty input.** If `<input>` is empty or just whitespace, ask the user what they want to send to Notion, then wait for their reply.

2. **Create the page.** Use the Notion `create-pages` tool to create one new page:
   - **Title:** derive a concise, descriptive title (≤ ~8 words) from the content. If the input is a single short line, use that line as the title. Never leave the title blank.
   - **Content:** the full input, preserved faithfully as Notion-flavored markdown. Keep existing structure (lists, headings, links). If the input looks like code, logs, or structured data, wrap it in a fenced code block. Don't summarize, reword, or drop anything.
   - Parent: omit it (creates a standalone workspace page) unless the user has told you a specific destination page/database to use.

3. **Confirm.** Report the created page's title and URL in one line. Don't add commentary.

This command is an explicit "save to Notion" action — do not ask for confirmation before creating the page; just create it and return the link.
