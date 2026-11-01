#include "remote.h"
#include <string.h>

static int host_char(int c)
{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '.' || c == '-' || c == '_' || c == '@';
}

int remote_parse(const char *spec, char *userhost, size_t uhcap, char *path, size_t pcap)
{
    const char *colon = strchr(spec, ':');
    size_t hl, pl;
    const char *p;

    if (colon == NULL || colon == spec) return 0;
    hl = (size_t)(colon - spec);
    for (p = spec; p < colon; p++) if (!host_char((unsigned char)*p)) return 0;
    if (spec[0] == '@' || spec[hl - 1] == '@' || spec[0] == '-') return 0;      /* no host; or an option in disguise */
    pl = strlen(colon + 1);
    if (pl == 0 || hl >= uhcap || pl >= pcap) return 0;
    memcpy(userhost, spec, hl);
    userhost[hl] = '\0';
    memcpy(path, colon + 1, pl + 1);
    return 1;
}

size_t remote_shq(const char *s, char *out, size_t cap)
{
    size_t n = 0;
    const char *p;

#define PUT(ch) do { if (n + 1 < cap) out[n] = (char)(ch); n++; } while (0)
    PUT('\'');
    for (p = s; *p != '\0'; p++) {
        if (*p == '\'') { PUT('\''); PUT('\\'); PUT('\''); PUT('\''); }
        else PUT(*p);
    }
    PUT('\'');
    if (cap > 0) out[n < cap ? n : cap - 1] = '\0';
    return n;
#undef PUT
}

size_t remote_path_arg(const char *path, char *out, size_t cap)
{
    size_t n = 0, m;

    if (path[0] == '~' && path[1] == '/') {
        static const char home[] = "\"$HOME\"/";

        n = sizeof home - 1;
        if (cap > n) memcpy(out, home, n);
        m = remote_shq(path + 2, cap > n ? out + n : out, cap > n ? cap - n : 0);
        return n + m;
    }
    return remote_shq(path, out, cap);
}

size_t remote_command(const char *prog, int batch, const char *extra, const char *userhost, const char *remote_cmd,
                      char *out, size_t cap)
{
    size_t n = 0, m;

    m = remote_shq(prog, cap > n ? out + n : out, cap > n ? cap - n : 0);
    n += m;
    if (batch) {
        static const char b[] = " -o BatchMode=yes";

        if (cap > n + sizeof b) memcpy(out + n, b, sizeof b - 1);
        n += sizeof b - 1;
    }
    if (extra != NULL && extra[0] != '\0') {
        size_t el = strlen(extra);

        if (cap > n + 1 + el) { out[n] = ' '; memcpy(out + n + 1, extra, el); }
        n += 1 + el;
    }
    if (cap > n + 1) out[n] = ' ';
    n += 1;
    n += remote_shq(userhost, cap > n ? out + n : out, cap > n ? cap - n : 0);
    if (cap > n + 1) out[n] = ' ';
    n += 1;
    n += remote_shq(remote_cmd, cap > n ? out + n : out, cap > n ? cap - n : 0);
    if (cap > 0) out[n < cap ? n : cap - 1] = '\0';
    return n;
}

static unsigned long crc_table[256];
static int crc_ready;

static void crc_init(void)
{
    unsigned long i, j, c;

    for (i = 0; i < 256; i++) {
        c = i << 24;
        for (j = 0; j < 8; j++) c = (c & 0x80000000UL) ? ((c << 1) ^ 0x04C11DB7UL) : (c << 1);
        crc_table[i] = c & 0xFFFFFFFFUL;
    }
    crc_ready = 1;
}

unsigned long remote_cksum(const unsigned char *b, size_t n)
{
    unsigned long crc = 0, len = (unsigned long)n;
    size_t i;

    if (!crc_ready) crc_init();
    for (i = 0; i < n; i++) crc = ((crc << 8) ^ crc_table[((crc >> 24) ^ b[i]) & 0xFF]) & 0xFFFFFFFFUL;
    while (len != 0) {
        crc = ((crc << 8) ^ crc_table[((crc >> 24) ^ len) & 0xFF]) & 0xFFFFFFFFUL;
        len >>= 8;
    }
    return (~crc) & 0xFFFFFFFFUL;
}

int remote_parse_cksum(const char *text, unsigned long *crc, unsigned long *length)
{
    unsigned long a = 0, b = 0;
    const char *p = text;

    while (*p == ' ' || *p == '\t' || *p == '\n') p++;
    if (*p < '0' || *p > '9') return 0;
    while (*p >= '0' && *p <= '9') a = a * 10 + (unsigned long)(*p++ - '0');
    if (*p != ' ' && *p != '\t') return 0;
    while (*p == ' ' || *p == '\t') p++;
    if (*p < '0' || *p > '9') return 0;
    while (*p >= '0' && *p <= '9') b = b * 10 + (unsigned long)(*p++ - '0');
    *crc = a;
    *length = b;
    return 1;
}
