#ifndef URL_H
#define URL_H

/* Finding a web address in text: for the Markdown preview, where a link is shown as "text (http://...)" and a click on the address
 * should open it.  Plain C so that it can be tested on the host. */

#ifndef U16_DEFINED
#define U16_DEFINED
typedef unsigned short u16;
#endif

/* If t[pos] is inside an address (scheme://..., or mailto:...), returns its length and sets *start; otherwise 0.  The address ends at
 * white space, a quote or angle bracket, or a closing parenthesis that has no opening one inside the address; sentence punctuation
 * (. , ; : ! ?) after it is not part of it. */
unsigned url_at(const u16 *t, unsigned n, unsigned pos, unsigned *start);

/* The next address at or after `from`: returns its length (0 if none) and sets *start. */
unsigned url_next(const u16 *t, unsigned n, unsigned from, unsigned *start);

#endif
