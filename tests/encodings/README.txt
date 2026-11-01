Test files in different text encodings, for trying File > Encoding by hand.

Each file starts with an ASCII line saying what it is.  Pilcrow guesses UTF-8 (or a byte order mark), and otherwise reads a file as
ISO-8859-1, so the legacy ones open as readable-looking garbage at first.  For each file:

  1. open it and look at the encoding in the status line;
  2. File > Encoding > Reopen with > <the encoding named in the first line> -- the text should now be what it says (where the fonts can
     show it: Latin and Cyrillic-with-boxes are one thing, Japanese/Chinese/Korean will show as boxes on a system without CJK fonts,
     but the status line and the line lengths still tell);
  3. press Save, then in a terminal:  git diff --stat tests/encodings   (or cmp the file against a fresh checkout).
     Nothing may have changed: the file must have been written back in its own encoding, byte for byte.

The files were made by tools on the development host (Python's codecs), so the bytes are what other programs would write.
