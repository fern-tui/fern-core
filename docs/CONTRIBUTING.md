# Contributing to fern-core

If you are reading this, you are already thinking about
contributing. That is appreciated. fern is free and open-source software. 
Bug reports and patches are welcome from everyone. fern governance is 
BDFN (Benevolent Dictator For Now), which means the fern-tui team has 
final say on the design and implementation of everything.

## Before you start

1. Read the [README](../README.md), particularly the architecture section.
2. Run `zig build test` on your machine before touching anything. If it fails
   before your changes, open an issue. Do not open a PR on a broken baseline.
3. Check open issues for `good first issue` or `help wanted` before starting
   new work. New idea? Open an issue first. A PR nobody asked for is a PR that
   will wait indefinitely.

## Zig version

0.16.0. Not nightly, not 0.14, not 0.13. If your PR touches an API that does
not exist in 0.16.0, it gets closed.

## Codebase layout

```
src/
  ansi/    -- ANSI escape sequences and types. No fern deps.
  anim/    -- Physics animations (Spring, Throw). No fern deps.
  style/   -- Style, Border, Layout. Depends on fern_ansi.
  zone/    -- Zone Manager + ZoneInfo. Depends on fern_ansi.
  app/     -- TEA runtime. Depends on fern_ansi, fern_anim, fern_zone.
  widget/  -- Widgets. Depends on fern_ansi, fern_style, fern_app, fern_anim.
  chart/   -- Braille chart library. No fern deps.
examples/
  01_spinner/
  02_progress/
  03_list/
```

The dependency graph is a DAG. It stays a DAG.

- `ansi/`, `anim/`, `chart/`: no fern imports.
- `style/`, `zone/`: may only import `ansi/`.
- `app/`: may import `ansi/`, `anim/`, `zone/`.
- `widget/`: may import `ansi/`, `style/`, `app/`, `anim/`.
- Nothing imports `widget/` or `chart/`.

A PR that introduces a cycle is closed regardless of the feature it delivers.
Dependency discipline is non-negotiable.

## Adding a widget

1. Create `src/widget/<name>.zig`.
2. Pattern: `init()`, `update()`, `view()`, comptime `MsgT`. Match existing widgets.
3. Export from `src/widget/root.zig`.
4. Add `test-widget-<name>` step to `build.zig`.
5. Write `examples/0N_<name>/main.zig` demonstrating the widget.
6. Add the example step to `build.zig`.

## Adding a chart type

1. Create `src/chart/<type>.zig`. Import only `canvas.zig` or nothing.
2. Export from `src/chart/root.zig`.
3. Tests live in the same file. See `canvas.zig` for the pattern.

## Code style

- `const` by default. `var` only when mutation is actually required.
- No shadowing. Zig 0.16.0 makes it a compile error; we consider this a feature.
- `errdefer` for error-path cleanup. `defer` for unconditional cleanup.
- Comments explain why, not what. If the comment restates the code, delete it.
- Every public function has a doc comment (`///`).
- Run `zig fmt src/ examples/ build.zig` before every commit. Not sometimes. Every time.

## Testing

Every public API needs test blocks. Not most of them. All of them.

```sh
zig build test          # all modules
zig build test-app      # app/ only
zig build test-widget   # widget/ only
```

Tests must pass clean under `std.testing.allocator`. Zero leaks.

## AI usage

fern does not adopt Zig's no-LLM policy. AI tools are welcome; shipping
code you cannot explain is not.

Using a model to move faster, catch your own mistakes, or explore an approach
is acceptable. Generating boilerplate that you then read and verify is
acceptable.

The following will get a PR closed:

- You cannot explain a line in review. "The model wrote it" is not a review
  response. It means you shipped code you do not understand into a codebase
  other people depend on.

- The code uses Zig APIs from 0.14 or 0.13. Most models were trained before
  0.16.0 and will confidently produce code for older versions. `std.io.Writer`
  changed. Allocator interfaces changed. Several things that compiled in 0.14
  do not compile in 0.16.0. Verify every API call against the 0.16.0 stdlib
  source. The source is the ground truth. The model is not.

- The model added heap allocation to a hot path. The model does not know the
  project rules. You do, because you read this document. You own what you submit.

- The diff is a wall of changes with no coherent explanation. If you cannot
  describe in one paragraph what the PR does and why, it is not ready.

If a bug ships because you did not verify what the model generated, that bug
has your name on it. You reviewed it. You approved it. You submitted it.

## Commit format

```
type(scope): short description

optional longer body
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`,
       `ci`, `chore`, `revert`

Scopes: `ansi`, `anim`, `style`, `zone`, `app`, `widget`, `chart`, `build`,
        `docs`, `examples`

Examples:

```
fix(widget/stopwatch): fix stack-escape UB in start()
fix(zone): wire Manager.scan() into app event loop
feat(build): add build.zig.zon package manifest
```

Issue references go in the PR description, not the commit message.

## PR checklist

- [ ] `zig build test` passes
- [ ] `zig fmt src/ examples/ build.zig` has been run
- [ ] New public functions have doc comments
- [ ] No new cycle introduced in the dep graph
- [ ] PR description links the relevant issue (if any)

## What gets closed immediately

- Zig version other than 0.16.0.
- Dep cycle introduced.
- Existing tests removed.
- UB introduced: stack-escape, out-of-bounds, integer overflow without
  explicit wrapping operators.
- Heap allocation in hot render paths.
- Code the author cannot explain in review.

---
<div align=center>
Thank you for contributing.
</div>
