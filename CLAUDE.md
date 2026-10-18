# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

Command-line tool that converts CharPad and SpritePad project files into artifacts (e.g. binary data, source includes) that can be consumed by build pipelines.

## Project status

Freshly generated Nimble binary package (`nimble init` skeleton). The only source file is `src/charpad_spritepad_assistant.nim`, which currently prints "Hello, World!". No tests or architecture exist yet; `README.md` holds the purpose and the format version tables — update this file as the project takes shape.

## Priorities

Formats written by the releases currently on itch.io (subchristsoftware.itch.io) matter most: CTM V9 (CharPad C64 Pro 3.6+), CTM V7 (CharPad Free 2.86) and SPD V5 (SpritePad C64 Pro). Older versions come after these.

## Issue tracking

Issues live in `ISSUES.md` (format described at its top). When finishing work on an issue, move it to "Closed"; when adding one, use the next free number and bump it.

## Toolchain

- Nim >= 2.2.8 (declared in `charpad_spritepad_assistant.nimble`), managed with Nimble.
- Project is opened in IntelliJ IDEA with the Nim plugin (`.idea/`).

## Commands

```sh
nimble build                 # compile to bin/charpad_spritepad_assistant
nimble run                   # build and run
nim c -r src/charpad_spritepad_assistant.nim   # compile + run directly
nim check src/charpad_spritepad_assistant.nim  # type-check without building
nimble test                  # runs tests/t*.nim (no tests/ dir yet)
nim c -r tests/tfoo.nim      # run a single test file once tests exist
```

## Layout

- `srcDir = "src"`, `binDir = "bin"`; the binary entry point is `src/charpad_spritepad_assistant.nim` (code under `when isMainModule:`).
- Library modules for the package should go in `src/charpad_spritepad_assistant/`; tests in `tests/` with `t` prefix (Nimble convention picked up by `nimble test`).
- `docs/spritepad.md`: SpritePad formats: 1.x `.spr`+`.inf`, headerless 1.8 `.spd`, SPD V1-V5.
- `docs/import-export.md`: every import/export format of the current CharPad, SpritePad and Glaze releases, and which we support.
- `docs/charpad.md`: CTM V1-V9 format (from CharPad's official specs, checked against all bundled samples) and lessons from earlier projects; `docs/reference/` holds the Python scripts they came from.
- `software/` (untracked, ~83 MB): every CharPad and SpritePad release found, as zip/rar. They hold the official spec HTML (`Help/File Format - *.htm`) and ~1500 distinct sample `.ctm`/`.spd` files, a good test corpus. Extract to a scratch dir; don't commit.
