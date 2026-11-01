# Host-side build & test (macOS/Linux).  The OPENSTEP build lives in Makefile.openstep.
CC      ?= cc
BUILD   = build
OBJCFLAGS = -x objective-c -fno-objc-arc -w -g -Ihk -Icore -Iapp

CFLAGS  = -std=c89 -pedantic -Wall -Wextra -Wdeclaration-after-statement \
          -Wno-long-long -Wno-unused-parameter -O2 -g -Icore

test: $(BUILD)/test_core $(BUILD)/test_search $(BUILD)/test_edit $(BUILD)/test_brace $(BUILD)/test_fill $(BUILD)/test_shell $(BUILD)/test_fold $(BUILD)/test_words $(BUILD)/test_includes $(BUILD)/test_tags $(BUILD)/test_foldlines $(BUILD)/test_macro $(BUILD)/test_modeprefs $(BUILD)/test_grep $(BUILD)/test_session $(BUILD)/test_cliphist $(BUILD)/test_complete $(BUILD)/test_remote
	$(BUILD)/test_core
	$(BUILD)/test_search
	$(BUILD)/test_edit
	$(BUILD)/test_brace
	$(BUILD)/test_fill
	$(BUILD)/test_shell
	$(BUILD)/test_fold
	$(BUILD)/test_words
	$(BUILD)/test_includes
	$(BUILD)/test_tags
	$(BUILD)/test_modeprefs
	$(BUILD)/test_grep
	$(BUILD)/test_session
	$(BUILD)/test_cliphist
	$(BUILD)/test_complete
	$(BUILD)/test_remote
	$(BUILD)/test_foldlines
	$(BUILD)/test_macro

$(BUILD)/test_fill: tests/test_fill.c tests/test.h core/fill.c core/fill.h core/rect.c core/rect.h
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) tests/test_fill.c core/fill.c core/rect.c -o $@

$(BUILD)/test_fold: tests/test_fold.c tests/test.h core/fold.c core/fold.h core/brace.c core/brace.h
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) tests/test_fold.c core/fold.c core/brace.c -o $@

$(BUILD)/test_words: tests/test_words.c tests/test.h core/words.c core/words.h core/fold.c core/fold.h core/brace.c
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) tests/test_words.c core/words.c core/fold.c core/brace.c -o $@

$(BUILD)/test_includes: tests/test_includes.c tests/test.h core/includes.c core/includes.h
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) tests/test_includes.c core/includes.c -o $@

$(BUILD)/test_modeprefs: tests/test_modeprefs.c tests/test.h core/modeprefs.c core/modeprefs.h
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) tests/test_modeprefs.c core/modeprefs.c -o $@

$(BUILD)/test_grep: tests/test_grep.c tests/test.h core/grep.c core/grep.h core/search.c core/search.h
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) tests/test_grep.c core/grep.c core/search.c -o $@

$(BUILD)/test_session: tests/test_session.c tests/test.h core/session.c core/session.h
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) tests/test_session.c core/session.c -o $@

$(BUILD)/test_cliphist: tests/test_cliphist.c tests/test.h core/cliphist.c core/cliphist.h
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) tests/test_cliphist.c core/cliphist.c -o $@

$(BUILD)/test_complete: tests/test_complete.c tests/test.h core/complete.c core/complete.h
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) tests/test_complete.c core/complete.c -o $@

$(BUILD)/test_remote: tests/test_remote.c tests/test.h core/remote.c core/remote.h
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) tests/test_remote.c core/remote.c -o $@

$(BUILD)/test_tags: tests/test_tags.c tests/test.h core/tags.c core/tags.h
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) tests/test_tags.c core/tags.c -o $@

$(BUILD)/test_foldlines: tests/test_foldlines.c tests/test.h core/foldlines.c core/foldlines.h core/fold.c core/words.c core/brace.c
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) tests/test_foldlines.c core/foldlines.c core/fold.c core/words.c core/brace.c -o $@

$(BUILD)/test_macro: tests/test_macro.c tests/test.h core/macro.c core/macro.h
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) tests/test_macro.c core/macro.c -o $@

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
	for f in tests/doc_smoke.m app/EditorDoc.m app/UIHelpers.m app/LineNumberView.m app/ShellController.m app/FindController.m app/FilesController.m app/SessionController.m app/ClipboardController.m app/RemoteController.m app/MacroController.m app/Appearance.m hk/*.m; do \
	  $(CC) -c $(OBJCFLAGS) -fsanitize=address,undefined $$f -o $(BUILD)/dc_$$(basename $$f .m).o || exit 1; \
	done
	for f in core/*.c; do $(CC) -c -w -g -Icore -fsanitize=address,undefined $$f -o $(BUILD)/dc_c_$$(basename $$f .c).o || exit 1; done
	$(CC) -fsanitize=address,undefined $(BUILD)/dc_*.o -framework Foundation -framework AppKit -o $(BUILD)/doc_smoke
	$(BUILD)/doc_smoke

clean:
	rm -rf $(BUILD)

.PHONY: test lint check-objc hk-smoke doc-smoke clean
