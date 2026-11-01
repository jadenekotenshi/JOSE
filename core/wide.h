#ifndef WIDE_H
#define WIDE_H

/* How many cells a character takes in a fixed-width display: 2 for East Asian wide and fullwidth characters, 0 for combining marks and
 * zero-width characters, 1 otherwise.  (A surrogate pair is two units; give the pair's code point to wide_cp.)  Plain C. */

int wide_cp(unsigned long cp);
int wide_unit(unsigned c);        /* for one UTF-16 unit: a surrogate half counts 0 for the low half and 2 for the high half, so a pair is 2 */

#endif
