# Prompt: Define Swift Coding Standards

You are an expert Swift developer and style guide author. Produce a practical
Swift Coding Standards document for a small macOS application (SwiftUI + AppKit,
SwiftPM, no third-party dependencies).

The current, authoritative version of that document already lives in
[`docs/standards/swift.md`](../../../docs/standards/swift.md) — read it first and
extend it rather than replacing it.

Deliverables and structure

- A one-page Decision Table of 10-12 rules with enforcement levels
  (INFO / WARN / FAIL) and a one-line rationale per rule.
- Short "Пояснения к правилам" sections grouped by topic.
- A "Проверки" section with the exact commands to run.
- A reviewer checklist of 8-10 items.

Essential enforcement / hard constraints

Concurrency
Swift 6 strict concurrency, no language-mode downgrade. `@MainActor` on
everything touching AppKit/SwiftUI. Background file I/O via `Task.detached`,
results returned through `await MainActor.run`. `nonisolated(unsafe)` only with a
comment proving safety.

Optionals & errors
No force-unwrap (`!`) or `try!` unless provably safe and commented. `guard let`
with early return over nested `if let`. No silent empty `catch`.

External data
Anything parsed from outside the app (here: Claude Code jsonl logs) uses explicit
casts with defaults (`?? 0`, `?? ""`). A schema change must surface as zeros, not
a crash.

Dependencies
System frameworks only (Foundation, AppKit, SwiftUI, Combine). Any third-party
package requires a written justification in `docs/architecture.md`.

Testing
Non-trivial logic (parsers, loops, branching, time-window boundaries) leaves one
runnable check behind — here the `--selftest` executable flag using
`precondition`. No test frameworks or fixtures unless asked.

Formatting
4 spaces, no tabs. Max 120 columns. Comments and error messages in Russian.
Deliberate simplifications marked with a `ponytail:` comment naming the ceiling
and the upgrade path.

Tooling
Do not introduce SwiftLint / swift-format for a project of this size; state the
condition under which adding one becomes worth it.

Keep the standard actionable and minimal: 1-3 pages of Markdown, written in
Russian, that a developer or an agent can follow directly. Return only the
Markdown content without additional commentary.

## End of Prompt
