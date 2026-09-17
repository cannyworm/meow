# AGENTS.md

Zig 0.16 CLI ("meow"): scrapes torrent sites (currently nyaa.si), parses HTML with lexbor, fetches over HTTP with zig-curl. Goal is media file renaming per the convention linked in `note.md`.

## Commands

- `zig build` / `zig build run -- <args>` / `zig build test`
- Requires **Zig 0.16.0** (uses the 0.16 `std.Io` API: `pub fn main(init: std.process.Init)`, `Io.Writer`, unmanaged `std.ArrayList` syntax). Older Zig will not compile this.
- No lint/typecheck config; `zig build` is the check.

## Setup gotchas

- `vendor/lexbor` is a **git submodule**. Clone with `--recurse-submodules` or run `git submodule update --init` — the build panics without it. lexbor is compiled from source by `build.zig` (no system library needed).
- zig-curl comes from `build.zig.zon`; fetched automatically on first build (cached in `zig-pkg/`, gitignored). libc is linked.

## Runtime quirk

- `src/service/nyaa.zig` `searchRaw()` reads the local file `log/nyaa.si` (saved HTML) **relative to cwd** instead of doing live HTTP. `log/` is gitignored, so run from repo root and create the fixture yourself (save nyaa.si search-result HTML there).

## Layout

- `src/main.zig` — exe entry; `src/root.zig` — library module root (`@import("meow")`)
- `src/html/html.zig` — lexbor `@cImport` bindings + `MakeProxy` create/init/deinit wrapper and `ok()` status check; use these instead of raw lexbor calls where possible
- `src/service/` — one scraper per site (`nyaa.zig`)
- `src/media/`, `src/logger/` — stubs, not wired into the build
- `zig build test` runs two test binaries (library module + exe module); test blocks anywhere in those import graphs are picked up
