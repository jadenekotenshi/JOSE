# Host-side build & test (macOS/Linux).  The OPENSTEP build lives in Makefile.openstep.
CC      ?= cc
BUILD   = build
OBJCFLAGS = -x objective-c -fno-objc-arc -w -g -Ihk -Icore -Iapp

CFLAGS  = -std=c89 -pedantic -Wall -Wextra -Wdeclaration-after-statement \
          -Wno-long-long -Wno-unused-parameter -O2 -g -Icore

test: $(BUILD)/test_core $(BUILD)/test_search $(BUILD)/test_edit $(BUILD)/test_brace $(BUILD)/test_fill $(BUILD)/test_shell $(BUILD)/test_fold
	$(BUILD)/test_core
	$(BUILD)/test_search
	$(BUILD)/test_edit
	$(BUILD)/test_brace
	$(BUILD)/test_fill
	$(BUILD)/test_shell
	$(BUILD)/test_fold

$(BUILD)/test_fill: tests/test_fill.c tests/test.h core/fill.c core/fill.h core/rect.c core/rect.h
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) tests/test_fill.c core/fill.c core/rect.c -o $@

$(BUILD)/test_fold: tests/test_fold.c tests/test.h core/fold.c core/fold.h core/brace.c core/brace.h
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) tests/test_fold.c core/fold.c core/brace.c -o $@

$(BUILD)/test_shell: tests/test_shell.c tests/test.h core/shellrun.c core/shellrun.h
	mkdir -p $(BUILD)
	$(CC) -std=gnu89 -Wall -Wextra -Wno-unused-parameter -O2 -g -Icore tests/test_shell.c core/shellrun.c -o $@

$(BUILD)/test_brace: tests/test_brace.c tests/test.h core/brace.c core/brace.h
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) tests/test_brace.c core/brace.c -o $@

$(BUILD)/test_edit: tests/test_edit.c tests/test.h core/edit.c core/edit.h core/langmodes.c core/langmodes.h
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) tests/test_edit.c core/edit.c core/langmodes.c -o $@

$(BUILD)/test_search: tests/test_search.c tests/test.h core/search.c core/search.h
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) tests/test_search.c core/search.c -o $@

$(BUILD)/test_core: tests/test_core.c tests/test.h core/langmodes.c core/eol.c core/undo.c core/langmodes.h core/eol.h core/undo.h
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) tests/test_core.c core/langmodes.c core/eol.c core/undo.c -o $@

lint:
	sh tools/lint_openstep.sh

# Syntax-check the Objective-C against the modern SDK (never linked or run).
check-objc:
	for f in app/*.m hk/*.m; do \
	  echo "check $$f"; \
	  $(CC) -fsyntax-only -x objective-c -fno-objc-arc -Wall -Wno-deprecated-declarations \
	    -Werror=declaration-after-statement -Wno-unused-parameter -Wno-unused-function -Ihk -Icore -Iapp $$f || exit 1; \
	done

hk-smoke:
	mkdir -p $(BUILD)
	for f in tests/hk_smoke.m hk/*.m; do \
	  $(CC) -c $(OBJCFLAGS) -O2 $$f -o $(BUILD)/hk_$$(basename $$f .m).o || exit 1; \
	done
	$(CC) $(BUILD)/hk_*.o -framework Foundation -framework AppKit -o $(BUILD)/hk_smoke
	$(BUILD)/hk_smoke

doc-smoke:
	mkdir -p $(BUILD)
	for f in tests/doc_smoke.m app/EditorDoc.m app/UIHelpers.m app/LineNumberView.m app/ShellController.m hk/*.m; do \
	  $(CC) -c $(OBJCFLAGS) -fsanitize=address,undefined $$f -o $(BUILD)/dc_$$(basename $$f .m).o || exit 1; \
	done
	for f in core/*.c; do $(CC) -c -w -g -Icore -fsanitize=address,undefined $$f -o $(BUILD)/dc_c_$$(basename $$f .c).o || exit 1; done
	$(CC) -fsanitize=address,undefined $(BUILD)/dc_*.o -framework Foundation -framework AppKit -o $(BUILD)/doc_smoke
	$(BUILD)/doc_smoke

clean:
	rm -rf $(BUILD)

.PHONY: test lint check-objc hk-smoke doc-smoke clean
