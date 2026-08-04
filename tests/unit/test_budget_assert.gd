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

const CI_YML := "res://.github/workflows/ci.yml"
const BUDGET_ASSERT := "res://tests/ci/budget_assert.gd"


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
	var ba_src: String = FileAccess.get_file_as_string(BUDGET_ASSERT)
	assert_false("HUD_COLOR_ALARM_FILL" in ba_src.split("const C02_CARRIERS")[1].split("]")[0],
		"C-02 reverse: ALARM_FILL must NOT be in the C02 whitelist (N-12 false-red guard) [H28]")


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
		"N-12: WARN-ONLY summary must NEVER contain [Risky] (ci.yml N-7 fail-closed would hang) [H29]")


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
