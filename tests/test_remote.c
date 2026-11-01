#include "test.h"
#include "../core/remote.h"

int main(void)
{
    char uh[64], path[256], buf[512];
    unsigned long crc, len;

    CHECK(remote_parse("jade@host.example:/home/jade/a b.c", uh, sizeof uh, path, sizeof path));
    CHECK(strcmp(uh, "jade@host.example") == 0 && strcmp(path, "/home/jade/a b.c") == 0);
    CHECK(remote_parse("sparc:~/src/x.c", uh, sizeof uh, path, sizeof path) && strcmp(uh, "sparc") == 0 && strcmp(path, "~/src/x.c") == 0);
    CHECK(remote_parse("h:rel:with:colons", uh, sizeof uh, path, sizeof path) && strcmp(path, "rel:with:colons") == 0);
    CHECK(!remote_parse("nocolon", uh, sizeof uh, path, sizeof path));
    CHECK(!remote_parse(":/x", uh, sizeof uh, path, sizeof path));
    CHECK(!remote_parse("host:", uh, sizeof uh, path, sizeof path));
    CHECK(!remote_parse("a b:/x", uh, sizeof uh, path, sizeof path));
    CHECK(!remote_parse("-oProxy=x:/y", uh, sizeof uh, path, sizeof path));       /* an option, not a host */
    CHECK(!remote_parse("@h:/x", uh, sizeof uh, path, sizeof path) && !remote_parse("u@:/x", uh, sizeof uh, path, sizeof path));
    CHECK(!remote_parse("host;rm:/x", uh, sizeof uh, path, sizeof path));
    CHECK(!remote_parse("verylonghostname:/x", uh, 5, path, sizeof path));

    CHECK(remote_shq("plain", buf, sizeof buf) == 7 && strcmp(buf, "'plain'") == 0);
    CHECK(remote_shq("it's", buf, sizeof buf) == 9 && strcmp(buf, "'it'\\''s'") == 0);
    CHECK(remote_shq("a b;$(x)", buf, sizeof buf) == 10 && strcmp(buf, "'a b;$(x)'") == 0);
    CHECK(remote_shq("long string", buf, 4) == 13 && strlen(buf) == 3);              /* too small: reports the size, does not overrun */
    remote_path_arg("~/src/it's.c", buf, sizeof buf);
    CHECK(strcmp(buf, "\"$HOME\"/'src/it'\\''s.c'") == 0);
    remote_path_arg("~", buf, sizeof buf);
    CHECK(strcmp(buf, "\"$HOME\"") == 0);
    remote_path_arg("/abs/path", buf, sizeof buf);
    CHECK(strcmp(buf, "'/abs/path'") == 0);
    remote_path_arg("~user/x", buf, sizeof buf);
    CHECK(strcmp(buf, "'~user/x'") == 0);                                            /* only ~/ is understood */

    remote_command("/usr/local/bin/ssh", 1, "-p 2222", "me@h", "cat 'f'", buf, sizeof buf);
    CHECK(strcmp(buf, "'/usr/local/bin/ssh' -o BatchMode=yes -p 2222 'me@h' 'cat '\\''f'\\'''") == 0);
    remote_command("stepssh", 0, "", "h", "cat x", buf, sizeof buf);
    CHECK(strcmp(buf, "'stepssh' 'h' 'cat x'") == 0);
    CHECK(remote_command("stepssh", 0, NULL, "h", "cat x", NULL, 0) == strlen("'stepssh' 'h' 'cat x'"));

    CHECK(remote_cksum((const unsigned char *)"123456789", 9) == 930766865UL);       /* the known POSIX value */
    CHECK(remote_cksum((const unsigned char *)"", 0) == 4294967295UL);
    CHECK(remote_cksum((const unsigned char *)"abc\n", 4) == remote_cksum((const unsigned char *)"abc\n", 4));
    CHECK(remote_cksum((const unsigned char *)"abc\n", 4) != remote_cksum((const unsigned char *)"abd\n", 4));
    CHECK(remote_parse_cksum("930766865 9\n", &crc, &len) && crc == 930766865UL && len == 9);
    CHECK(remote_parse_cksum("  12 34 file\n", &crc, &len) && crc == 12 && len == 34);
    CHECK(!remote_parse_cksum("cksum: no such file", &crc, &len) && !remote_parse_cksum("12", &crc, &len) && !remote_parse_cksum("", &crc, &len));
    TEST_DONE("test_remote");
}
