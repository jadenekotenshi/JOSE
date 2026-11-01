#include "eol.h"

int eol_detect(const char *text, size_t n, int *mixed)
{
    size_t i;
    size_t lf = 0, crlf = 0, cr = 0;
    int kinds;

    for (i = 0; i < n; i++) {
        if (text[i] == '\n') lf++;
        else if (text[i] == '\r') {
            if (i + 1 < n && text[i + 1] == '\n') { crlf++; i++; }
            else cr++;
        }
    }
    kinds = (lf > 0) + (crlf > 0) + (cr > 0);
    if (mixed != NULL) *mixed = kinds > 1;
    if (crlf > lf && crlf >= cr) return EOL_CRLF;
    if (cr > lf && cr > crlf) return EOL_CR;
    return EOL_LF;
}

size_t eol_normalize(char *text, size_t n)
{
    size_t i, o = 0;

    for (i = 0; i < n; i++) {
        if (text[i] == '\r') {
            if (i + 1 < n && text[i + 1] == '\n') i++;
            text[o++] = '\n';
        } else if (text[i] == '\0') {
            text[o++] = ' ';
        } else {
            text[o++] = text[i];
        }
    }
    return o;
}

size_t eol_expanded_size(const char *text, size_t n, int eol)
{
    size_t i, extra = 0;

    if (eol != EOL_CRLF) return n;
    for (i = 0; i < n; i++)
        if (text[i] == '\n') extra++;
    return n + extra;
}

size_t eol_expand(const char *text, size_t n, int eol, char *out)
{
    size_t i, o = 0;

    for (i = 0; i < n; i++) {
        if (text[i] == '\n') {
            if (eol == EOL_CRLF) { out[o++] = '\r'; out[o++] = '\n'; }
            else if (eol == EOL_CR) out[o++] = '\r';
            else out[o++] = '\n';
        } else {
            out[o++] = text[i];
        }
    }
    return o;
}

/* ---- UTF-16 ---- */

int eol16_detect(const u16 *text, size_t n, int *mixed)
{
    size_t i, lf = 0, crlf = 0, cr = 0;
    int kinds;

    for (i = 0; i < n; i++) {
        if (text[i] == '\n') lf++;
        else if (text[i] == '\r') {
            if (i + 1 < n && text[i + 1] == '\n') { crlf++; i++; }
            else cr++;
        }
    }
    kinds = (lf > 0) + (crlf > 0) + (cr > 0);
    if (mixed != NULL) *mixed = kinds > 1;
    if (crlf > lf && crlf >= cr) return EOL_CRLF;
    if (cr > lf && cr > crlf) return EOL_CR;
    return EOL_LF;
}

size_t eol16_normalize(u16 *text, size_t n)
{
    size_t i, o = 0;

    for (i = 0; i < n; i++) {
        if (text[i] == '\r') {
            if (i + 1 < n && text[i + 1] == '\n') i++;
            text[o++] = '\n';
        } else if (text[i] == 0) {
            text[o++] = ' ';
        } else {
            text[o++] = text[i];
        }
    }
    return o;
}

size_t eol16_expanded_size(const u16 *text, size_t n, int eol)
{
    size_t i, extra = 0;

    if (eol != EOL_CRLF) return n;
    for (i = 0; i < n; i++) if (text[i] == '\n') extra++;
    return n + extra;
}

size_t eol16_expand(const u16 *text, size_t n, int eol, u16 *out)
{
    size_t i, o = 0;

    for (i = 0; i < n; i++) {
        if (text[i] == '\n') {
            if (eol == EOL_CRLF) { out[o++] = '\r'; out[o++] = '\n'; }
            else if (eol == EOL_CR) out[o++] = '\r';
            else out[o++] = '\n';
        } else {
            out[o++] = text[i];
        }
    }
    return o;
}
