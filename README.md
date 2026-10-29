# StepEdit

A programmer's text editor for OPENSTEP 4.2 (Mach, i386 / m68k / SPARC), with syntax highlighting.
The aim is approximate feature parity with NEdit.  Plain Objective-C and C for gcc 2.7.2; no libraries beyond the
OpenStep Foundation and AppKit.  *Working name.*

Status: **prototype (0.0.1)** -- nothing here has been run on OPENSTEP yet.

## What works so far

* One window per file: open, save, save as, revert, close (with the usual question about unsaved changes).
* Syntax highlighting by [HighlighterKit](hk/) (LGPL; see `hk/COPYING.LGPL`), applied lazily to what is on screen.
  The mode is chosen from the file name and can be changed from *Preferences > Language Mode*.
  Syntax files are in `syntax/` and are installed in `StepEdit.app/syntax/`; add more there.
* Line endings (LF, CRLF, CR) are detected on load and kept on save; UTF-8 is read and written (invalid bytes read as Latin-1).
* Status line (line, column, mode, line ending), Go to Line, optional line wrapping.

## Roadmap towards NEdit

Roughly in this order; the list is not a promise.

1. Search: Find, Replace, Find Again, selection search, regular expressions, case/word options, multi-file replace.
2. Editing: undo/redo, auto-indent, smart indent for C, shift left/right, comment/uncomment, fill paragraph,
   rectangular selection and its operations, match brace, tabs/emulated tabs.
3. Highlighting: nested patterns (NEdit-style `.pats`), more language modes, a preferences panel for the colours and fonts.
4. Shell commands (filter selection through a command; run a command and show its output), a macro language,
   learn/replay, tags files (ctags) with call tips, split panes, line numbers, a files menu with recent files.
5. Preferences saved per language mode.

## Building

```
make -f Makefile.openstep test     # the C unit tests, with the real compiler
make -f Makefile.openstep          # build StepEdit.app
```

On a development Mac (not for OPENSTEP): `make test lint check-objc hk-smoke doc-smoke`.

## Licence

MIT for StepEdit's own sources.  The `hk/` directory is HighlighterKit 0.1.3 by Saso Kiselkov under the LGPL 2.1 or later,
with the changes described at the top of `hk/HKCompat.h` and in the git history.
