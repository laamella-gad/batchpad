# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

Command-line tool that converts CharPad and SpritePad project files into artifacts (e.g. binary data, source includes) that can be consumed by build pipelines.

## Project status

Freshly generated Nimble binary package (`nimble init` skeleton). The only source file is `src/charpad_spritepad_assistant.nim`, which currently prints "Hello, World!". No tests, README, or architecture exist yet — update this file as the project takes shape.

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
- `docs/spritepad.md`: SpritePad 1.8 .spd format.
- `docs/charpad.md`: CTM format notes and lessons from earlier projects; `docs/reference/` holds the Python scripts they came from.
