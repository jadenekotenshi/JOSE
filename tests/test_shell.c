#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test.h"
#include "shellrun.h"

int main(void)
{
    ShellResult r;
    char *big;
    size_t i;

    CHECK(shell_run("echo hello", NULL, NULL, 0, 5000, 0, &r) && strcmp(r.out, "hello\n") == 0 && r.status == 0 && r.nerr == 0);
    shell_result_free(&r);
    CHECK(shell_run("cat", NULL, "some input", 10, 5000, 0, &r) && strcmp(r.out, "some input") == 0 && r.nout == 10);
    shell_result_free(&r);
    CHECK(shell_run("sort", NULL, "b\na\nc\n", 6, 5000, 0, &r) && strcmp(r.out, "a\nb\nc\n") == 0);
    shell_result_free(&r);
    CHECK(shell_run("echo oops >&2; exit 3", NULL, NULL, 0, 5000, 0, &r) && r.status == 3 && strcmp(r.err, "oops\n") == 0 && r.nout == 0);
    shell_result_free(&r);
    CHECK(shell_run("nosuchcommand_zz", NULL, NULL, 0, 5000, 0, &r) && r.status == 127 && r.nerr > 0);
    shell_result_free(&r);
    CHECK(shell_run("pwd", "/tmp", NULL, 0, 5000, 0, &r) && strstr(r.out, "tmp") != NULL);
    shell_result_free(&r);
    /* a filter that is fed much more than a pipe holds must not deadlock */
    big = (char *)malloc(2000000);
    for (i = 0; i < 2000000; i++) big[i] = (char)('a' + i % 26);
    CHECK(shell_run("cat", NULL, big, 2000000, 20000, 0, &r) && r.nout == 2000000 && memcmp(r.out, big, 2000000) == 0);
    shell_result_free(&r);
    /* a command that never reads its input */
    CHECK(shell_run("echo done", NULL, big, 2000000, 20000, 0, &r) && strcmp(r.out, "done\n") == 0);
    shell_result_free(&r);
    free(big);
    CHECK(shell_run("sleep 5", NULL, NULL, 0, 300, 0, &r) && r.timed_out && r.status != 0);
    shell_result_free(&r);
    CHECK(shell_run("yes", NULL, NULL, 0, 5000, 1000, &r) == 1);
    CHECK(r.nout <= 1000 && r.truncated);
    shell_result_free(&r);
    TEST_DONE("shellrun");
}
