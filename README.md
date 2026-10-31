# JOSE -- Jade's OPENSTEP Editor

A programmer's text editor for OPENSTEP 4.2 (Mach, i386 / m68k / SPARC), with syntax highlighting.
The aim is approximate feature parity with NEdit.  Plain Objective-C and C for gcc 2.7.2; no libraries beyond the
OpenStep Foundation and AppKit. 

Status: **prototype (0.0.1)** -- nothing here has been run on OPENSTEP yet.

## What works so far

* One window per file: open, save, save as, revert, close (with the usual question about unsaved changes).
* Syntax highlighting by [HighlighterKit](hk/) (LGPL; see `hk/COPYING.LGPL`), applied lazily to what is on screen.
  The mode is chosen from the file name and can be changed from *Preferences > Language Mode*.
  Syntax files are in `syntax/` and are installed in `JOSE.app/syntax/`; add more there.
* Line endings (LF, CRLF, CR) are detected on load and kept on save; UTF-8 is read and written (invalid bytes read as Latin-1).
* Status line (line, column, mode, line ending), Go to Line, optional line wrapping, optional line numbers, matching brackets.
* Find/Replace with regular expressions; auto-indent, shift left/right, comment/uncomment; saved preferences.
* **Fill Paragraph** (Edit, cmd-J): re-flows the selected lines, or the paragraph around the insertion point, to the
  *Preferences > Fill Width*.  A comment leader (`//`, `#`, `*`, `>`, `;`, `--`) and the indentation are kept, and the second
  line's indentation is used for the rest (hanging indents).
* **Rectangular selection**: Option-drag.  Copy, Cut, Delete and Backspace work on the rectangle; typing puts the text into
  every line of it (a rectangle with no width is a column of insertion points); Paste puts a block back as a rectangle
  (when the pasteboard holds what Copy took from one), or line by line into a rectangle.  Columns are screen columns of
  the fixed-pitch font, a tab going to the next multiple of 8, and it is meant to be used with *Wrap Lines* off.
* **Shell** menu: *Filter Selection...* (cmd-|) passes the selection, or all the text, through a command and replaces it with
  the output; *Execute Command...* (cmd-!) inserts what a command prints; *Sort Lines*.  Commands run under `/bin/sh` in the
  file's folder; the editor waits for them for up to a minute.  Output on stderr or a non-zero status is shown in an alert
  and, for a failure, the text is left alone.

* **Code folding** (Edit > Fold/Unfold Block, cmd-K; Fold All Blocks; Expand All Blocks): collapses the block between matching
  braces, the one that opens on the insertion point's line, closes on it, or surrounds it, into `{ ... 12 lines ~7 }`.
  Click the marker, or press cmd-K on its line, to open it again.  Fold All Blocks folds every outermost block that spans
  several lines (every function body, in C).  The hidden code stays in the document: Save writes it in full, Copy and Cut
  put it on the pasteboard in full, line numbers and the status line count it, folds are undone and redone like any edit, and
  folding does not make a clean file dirty.  What a fold cannot do: a marker cannot be edited in part (it is refused, or opens
  if you select into it), and Find sees only the markers, not the folded code; Go to Line, Fill, rectangular selection and
  Replace All open all folds first.  Folds are not remembered when a file is closed.

## Syntax files

HighlighterKit's `.syntax` files are property lists of contexts.  JOSE adds one key: a context may have a `Parent`
(the index of another context in the list; 0, the default context, if it is left out), which makes it a context that begins
*inside* its parent, so the contexts form a tree.  The C modes use this for `<header>`, `"header"` and comments inside a
preprocessor line, and Shell for `${var}` and `$(cmd)` inside double quotes.  A nested context ends at its own `Ending`, or
where the ending of any context around it is found (which also ends everything in between), so an unfinished one never runs
past the end of its parent.  Patterns use HighlighterKit's own pattern syntax (`<` and `>` mean word start/end: write `\\<`
for a literal one).

## Roadmap towards NEdit

Roughly in this order; the list is not a promise.

1. Search: Find, Replace, Find Again/Previous, Find Selection, regular expressions, case/word options, Replace All and In Selection (one undo step) -- done, awaiting a check on 4.2; multi-file replace still to do.
2. Editing: undo/redo, auto-indent, smart indent (brace languages, Python), shift left/right, comment/uncomment, spaces-for-tabs
   and indent width -- done and checked on 4.2; match brace, line numbers and saved settings -- done and checked;
   fill paragraph, rectangular selection, shell commands -- done and checked; code folding -- done, awaiting a check on 4.2.
3. Highlighting: nested contexts -- done (see above), awaiting a check on 4.2; more language modes, a preferences panel for
   the colours and fonts.
4. Shell commands (filter, execute, sort) -- done, awaiting a check on 4.2; a macro language, learn/replay, tags files (ctags)
   with call tips, split panes, a files menu with recent files.
5. Preferences saved per language mode.

## Building

```
make -f Makefile.openstep test     # the C unit tests, with the real compiler
make -f Makefile.openstep          # build JOSE.app
```

On a development Mac (not for OPENSTEP): `make test lint check-objc hk-smoke doc-smoke`.

## Licence

MIT for JOSE's own sources.  The `hk/` directory is HighlighterKit 0.1.3 by Saso Kiselkov under the LGPL 2.1 or later,
with the changes described at the top of `hk/HKCompat.h` and in the git history.
