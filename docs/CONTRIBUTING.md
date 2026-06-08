# Contributing to fern-core >>

> This document is the thing the README says doesn't exist yet.  It now exists.

---

## Before you start

1. Read the [README](README.md).  Not a skim.  The architecture section matters.
2. Make sure `zig build test` passes on your machine.  If it doesn't, open an
   issue before writing any code.
3. Check the open issues for something labelled `good first issue` or
   `help wanted`.  If you have a new idea, open an issue first so we can
   discuss the design before you spend time on a PR that might not fit.

---

## Zig version requirement

**Zig 0.16.0 only.**  Not nightly.  Not 0.14.  Not whatever the package
manager pulled in.  If a PR introduces a breaking API or uses a feature not
available in 0.16.0, it will be closed.

---

## How the codebase is structured

```
src/
  ansi/    -- ANSI escape sequence parser and types.  No deps inside fern.
  anim/    -- Physics animations (Spring, Throw).  No deps inside fern.
  style/   -- Style, Border, Layout.  Depends on fern_ansi.
  zone/    -- Zone Manager + ZoneInfo.  Depends on fern_ansi.
  app/     -- TEA runtime.  Depends on fern_ansi, fern_anim, fern_zone.
  widget/  -- Widgets.  Depends on fern_ansi, fern_style, fern_app, fern_anim.
  chart/   -- Braille chart library.  Depends on nothing inside fern.
examples/
  01_spinner/
  02_progress/
  03_list/
  04_zone_click/
```

**The dependency graph must remain a DAG.**  Specifically:

- Nothing in `ansi/`, `anim/`, or `chart/` may import anything else in fern.
- `style/` and `zone/` may only import `ansi/`.
- `app/` may import `ansi/`, `anim/`, `zone/`.
- `widget/` may import `ansi/`, `style/`, `app/`, `anim/`.
- No module may import `widget/` or `chart/`.

If a PR breaks this table, it will be rejected regardless of feature quality.

---

## Adding a new widget

1. Create `src/widget/<name>.zig`.
2. Follow the existing pattern: `init()`, `update()`, `view()`, comptime `MsgT`.
3. Export it from `src/widget/root.zig`.
4. Add a `test-widget-<name>` step to `build.zig` (copy the pattern for
   existing widgets).
5. Write a `examples/0N_<name>/main.zig` that demonstrates the widget.
6. Add the example step to `build.zig`.

---

## Adding a new chart type

1. Create `src/chart/<type>.zig`.  Import only `canvas.zig` or nothing.
2. Export it from `src/chart/root.zig`.
3. Write tests in the same file (see `canvas.zig` for the pattern).

---

## Code style

- `const` by default; `var` only when mutation is necessary.
- No shadowing -- it is a compile error in Zig 0.16.0 and we want it.
- Allocators are passed as parameters, never stored in global state.
  The documented exception is `fern_zone.Manager`, which must store its
  allocator because it owns long-lived maps.
- `errdefer` for error-path cleanup; `defer` for unconditional cleanup.
- Comments explain *why*, not *what*.
- Every public function has a doc comment (lines starting with `///`).
- `zig fmt src/` and `zig fmt examples/` before every commit.

---

## Testing

Every file must have test blocks for its public API.  Run:

```bash
zig build test          # all modules
zig build test-app      # only app/
zig build test-widget   # only widget/
```

Tests must pass with no leaks under `std.testing.allocator`.

---

## Commit format

```
Types(<scope>): <short description>

<optional longer explanation>
```
Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.
Scopes: `ansi`, `anim`, `style`, `zone`, `app`, `widget`, `chart`, `build`, `docs`, `examples`.


Examples:

```
fix(widget/stopwatch): fix stack-escape UB in start()
fix(zone): wire Manager.scan() into app event loop
feat(chart): add braille BarChart and Sparkline
feat(build): add build.zig.zon package manifest
```

No issue references required in the commit message, but link the issue in the
PR description.

---

## Pull request checklist

- [ ] `zig build test` passes
- [ ] `zig fmt src/ examples/ build.zig` has been run
- [ ] New public functions have doc comments
- [ ] No new module introduces a cycle in the dep graph
- [ ] The PR description links the issue it addresses (if any)

---

## What we will not merge

- PRs that use a Zig version other than 0.16.0.
- PRs that add a cycle to the dependency graph.
- PRs that remove existing tests.
- PRs that introduce UB (stack-escape, out-of-bounds, integer overflow without
  explicit wrapping operators).
- PRs for `fern_chart` that use heap allocation in hot render paths.

---

Thank you for contributing.
