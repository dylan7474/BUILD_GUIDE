# Repository Contribution Guidelines

## Scope
These instructions apply to the entire repository unless a subdirectory contains
its own `AGENTS.md` with more specific guidance.

## General Expectations
- Keep changes idempotent. Installation scripts should be safe to re-run without
  leaving partial state behind.
- Prefer clear, self-documenting function names and add comments when a command
  sequence is non-obvious.
- Update the relevant Markdown guides when you add, remove, or change features
  exposed to end users.

## Shell Script Style (`*.sh`)
- Use `#!/bin/bash` as the shebang and Bash-specific syntax (arrays, `[[ ]]`,
  `local`, etc.) consistently.
- Indent nested blocks with four spaces and avoid tabs.
- Reuse the existing helper functions (`print_section`, `print_done`,
  `print_error`, etc.) for messaging. If you introduce new helpers, group them
  near the top of the file with the current ones.
- Capture failures with `|| print_error "message"` so errors surface clearly.
  When invoking commands in loops, ensure each command is guarded the same way.
- When downloading external assets, pin the version in a variable and keep all
  URLs together in an easy-to-find block (see `install_mingw_sdl_stack`).

## Markdown Documentation (`*.md`)
- Wrap text at roughly 100 characters for readability and keep section headings
  in sentence case.
- Use fenced code blocks with a language hint (e.g., ```bash) for shell
  commands.
- Keep lists consistent with the surrounding style (numbered vs. bulleted).

Following these conventions keeps the repository approachable for future
contributors and ensures the automated setup scripts remain reliable.
