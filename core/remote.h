#ifndef REMOTE_H
#define REMOTE_H

/* Remote editing over ssh: reading and writing a file by running `cat` on the far side.  This is the plain-C part -- parsing
 * `[user@]host:path`, quoting for the two shells involved, building the command line, and the POSIX `cksum` that tells whether the
 * file changed behind our back -- so that it can be tested on the host.  The program that is run (stepssh, or OpenSSH's ssh) and what
 * is done with the result belong to app/RemoteController. */

#include <stddef.h>

/* `[user@]host:path` -> user@host (as typed) and path.  The path must not be empty; the host holds only letters, digits and
 * . - _ @ .  Returns 1 if it parsed. */
int remote_parse(const char *spec, char *userhost, size_t uhcap, char *path, size_t pcap);

/* s in single quotes for a shell (a quote inside it as '\''). Returns the length needed (excluding the NUL), and writes the quoted
 * string if cap is big enough. */
size_t remote_shq(const char *s, char *out, size_t cap);

/* The remote shell's form of a path: quoted, except that a leading ~/ becomes "$HOME"/ so that it still means the home folder. */
size_t remote_path_arg(const char *path, char *out, size_t cap);

/* The local command line:  'prog' [-o BatchMode=yes] [extra] 'userhost' 'remote command'.  `batch` adds the BatchMode option (OpenSSH
 * only: it keeps ssh from waiting for a password that nobody can type); `extra` is split by the local shell as it stands.  Returns the
 * length needed (excluding the NUL). */
size_t remote_command(const char *prog, int batch, const char *extra, const char *userhost, const char *remote_cmd,
                      char *out, size_t cap);

/* POSIX cksum of some bytes (the CRC, with the length mixed in).  `cksum < file` prints "<crc> <length>" for the same bytes. */
unsigned long remote_cksum(const unsigned char *b, size_t n);

/* Reads "<crc> <length>" from the start of the text.  Returns 1 if it did. */
int remote_parse_cksum(const char *text, unsigned long *crc, unsigned long *length);

#endif
