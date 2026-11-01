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
  skipped, and so are here-documents (`<<EOF`, `<<-EOF`, `<<'EOF'`, several on one line; Ruby `<<~EOS`) and, in Ruby, `/regexp/`,
  `%w[...]` and `%r{...}` literals, which could hide a keyword.
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
* **Find Unmatched Bracket / Keyword** (Search menu, cmd-U): reads the whole file for a `( ) [ ] { }` without a partner and selects
  the first one after the insertion point; press it again for the next, and it wraps round.  The status line says which problem
  it is on ("Problem 2 of 5: '}' closes nothing").  A closing bracket with nothing open, one that does not fit the bracket open
  before it, and an opener that is never closed are all found; where a closer matches an opener further out, the brackets it
  skipped over are the ones reported -- which is where a closing bracket is missing.  In the shell, csh, zsh, Ruby and C modes
  block keywords are checked too: `if` without `fi`, `case` without `esac`, a loop without `done` (a `fi` does not close a
  `while`; nor does an `else` belong in a loop, a `do` in an `if`, a Ruby `when` in an `if` or an `elsif` in a `case`), Ruby `def`/`if`/`do` without `end`, `#if` without `#endif`, and a stray `else`/`#elif`.  Strings, character constants
  and comments are skipped in the C-like modes.  When there are problems, the first `}` that starts its line but is not indented
  like the line that opened its block is listed too, because an extra or missing brace shows up there long before the place where
  the counts finally run out.  If everything is paired it says so.
* **Markdown preview** (Windows > Markdown Preview, shift-cmd-P; works on any window): a read-only window beside the document shows its
  text formatted -- headings, emphasis, lists, quotes, code blocks, tables, links as "text (address)" -- made by MarkStep's Markdown-to-RTF
  converter and shown by the ordinary text view.  It follows the document half a second after each edit and keeps about the same
  place in the text as the document is scrolled to; closing the document closes it.  *Preferences > Markdown...* chooses how accents
  are written into the RTF (NeXTSTEP by default on OPENSTEP; try Windows-1252 if letters come out wrong) and how links show.
  Web addresses in the preview show in blue, and a click on one runs the browser set in *Preferences > Markdown...* (default
  `/LocalApps/OmniWeb.app`; any `.app`, such as NetSurf, or any program will do): its executable gets the arguments you give and then the
  address (or `%u` in the arguments stands for it).  Addresses show only with *Links* set to *Text (address)* or *Show the address*.
  `.md`, `.markdown`, `.mkd` and `.mdown` files open in a Markdown mode that colours headings, quotes, fenced code and HTML comments.
* **Remote editing** (File > Open Remote..., shift-cmd-O): opens `[user@]host:path` (`me@sparc:/home/me/x.c`, or `sparc:~/x.c` for the
  home folder) in a window titled with that name, by running `stepssh host 'cat path'` -- or OpenSSH's `ssh` instead; *Preferences >
  Remote Editing...* picks which (default StepSSH at `/usr/local/bin/stepssh`; OpenSSH at `/usr/local/bin/ssh`, run with
  `BatchMode`), where it is, and extra arguments such as `-p 2222` or `-i keyfile`.  Save writes the text back the same way (into
  `path.jose-tmp` first, then over the file, so a dropped connection leaves the original alone) after asking the far side's `cksum`
  whether the file changed since it was read -- if it did, you are asked before it is overwritten.  Line endings are kept; only UTF-8
  text is opened; a path that does not exist can be created.  Revert to Saved fetches it again.  The program must log in without
  asking anything (a key; with OpenSSH an agent), and the host key must be known already (connect once from a terminal).  Save As
  makes a local copy.  Remote windows are not part of sessions, and Open Included File, tags and the like see no local file.
* **Word completion** (Edit > Complete Word, cmd-I; Complete Word, Previous, shift-cmd-I): finishes the word before the insertion point
  and, pressed again, goes on to the next candidate -- then back to the word as typed, and round again; shift-cmd-I goes the other way.
  Candidates, in this order: words of this text, nearest first (before the word, then after it); words of the other open windows
  (the first 400,000 characters of each); the keywords of the language mode; names from loaded tags files; and, in the C family, the identifiers of the headers the file includes
  (`#include`/`#import`, found next to the file and along the include path of Preferences, and the headers those include -- two levels, at
  most 80 files and 3 MB; read once per document and remembered until its include lines change, so the first completion in a file can
  pause on a slow machine).  Names of three letters or more are kept, which covers Objective-C method names and constants.  Case counts; if nothing
  matches, it is ignored.  Each press replaces the last candidate, so one Undo takes the whole completion out; any other edit or
  move of the insertion point ends the cycle.  The status line says which candidate it is on.
* **Clipboard history** (Edit > Paste from History; Edit > Clipboard History..., shift-cmd-V): the last thirty things cut or copied in JOSE --
  and, whenever JOSE becomes the active program again, what was copied elsewhere -- newest first.  Choosing one from the submenu makes it
  the current clipboard (so cmd-V pastes it too) and pastes it at once; the panel lists them with a longer look at the selected one and
  can paste, make current, delete or clear.  Something copied from a rectangle stays a rectangle.  Anything over 400,000 bytes is not kept,
  and the history lives in memory only.  (Several copies made one after another in another program, without JOSE becoming active
  between, are seen only as the last.)
* **Files dropped on the icon**: a file dragged from Workspace onto JOSE's icon (or opened with it) opens in a window, whether JOSE is
  running or is started by the drop; several files at once open together.  (JOSE does not claim any file type, so double-clicking a
  file in Workspace still opens it with whatever Workspace has chosen for that type.)
* **Sessions** (File > Sessions): *Save Session As...* keeps the windows that show files -- with each caret, scroll position, window
  frame and wrap setting -- as a named set in `~/.JOSE.sessions`; *Save Session* writes it again under the current name.  *Open
  Session* adds a saved set to what is open; *Switch to Session* first closes the windows that are not in it (asking about unsaved
  work, and leaving the ones that are in it alone); *Delete Session* removes one.  The windows open now are also kept as the *last
  session* each time one opens or closes, and at quit, so *Reopen Last Session* brings them back; with *Preferences > Reopen the
  last session's files when JOSE starts* (off by default) that happens at launch, unless files are named on the command line.
  Windows without a file are not part of a session, and files that have gone are skipped (and counted).
* **Split panes** (Windows > Split Pane, cmd-2; Close Pane, cmd-1): the window shows the same text in two panes, one above the
  other, each with its own scroll position, selection, line numbers and fold margin.  Edits, undo, folds and highlighting are
  shared; the commands act on the pane with the insertion point.  Close Pane closes that one and the other fills the window.
* **Find in Files** (Search > Find in Files..., shift-cmd-F): looks for text in the files of a folder -- or, with *Search in: Open files*, in the open windows, saved
  or not, matched by file name and replaced in the windows with Undo -- with the same case, regular
  expression and whole-word options as Find, a list of file-name patterns (`*.c *.h`; `*` and `?`), and subfolders on or off
  (`.`-folders and `CVS` are skipped).  The matching lines are listed as `file:line: text`; double-click one to open the file
  there.  *Replace All...* replaces in every file with a match, after asking.  A file open in a window is searched as it stands
  there and changed there (one undo step, not saved); the others are rewritten on disk, each kept as `name.bak` if that is ticked.
  Files that are not UTF-8 text (or are over 4 MB) are never searched, and a file that mixes line endings is never rewritten; the
  message line says how many were left out.  While it runs the panel stays alive: *Stop* (or closing the panel) ends it, and nothing else in the program responds until it is over.
* **Per-mode preferences** (Preferences > Preferences Panel > Language Modes...): each language mode may override the indent width,
  spaces for indentation, auto indent and line wrapping; a setting left at "Same as general" follows the Preferences menu.  The
  overrides apply when a file is opened or saved under a name, or the mode is chosen by hand, and at once to windows already in
  that mode.  (They win over the menu: the menu items change the general setting.)  Saved as `ModePrefs`, one line per mode.
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
(`BSDmakefile`, `bsd.*.mk`), Imake (`Imakefile`, `*.tmpl`, `*.rules`), property lists, `.strings`, GSmarkup, ChangeLogs, Markdown and plain
text.  The mode is chosen from the file name, a `#!` line, or by hand from *Preferences > Language Mode*.  A file named `Makefile` or
`makefile` is taken to be BSD make (OPENSTEP's own `make`); `GNUmakefile`, `*.mk` and `Makefile.openstep`/`.preamble`/`.postamble` are
taken to be GNU make.  Switch by hand from *Language Mode* where that is wrong.  Ruby folds and matches
`def`/`class`/`if`/`do`...`end`; JSON and JavaScript fold arrays as well as objects; Imake files use the C preprocessor rules for
matching and `XCOMM` for comment/uncomment.  The Ruby, JavaScript, JSON, BSD make, Imake and zsh syntax files are written by
`tools/gen_syntax.py`; change that, not the files.  Not understood: JavaScript regular expression literals, and the bracket matcher still counts brackets
inside here-documents, Ruby regular expressions and `%w[]`-style literals.

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

1. Search: Find, Replace, Find Again/Previous, Find Selection, regular expressions, case/word options, Replace All and In Selection (one undo step) -- done, awaiting a check on 4.2; multi-file search and replace (Find in Files) -- done, awaiting a check on 4.2.
2. Editing: undo/redo, auto-indent, smart indent (brace languages, Python), shift left/right, comment/uncomment, spaces-for-tabs
   and indent width -- done and checked on 4.2; match brace, line numbers and saved settings -- done and checked;
   fill paragraph, rectangular selection, shell commands -- done and checked; code folding -- done and checked.
3. Highlighting: nested contexts -- done and checked; the Preferences panel (colours, dark mode, font), recent files, Open Included
   File, tags with call tips and the fold margin -- done, awaiting a check on 4.2; more language modes.
4. Shell commands (filter, execute, sort) -- done and checked; per-mode preferences -- done, awaiting a check on 4.2; split panes -- done, awaiting a check on 4.2.

## Building

```
make -f Makefile.openstep test     # the C unit tests, with the real compiler
make -f Makefile.openstep          # build JOSE.app
```

On a development Mac (not for OPENSTEP): `make test lint check-objc hk-smoke doc-smoke`.

## Third-party code

* `hk/` is HighlighterKit by Saso Kiselkov (LGPL), adapted.
* `core/md*.c`, `core/md*.h` and `core/nsenc*` are MarkStep's Markdown parser and RTF writer (MIT, by the author of JOSE; MarkStep's own
  repository has the full CommonMark test suite).  `nsenc` is the NeXTSTEP character-set table that StepTTY also uses.

## Licence

MIT for JOSE's own sources.  The `hk/` directory is HighlighterKit 0.1.3 by Saso Kiselkov under the LGPL 2.1 or later,
with the changes described at the top of `hk/HKCompat.h` and in the git history.
