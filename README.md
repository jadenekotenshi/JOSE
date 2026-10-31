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
* Status line (line, column, mode, line ending), Go to Line, optional line wrapping, optional line numbers, matching brackets
  (`( ) [ ] { }`, and in shell scripts and the C family also the keyword pairs below).
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

* **Matching keyword pairs** (Search > Go to / Select to Matching Bracket, with the insertion point on or next to the word):
  shell `if`/`fi`, `case`/`esac`, `for`/`while`/`until`/`select`/`done`, and `then`, `elif`, `else`, `do` (which go to the end of
  their block); csh `if (...) then`/`endif`, `foreach`/`while`/`end`, `switch`/`endsw`; C-family `#if`, `#ifdef`, `#ifndef`/`#endif`,
  with `#else` and `#elif`.  A word only counts where a command can start, so `echo if` is left alone; comments and quoted text are
  skipped.  (Not understood: here-documents, which may hide a keyword at the start of a line.)
* **Code folding** (Edit > Fold/Unfold Block, cmd-K; Fold All Blocks; Expand All Blocks): collapses the block between matching
  braces, the one that opens on the insertion point's line, closes on it, or surrounds it, into `{ ... 12 lines ~7 }`.
  How a block is found depends on the mode: braces for the C family and most others; **indentation for Python** (the line with
  the insertion point if the next line is indented more, else the nearest line above that is indented less; blank lines at the end
  stay out of it); **keyword pairs for shell and csh** (`if`...`fi`, `for`...`done`, `case`...`esac`: the closing word stays visible
  after the marker).  Click the marker, or press cmd-K on its line, to open it again.  Fold All Blocks folds every outermost block that spans
  several lines (every function body, in C).  The hidden code stays in the document: Save writes it in full, Copy and Cut
  put it on the pasteboard in full, line numbers and the status line count it, folds are undone and redone like any edit, and
  folding does not make a clean file dirty.  What a fold cannot do: a marker cannot be edited in part (it is refused, or opens
  if you select into it), and Find sees only the markers, not the folded code; Go to Line, Fill, rectangular selection and
  Replace All open all folds first.  Folds are not remembered when a file is closed.

* **Preferences panel** (Preferences > Preferences Panel..., cmd-,): Light or Dark colours (light text on a dark background, with the
  syntax colours lightened to match), the background and text colours, the font and size (any fixed-pitch font installed), the
  include path, call tips and the fold margin.  Changes show in every window at once and are saved.
* **Fold margin**: a `-` beside every line where a block begins and a `+` beside every folded one, next to the line numbers (or
  alone, if they are off).  Click it to fold or unfold.  It is rescanned shortly after you stop typing, and left empty for files of
  more than three million characters.
* **File > Open Recent** (twelve files, saved) and **File > Open Included File** (cmd-D): opens the file named by the `#include`,
  `#import`, Python `import`/`from`, shell `.`/`source`, Perl `use`/`require` or make `include` on the insertion point's line --
  or the selected name, or the file name under the insertion point -- in a window of its own.  It looks next to the current file,
  then along the include path of the Preferences panel (`Foo/Bar.h` is also tried as `Foo.framework/Headers/Bar.h`).
* **Tags** (Search menu): a ctags file called `tags` in the document's folder or one above it is found by itself; others can be
  loaded with *Load Tags File...*.  *Find Definition* (cmd-T) opens the definition of the selected name, or the name at the
  insertion point (a chooser appears if there are several), in a window of its own; *Return from Definition* (shift-cmd-T) goes
  back.  A call tip -- the declaration line from the tags file -- appears when you type `(` after a tagged name (switchable in
  the Preferences panel), or with *Show Call Tip* (cmd-9).  The tags file is read again when it changes.

## Macros

*Macro > Learn Macro* (shift-cmd-L) starts learning; the status line says "Learning a macro"; *Stop Learning* ends it.  *Replay Macro*
(cmd-Y) runs it again in the front window, and *Repeat Macro...* (shift-cmd-Y) runs it a number of times or until it fails (a
search that finds nothing, say).  The last macro is kept between sessions; *Save Macro As...* names it, and *Run Macro* and
*Edit Macro* list the saved ones (in `~/.JOSE.macros`).  *Macro as Text* shows the learned macro in a window.

What is learned is not keystrokes but *actions*: typed text (one insert for a run of keys), key actions such as the arrows, Return,
Tab, Delete, word and line movement, selecting, Cut/Copy/Paste, menu commands (shift, comment, fill, fold, brackets, undo), searches
and replacements with their settings, and filters and executed commands.  Nothing is learned from the mouse, so start a macro at a
place that a key or a search can find again.  Because the result is a short text, macros can be read, edited and written by hand:

    # JOSE macro
    # find: f or b (forward/backward), c case sensitive, r regular expression, w whole word, p wrap around
    find fcp "TODO"
    action moveToEndOfLine:
    insert "  /* done */"
    # replace-all (or replace-sel): in a regular expression replacement \\1 is a group
    replace-all fcp "foo" "bar"
    # commands: shift-left shift-right comment uncomment fill-paragraph fold-toggle fold-all expand-all
    #           match-bracket select-bracket undo redo
    command shift-right
    filter "sort -r"
    exec "date"

A line may end with a # comment after its last string.  Strings take \\ \" \n \t \r \xHH, so a backslash in a regular expression is written twice.  A macro stops at the first line that cannot
be done.  Only text-view actions (keys) may appear in `action` lines.

## Language modes

C, C++, Objective-C and C headers, Python, Perl, Ruby, JavaScript, JSON, shell (sh/ksh/bash), zsh, csh/tcsh, GNU make, BSD make
(`BSDmakefile`, `bsd.*.mk`), Imake (`Imakefile`, `*.tmpl`, `*.rules`), property lists, `.strings`, GSmarkup, ChangeLogs and plain
text.  The mode is chosen from the file name, a `#!` line, or by hand from *Preferences > Language Mode*.  Plain `Makefile`s and
`*.mk` files are taken to be GNU make; switch to *BSDMakefile* by hand where that is wrong.  Ruby folds and matches
`def`/`class`/`if`/`do`...`end`; JSON and JavaScript fold arrays as well as objects; Imake files use the C preprocessor rules for
matching and `XCOMM` for comment/uncomment.  The Ruby, JavaScript, JSON, BSD make, Imake and zsh syntax files are written by
`tools/gen_syntax.py`; change that, not the files.  Not understood: Ruby and shell here-documents, JavaScript regular expression
literals, and Ruby `%w[]`-style literals.

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
   fill paragraph, rectangular selection, shell commands -- done and checked; code folding -- done and checked.
3. Highlighting: nested contexts -- done and checked; the Preferences panel (colours, dark mode, font), recent files, Open Included
   File, tags with call tips and the fold margin -- done, awaiting a check on 4.2; more language modes.
4. Shell commands (filter, execute, sort) -- done and checked; still to do: split panes,
   per-mode preferences.

## Building

```
make -f Makefile.openstep test     # the C unit tests, with the real compiler
make -f Makefile.openstep          # build JOSE.app
```

On a development Mac (not for OPENSTEP): `make test lint check-objc hk-smoke doc-smoke`.

## Licence

MIT for JOSE's own sources.  The `hk/` directory is HighlighterKit 0.1.3 by Saso Kiselkov under the LGPL 2.1 or later,
with the changes described at the top of `hk/HKCompat.h` and in the git history.
