#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "test.h"
#include "macro.h"

static int parse(const char *line, MacroOp *op)
{
    char err[100];
    return macro_parse_line(line, op, err, sizeof err);
}

int main(void)
{
    MacroOp op;
    char err[100], *q;

    CHECK(parse("", &op) == 0 && op.kind == MOP_NONE);
    CHECK(parse("   # a comment", &op) == 0 && op.kind == MOP_NONE);
    CHECK(parse("insert \"hello\"", &op) == 0 && op.kind == MOP_INSERT && strcmp(op.s1, "hello") == 0);
    macro_op_free(&op);
    CHECK(parse("  insert  \"a\\tb\\n\\\"c\\\\\\x01\"  # more", &op) == 0 && strcmp(op.s1, "a\tb\n\"c\\\001") == 0);
    macro_op_free(&op);
    CHECK(parse("action moveWordForward:", &op) == 0 && op.kind == MOP_ACTION && strcmp(op.word, "moveWordForward:") == 0);
    CHECK(parse("command shift-right", &op) == 0 && op.kind == MOP_COMMAND && strcmp(op.word, "shift-right") == 0);
    CHECK(parse("find fcrwp \"a.*b\"", &op) == 0 && op.kind == MOP_FIND && strcmp(op.word, "fcrwp") == 0 && strcmp(op.s1, "a.*b") == 0);
    macro_op_free(&op);
    CHECK(parse("replace f \"x\" \"y\"", &op) == 0 && op.kind == MOP_REPLACE && strcmp(op.s1, "x") == 0 && strcmp(op.s2, "y") == 0);
    macro_op_free(&op);
    CHECK(parse("replace-all fcr \"(a)\" \"\\\\1\"", &op) == 0 && op.kind == MOP_REPLACE_ALL && strcmp(op.s2, "\\1") == 0);
    macro_op_free(&op);
    CHECK(parse("replace-sel f \"\" \"\"", &op) == 0 && op.kind == MOP_REPLACE_SEL && op.s1[0] == '\0');
    macro_op_free(&op);
    CHECK(parse("filter \"sort -r\"", &op) == 0 && op.kind == MOP_FILTER && strcmp(op.s1, "sort -r") == 0);
    macro_op_free(&op);
    CHECK(parse("exec \"date\"", &op) == 0 && op.kind == MOP_EXEC);
    macro_op_free(&op);
    CHECK(parse("insert \"caf\xc3\xa9\"", &op) == 0 && strcmp(op.s1, "caf\xc3\xa9") == 0);          /* UTF-8 passes through */
    macro_op_free(&op);
    /* errors */
    CHECK(macro_parse_line("dance", &op, err, sizeof err) == -1 && strstr(err, "unknown") != NULL);
    CHECK(macro_parse_line("insert hello", &op, err, sizeof err) == -1);
    CHECK(macro_parse_line("insert \"open", &op, err, sizeof err) == -1 && strstr(err, "closed") != NULL);
    CHECK(macro_parse_line("insert \"a\\q\"", &op, err, sizeof err) == -1 && strstr(err, "escape") != NULL);
    CHECK(macro_parse_line("action", &op, err, sizeof err) == -1);
    CHECK(macro_parse_line("find f", &op, err, sizeof err) == -1);
    CHECK(macro_parse_line("replace f \"a\"", &op, err, sizeof err) == -1);
    CHECK(macro_parse_line("insert \"a\" junk", &op, err, sizeof err) == -1 && strstr(err, "left over") != NULL);
    CHECK(macro_parse_line("insert\"a\"", &op, err, sizeof err) == -1);
    /* quoting round trip */
    q = macro_quote("a\"b\\c\n\t\001 end");
    CHECK(strcmp(q, "\"a\\\"b\\\\c\\n\\t\\x01 end\"") == 0);
    {
        char line[256];
        sprintf(line, "insert %s", q);
        CHECK(parse(line, &op) == 0 && strcmp(op.s1, "a\"b\\c\n\t\001 end") == 0);
        macro_op_free(&op);
    }
    free(q);
    TEST_DONE("macro");
}
