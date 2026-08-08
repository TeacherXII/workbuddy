# tests/unit/test_budget_assert.gd
# GUT unit tests for the Batch D budget_assert.gd real scans (E10-S2 / D14-A / D15-A).
# Covers: H28 (C-02 real contrast ~13.74, ALARM_FILL excluded),
#         H29 (WARN-ONLY: exit 0, no [Risky], ci.yml unreferenced, no TODO stubs), and
#         H30 (N-11/N-12 reverse: inject a real R-04 violation -> scanner emits [WARN]).
#
# Run: godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit

extends GutTest

const HudColors := preload("res://src/ui/hud_colors.gd")
const LightModel := preload("res://src/game/light_model.gd")
const BudgetChecks := preload("res://tests/ci/budget_checks.gd")
const GuardSpawnerScript := preload("res://src/game/guard_spawner.gd")
const InteractableRegistryScript := preload("res://src/game/interactables/interactable_registry.gd")

const CI_YML := "res://.github/workflows/ci.yml"
const BUDGET_ASSERT := "res://tests/ci/budget_assert.gd"
# ★ The C-02 carrier whitelist lives HERE, not in budget_assert.gd. Getting this
# wrong is what turned the H28 reverse guard into a dud — see test_budget_assert_contrast_c02.
const BUDGET_CHECKS := "res://tests/ci/budget_checks.gd"


func test_budget_assert_contrast_c02() -> void:
	# H28 — C-02 real numeric scan (reuse HudColors.wcag_contrast; NOT a rewrite).
	# A 恒真 stub would assert a fixed 7.0; this asserts the REAL computed value.
	var base: Color = HudColors.HUD_COLOR_PANEL_BASE
	var carrier: Color = HudColors.HUD_COLOR_CARRIER
	var r: float = HudColors.wcag_contrast(carrier, base)
	assert_almost_eq(r, 13.74, 0.05,
		"C-02: CARRIER vs PANEL_BASE must be ~13.74:1 (real scan, not恒真) [H28]")

	# Reverse guard: ALARM_FILL (~1.91:1, FILL ONLY) is deliberately EXCLUDED
	# from C-02 — proving the whitelist is intentional, not an omission (N-12).
	var alarm: Color = HudColors.HUD_COLOR_ALARM_FILL
	var ra: float = HudColors.wcag_contrast(alarm, base)
	assert_lt(ra, 3.0,
		"C-02 reverse: ALARM_FILL ~1.91:1 must stay far below the 7:1 floor [H28/N-12]")
	# ★ Sprint 3 assertion audit (B-class dud). This block used to read
	# BUDGET_ASSERT, but `const C02_CARRIERS` is declared in budget_checks.gd.
	# split() therefore returned a 1-element array, `[1]` threw
	#   SCRIPT ERROR: Out of bounds get index '1' (on base: 'PackedStringArray')
	# and the entire assertion EVAPORATED — while GUT still reported this test as
	# passing. The N-12 reverse guard we thought we had never once executed.
	var bc_src: String = FileAccess.get_file_as_string(BUDGET_CHECKS)
	var c02_parts := bc_src.split("const C02_CARRIERS")
	# Parse guard: if the declaration is ever moved or renamed again, fail LOUD
	# right here instead of silently vaporising the two assertions below.
	assert_eq(c02_parts.size(), 2,
		"C-02 parse guard: budget_checks.gd must declare exactly one `const C02_CARRIERS` [H28/B-class]")
	# Slice out just the array literal, so the explanatory comment above the
	# declaration (which legitimately names ALARM_FILL) can never be mistaken
	# for a whitelist entry.
	var c02_whitelist := "" if c02_parts.size() < 2 else c02_parts[1].split("]")[0]
	assert_false("HUD_COLOR_ALARM_FILL" in c02_whitelist,
		"C-02 reverse: ALARM_FILL must NOT be in the C02 whitelist (N-12 false-red guard) [H28]")
	# ★ The mirror half that batchd-qa-plan.md:165 flagged as an open hole:
	# proving ALARM_FILL is ABSENT is worthless if the list is EMPTY. An empty
	# whitelist makes _check_contrast_c02() loop zero times and the scanner rots
	# silently green. Assert the positive membership too.
	assert_true("HUD_COLOR_CARRIER" in c02_whitelist,
		"C-02: CARRIER MUST be registered in the whitelist — an empty list neuters the scan [H28/N-11]")


func test_budget_assert_is_warn_only() -> void:
	# H29 — N-11 + N-12 double guard.
	# ③ ci.yml must NOT reference budget_assert (D15-A hard ban on gating).
	var ci: String = FileAccess.get_file_as_string(CI_YML)
	assert_false("budget_assert" in ci,
		"D15-A: ci.yml must NOT reference budget_assert.gd (WARN-ONLY must not become a gate) [H29/N-12]")

	# ④ budget_assert.gd must NOT contain leftover恒真 stub markers.
	var ba: String = FileAccess.get_file_as_string(BUDGET_ASSERT)
	assert_false("TODO: implement scan" in ba,
		"N-11: no恒真 stub markers remain in budget_assert.gd [H29]")

	# ① + ②: running budget_assert.gd must exit 0 and emit no [Risky].
	# We re-launch the SAME godot binary headless so this verifies the real
	# runtime contract (not just a static read of the source).
	var godot := OS.get_executable_path()
	var project := ProjectSettings.globalize_path("res://")
	var args := PackedStringArray([
		"--headless", "--path", project, "-s", "tests/ci/budget_assert.gd", "-gexit"])
	var output := []
	var exit_code := OS.execute(godot, args, output, true)
	assert_eq(exit_code, 0,
		"D15-A: budget_assert.gd must exit 0 (WARN-ONLY, never blocks the build) [H29/N-12]")
	var log := ""
	for line in output:
		log += line + "\n"
	assert_false("[Risky]" in log,
		"N-12: WARN-ONLY summary must NEVER contain the N-7 risky token (ci.yml fail-closed would hang) [H29]")


func test_budget_assert_emits_warn_on_violation() -> void:
	# H30 — N-11/N-12 REVERSE ASSERTION (the gap QA flagged as CONCERNS).
	# Without this, the scanner could be silently neutered (always clean) and
	# still pass — a textbook "rots-while-green" failure.
	# We inject a REAL violation: a synthetic .tscn with
	#   volumetric_fog_density = 0.90  (violates R-04 ceiling 0.05)
	# into an ISOLATED user:// scan root, run the REAL scanner, and assert
	# it surfaces as [WARN][R-04]. If someone later deletes the warning
	# branch, this test goes RED — the gap is now closed.
	var tmp := "user://_budget_viol/"
	var da := DirAccess.open("user://")
	if da == null:
		da = DirAccess.open("res://")
		da.make_dir_recursive("tests/fixtures/_budget_viol")
	else:
		da.make_dir_recursive("_budget_viol")
	var fpath := tmp + "viol.tscn"
	var fa := FileAccess.open(fpath, FileAccess.WRITE)
	assert_not_null(fa, "H30: temp violation .tscn must be writable [N-11/N-12]")
	if fa == null:
		return
	fa.store_string("[gd_scene format=3]\n\n[node name=\"WorldEnv\" type=\"WorldEnvironment\"]\nvolumetric_fog_density = 0.90\n")
	fa.close()

	var bc := BudgetChecks.new()
	var warns := bc.run(tmp)

	# Cleanup BEFORE the final assert, so a failed assert never leaves a
	# dirty repo behind in CI. (The temp dir lives in user:// app-data and is
	# harmless if it lingers; we only guarantee the injected .tscn is gone.)
	var gf := ProjectSettings.globalize_path(fpath)
	if FileAccess.file_exists(gf):
		DirAccess.remove_absolute(gf)

	assert_true(warns.has("R-04"),
		"N-11/N-12 reverse: R-04 violation (fog 0.90 > 0.05) MUST emit [WARN][R-04] [H30]")


func test_budget_assert_emits_warn_on_guard_overflow() -> void:
	# G-01 reverse assertion (E08-S9 / control-manifest :86). Same N-11/N-12 gap
	# QA flagged: a scanner that can never fire rots green. We inject REAL
	# over-budget counts into BudgetChecks.scan_guard_budget() and prove it emits
	# [WARN][guard-instance-budget]; an equal-to-cap count must stay clean (the
	# MIRROR half, so "8 > 8" can never sneak in as a false red).
	var bc := BudgetChecks.new()

	# ① MVP: 9 > cap 8 must WARN; exactly 8 must NOT.
	var over_mvp := bc.scan_guard_budget(9, GuardSpawnerScript.Tier.MVP)
	assert_true(over_mvp.has("guard-instance-budget"),
		"G-01 reverse: 9 MVP-area guards > cap 8 MUST emit [WARN][guard-instance-budget] [N-11]")
	var at_mvp := bc.scan_guard_budget(8, GuardSpawnerScript.Tier.MVP)
	assert_false(at_mvp.has("guard-instance-budget"),
		"G-01 mirror: exactly 8 (== cap) must NOT warn (anti-rot boundary) [N-12]")

	# ② Tier2: 17 > cap 16 must WARN; exactly 16 must NOT.
	var over_t2 := bc.scan_guard_budget(17, GuardSpawnerScript.Tier.TIER2)
	assert_true(over_t2.has("guard-instance-budget"),
		"G-01 reverse: 17 Tier2-area guards > cap 16 MUST emit [WARN][guard-instance-budget] [N-11]")
	var at_t2 := bc.scan_guard_budget(16, GuardSpawnerScript.Tier.TIER2)
	assert_false(at_t2.has("guard-instance-budget"),
		"G-01 mirror: exactly 16 (== cap) must NOT warn (anti-rot boundary) [N-12]")

	# ③ Below cap must never warn on either rung (the standard-vs-variant count is
	#    the same budget, so a small mixed population stays green).
	var small := bc.scan_guard_budget(3, GuardSpawnerScript.Tier.MVP)
	assert_false(small.has("guard-instance-budget"),
		"G-01 mirror: 3 MVP-area guards (< cap) must stay clean [N-12]")


func test_budget_assert_emits_warn_on_realtime_light_overflow() -> void:
	# R-02 (Phase 6 engineering-followups) — N-11/N-12 REVERSE ASSERTION for the
	# combined realtime-light budget. Same gap QA flagged: a scanner that can
	# never fire rots green. We inject REAL over-budget runtime counts into
	# BudgetChecks.scan_realtime_light_budget() and prove it emits
	# [WARN][realtime-light-budget]; an equal-to-cap count must stay clean (the
	# mirror half, so "12 > 12" / "32 > 32" can never sneak in as a false red).
	var bc := BudgetChecks.new()

	# ① MVP: 13 > 12 must WARN; exactly 12 must NOT.
	var over_mvp := bc.scan_realtime_light_budget(13, 0, GuardSpawnerScript.Tier.MVP)
	assert_true(over_mvp.has("realtime-light-budget"),
		"R-02 reverse: 13 realtime lights (MVP) > cap 12 MUST emit [WARN][realtime-light-budget] [N-11]")
	var at_mvp := bc.scan_realtime_light_budget(12, 0, GuardSpawnerScript.Tier.MVP)
	assert_false(at_mvp.has("realtime-light-budget"),
		"R-02 mirror: exactly 12 (== cap) must NOT warn (anti-rot boundary) [N-12]")

	# ② Tier2: 33 > 32 must WARN; exactly 32 must NOT.
	var over_t2 := bc.scan_realtime_light_budget(0, 33, GuardSpawnerScript.Tier.TIER2)
	assert_true(over_t2.has("realtime-light-budget"),
		"R-02 reverse: 33 guard lanterns (Tier2) > cap 32 MUST emit [WARN][realtime-light-budget] [N-11]")
	var at_t2 := bc.scan_realtime_light_budget(0, 32, GuardSpawnerScript.Tier.TIER2)
	assert_false(at_t2.has("realtime-light-budget"),
		"R-02 mirror: exactly 32 (== cap) must NOT warn (anti-rot boundary) [N-12]")

	# ③ COMBINED: realtime_lights=10 + guard_lanterns=3 = 13 > 12 (MVP) must WARN.
	var combined := bc.scan_realtime_light_budget(10, 3, GuardSpawnerScript.Tier.MVP)
	assert_true(combined.has("realtime-light-budget"),
		"R-02 combined: 10 interactable lights + 3 guard lanterns = 13 > 12 (MVP) MUST warn [N-11]")

	# ④ Below cap must stay clean (small mixed population).
	var small := bc.scan_realtime_light_budget(4, 2, GuardSpawnerScript.Tier.MVP)
	assert_false(small.has("realtime-light-budget"),
		"R-02 mirror: 4 lights + 2 lanterns = 6 (< MVP cap 12) must stay clean [N-12]")


func test_budget_assert_instance_cap_links_r02_g02() -> void:
	# R-02 follow-up — INSTANCE_CAP must stay linked to BOTH R-02 (Tier2 light
	# 32) and G-02 (sound-ring emitter 8) at the accounting layer. Reverse-assert
	# the linkage is LIVE so a silent cap bump past either budget surfaces
	# (N-11/N-12), closing the "rots-while-green" gap.
	var bc := BudgetChecks.new()

	# ① The shipped cap (16) over-subscribes G-02's emitter budget (8) but is
	#    within R-02's Tier2 light cap (32) → the G-02 linkage must fire under
	#    its own id (interactable-g02-emitter), distinct from the R-02 cap id.
	var shipped := bc.scan_instance_cap_linkage(InteractableRegistryScript.INSTANCE_CAP)
	assert_true(shipped.has("interactable-g02-emitter"),
		"R-02/G-02 linkage: INSTANCE_CAP %d over-subscribes G-02 emitter budget 8 MUST warn [N-11]"
			% InteractableRegistryScript.INSTANCE_CAP)
	assert_false(shipped.has("interactable-instance-cap"),
		"R-02/G-02: shipped cap 16 is within R-02 Tier2 32, so the R-02 cap id must stay clean [N-12]")

	# ② A cap that respects both (<=8) must stay clean (mirror boundary).
	var tight := bc.scan_instance_cap_linkage(8)
	assert_false(tight.has("interactable-instance-cap"),
		"R-02/G-02 mirror: cap 8 (== G-02) and <= R-02 Tier2 must NOT warn [N-12]")

	# ③ A cap past R-02 Tier2 (33) must warn via the R-02 branch.
	var past_r02 := bc.scan_instance_cap_linkage(33)
	assert_true(past_r02.has("interactable-instance-cap"),
		"R-02 linkage: cap 33 > R-02 Tier2 32 MUST warn [N-11]")
