# tests/unit/test_ci_gates.gd
# Reverse assertions for the CI quality gates in .github/workflows/ci.yml.
# Sprint 3 · S3-B follow-up F1 (N-7b「脚本未加载」闸门).
#
# ── Why a gate needs its own test ───────────────────────────────────────────
# N-7b exists because a GDScript parse error makes Godot drop a test file
# BEFORE GUT can collect it: the suite silently shrinks and every other gate
# reports a clean green. The gate is therefore the ONLY thing standing between
# "35 tests ran and passed" and "35 tests never existed".
#
# A gate that can never fire is worth exactly nothing, and that is not
# hypothetical here — it is what actually happened. As first merged, the second
# alternative of the N-7b pattern spelled the engine's second word with a
# lowercase `e` (the prefix, then `.*`, then `parse error` all in lower case).
# Godot 4.4 emits the title-case spelling, `grep -E` is case
# sensitive, and so that half of the pattern scored ZERO hits across both the
# false-green and the true-green run that were pulled down and diffed by hand.
# The gate worked, but on one leg, and nobody could have known without
# downloading the raw output. This file makes that observable in CI instead.
#
# The fixtures below are not invented: they are real captured engine output
# (tools/tmp/d_step2_red.txt, from the Batch D red run).
#
# ── ★ WHY EVERY FIXTURE IS ASSEMBLED FROM PIECES ★ ──────────────────────────
# This is the one test in the suite whose subject matter is a string that, if
# it ever reached stdout, would fail the build. GUT at -glog=3 echoes assertion
# descriptions into gut_output.txt, and that file is precisely what N-7b greps.
# So a careless fixture here does not produce a wrong answer — it produces a
# RED main, on every push, until someone works out why. (Batch D burned a cycle
# on the same shape of mistake with a bare [Risky] token in an assert message.)
#
# The defence is structural rather than careful: grep is LINE oriented, so the
# invariant we need is "no single line of this file matches the gate pattern".
# Every fixture is therefore split across separate `const` lines, each of which
# is inert on its own — one line carries the `SCRIPT ERROR:` prefix and no
# parse wording, the next carries the parse wording and no prefix. They are
# concatenated at runtime, held in local variables, and NEVER interpolated into
# an assertion message.
#
# test_unit_test_sources_cannot_trip_the_n7b_gate() then enforces that
# invariant mechanically, over this file and every other file in tests/unit/,
# so the next person to touch this cannot silently break it.
#
# Run: godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit

extends GutTest

const CI_YML := "res://.github/workflows/ci.yml"
const UNIT_DIR := "res://tests/unit"

# The gate is located by its marker comment, then by the first grep that
# follows it — so re-ordering the gates in ci.yml cannot make this test read
# the wrong one (N-7 uses the same `grep -qE` shape and sits directly above).
const N7B_MARKER := "N-7b"
const GREP_PREFIX := "grep -qE '"

# ── Fixture fragments (see the header note — inert alone, by construction) ──
const F_SCRIPT_ERR := "SCRIPT ERROR:"
const F_PARSE_TITLECASE := " Parse Error: Cannot find member \"DECOY_RADIUS\" in base \"SoundPropagator\"."
const F_PARSE_LOWERCASE := " Parse error: Identifier \"GutUtils\" not declared in the current scope."
const F_LOADFAIL_HEAD := "ERROR: Failed to load "
const F_LOADFAIL_TAIL := "script \"res://tests/unit/test_patrol_ai.gd\" with error \"Parse error\"."
# A REAL runtime error from the last green run. Tests drive negative paths on
# purpose, so lines like this are normal on a healthy build.
const F_RUNTIME_TAIL := " Invalid operands 'String' and 'int' in operator '=='."
# The gate's first alternative, split in two for the extraction test below.
# Written as one literal, THIS LINE would match the gate and break the very
# invariant the guard test at the bottom enforces — same reason the loader
# fixture above is split into HEAD and TAIL. Joined at the call site.
const F_ALT_LOADFAIL_A := "Failed to load "
const F_ALT_LOADFAIL_B := "script"


# =============================================================================
# Helpers — read the gate out of the workflow file itself
# =============================================================================
## The whole `if grep -qE '...' <file>; then` line of the N-7b gate, verbatim.
func _n7b_grep_line() -> String:
	var ci := FileAccess.get_file_as_string(CI_YML)
	if ci == "":
		return ""
	var marker := ci.find(N7B_MARKER)
	if marker < 0:
		return ""
	var rest := ci.substr(marker)
	var g := rest.find(GREP_PREFIX)
	if g < 0:
		return ""
	var line_start := rest.rfind("\n", g)
	line_start = 0 if line_start < 0 else line_start + 1
	var line_end := rest.find("\n", g)
	if line_end < 0:
		line_end = rest.length()
	return rest.substr(line_start, line_end - line_start)


## The single-quoted ERE the gate greps with. The pattern contains no single
## quote of its own, so first-quote..next-quote is an exact extraction.
func _n7b_pattern() -> String:
	var line := _n7b_grep_line()
	var a := line.find("'")
	if a < 0:
		return ""
	var b := line.find("'", a + 1)
	if b < 0:
		return ""
	return line.substr(a + 1, b - a - 1)


## The gate pattern compiled for matching. POSIX ERE and PCRE2 agree on every
## construct used here (alternation, `.`, `*`, bracket classes), so compiling
## the grep pattern with Godot's RegEx tests the real thing rather than a copy.
func _n7b_regex() -> RegEx:
	var pattern := _n7b_pattern()
	if pattern == "":
		return null
	var re := RegEx.new()
	if re.compile(pattern) != OK:
		return null
	return re


# =============================================================================
# The gate must be readable at all (guards every test below against a vacuous
# pass — an unfindable pattern would otherwise make "it matches" trivially true)
# =============================================================================
func test_n7b_gate_pattern_is_extractable_and_compiles() -> void:
	var line := _n7b_grep_line()
	# ★ Do NOT assert `line` or `pattern` as VALUES. GUT echoes the argument it
	# received, and both of those strings are the gate pattern itself — echoing
	# either one writes the trigger text into gut_output.txt and makes this very
	# test red the build. That is exactly how the first run of PR #12 failed,
	# and it is the same shape as the Batch D incident. Reduce to a bool first:
	# GUT then only ever prints `true`.
	# NB: the marker is on the COMMENT line above the gate, so the extracted
	# grep line does not carry it. What identifies the line is the grep itself.
	var line_found := line.contains(GREP_PREFIX)
	assert_true(line_found,
		"the N-7b gate must still be findable in ci.yml below its marker comment")
	var pattern := _n7b_pattern()
	# Only the loader alternative is checked as a LITERAL. The parse-diagnostic
	# alternative is spelled with bracket classes ([Pp]arse [Ee]rror), so it has
	# no literal form to look for — its coverage is proven by actually matching
	# both spellings in the behavioural tests below, which is the stronger check.
	var pattern_ok := pattern.length() > 0 \
		and pattern.contains(F_ALT_LOADFAIL_A + F_ALT_LOADFAIL_B)
	assert_true(pattern_ok,
		"the N-7b pattern must extract and must still carry the loader "
		+ "failure alternative")
	var re := RegEx.new()
	assert_eq(re.compile(pattern), OK,
		"the N-7b pattern must be a valid regular expression")


# =============================================================================
# What the gate MUST catch
# =============================================================================
## ★ THE REGRESSION THIS FILE EXISTS FOR (F1).
## Godot 4.4 reports a failed script load with a TITLE-CASE second word. The
## gate's original lowercase spelling never matched it, making this branch dead
## code. If anyone reverts to the case-sensitive spelling, this goes red.
func test_n7b_catches_the_titlecase_engine_diagnostic() -> void:
	var re := _n7b_regex()
	assert_not_null(re, "fixture: the N-7b pattern must compile")
	if re == null:
		return
	# ★ Reduced to a BOOL before it reaches the assertion. GUT prints the value
	#   it got when an assertion fails, and the value here would be the fixture
	#   itself — the one string that must never reach gut_output.txt.
	var hit := re.search(F_SCRIPT_ERR + F_PARSE_TITLECASE) != null
	assert_true(hit,
		"N-7b must catch the engine's title-case load diagnostic — this is the "
		+ "exact spelling Godot 4.4 emits, and the branch that was dead until F1")


## The lowercase spelling is not imaginary either: ResourceLoader embeds it in
## its own message. Keeping both alive costs two bracket classes.
func test_n7b_catches_the_lowercase_spelling() -> void:
	var re := _n7b_regex()
	assert_not_null(re, "fixture: the N-7b pattern must compile")
	if re == null:
		return
	var hit := re.search(F_SCRIPT_ERR + F_PARSE_LOWERCASE) != null
	assert_true(hit,
		"N-7b must still catch the lowercase spelling — widening the case must "
		+ "not have traded one dead branch for another")


## The alternative that actually saved the false-green run. Locked so a future
## tidy-up cannot drop it while "the other branch covers it".
func test_n7b_catches_the_resource_loader_failure_line() -> void:
	var re := _n7b_regex()
	assert_not_null(re, "fixture: the N-7b pattern must compile")
	if re == null:
		return
	var hit := re.search(F_LOADFAIL_HEAD + F_LOADFAIL_TAIL) != null
	assert_true(hit,
		"N-7b must catch the loader's own failure line — it is the alternative "
		+ "that carried the gate on its own before F1")


# =============================================================================
# What the gate MUST NOT catch  ← the half that keeps main green
# =============================================================================
## ★ MIRROR ASSERTION. A healthy run contains runtime engine errors on purpose:
## tests that exercise negative paths make the engine complain, and that
## complaint is the EVIDENCE the negative path was taken. The last green run
## carried three such lines. Widening the gate to a bare `SCRIPT ERROR` would
## therefore not catch more bugs — it would red main on the next push and
## teach everyone to ignore the gate. The parse qualifier is load-bearing.
func test_n7b_ignores_runtime_engine_errors() -> void:
	var re := _n7b_regex()
	assert_not_null(re, "fixture: the N-7b pattern must compile")
	if re == null:
		return
	var hit := re.search(F_SCRIPT_ERR + F_RUNTIME_TAIL) != null
	assert_false(hit,
		"N-7b must IGNORE runtime engine errors — a green run legitimately "
		+ "contains them, so matching them would red main immediately")


## Scope lock. N-7b judges the TEST RUN only. The import step above it is
## allowed to be noisy about assets and says nothing about whether the suite
## loaded, so pointing this gate at anything wider would import false reds.
func test_n7b_reads_only_the_gut_output_file() -> void:
	var line := _n7b_grep_line()
	assert_true(line.contains("gut_output.txt"),
		"the N-7b gate must read the GUT run output and nothing else")


# =============================================================================
# Self-pollution guard (see the ★ note in the header)
# =============================================================================
## Enforces the invariant that makes this file safe to write at all: no single
## LINE of any unit-test source may match the N-7b pattern. grep is line
## oriented, so this is the exact property that keeps a test's own text from
## tripping the gate if it is ever echoed into gut_output.txt (GUT does echo
## assertion descriptions at -glog=3).
##
## Offenders are reported as file:line ONLY. Printing the offending text would
## commit the very sin being detected.
func test_unit_test_sources_cannot_trip_the_n7b_gate() -> void:
	var re := _n7b_regex()
	assert_not_null(re, "fixture: the N-7b pattern must compile")
	if re == null:
		return

	var d := DirAccess.open(UNIT_DIR)
	assert_not_null(d, "fixture: the unit test directory must be listable")
	if d == null:
		return

	var scanned := 0
	var offenders: Array = []
	d.list_dir_begin()
	var entry := d.get_next()
	while entry != "":
		if entry.ends_with(".gd"):
			scanned += 1
			var src := FileAccess.get_file_as_string(UNIT_DIR + "/" + entry)
			var lines := src.split("\n")
			for i in range(lines.size()):
				if re.search(lines[i]) != null:
					offenders.append("%s:%d" % [entry, i + 1])
		entry = d.get_next()
	d.list_dir_end()

	# Anti-vacuity: an empty scan would make the assertion below trivially true,
	# which is the failure mode this whole file is arguing against.
	assert_gt(scanned, 10,
		"fixture: the scan must actually see the unit suite (got %d files)" % scanned)
	assert_eq(offenders.size(), 0,
		"a unit test source line matches the N-7b gate; if GUT echoes it, the "
		+ "build reds for no reason — split the text across lines. At: %s"
		% str(offenders))
