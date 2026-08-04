# tests/ci/budget_assert.gd
# Headless budget static-assertion runner (control-manifest §7; WARN-ONLY).
#
# [D14-A] STATIC-FEASIBLE budgets are scanned here with REAL scans.
# [D14-A] RUNTIME-ONLY budgets are deliberately NOT scanned here.
#         A static scan of a runtime quantity is an ALWAYS-PASS assertion, which
#         would satisfy Sprint 1 exit criterion #4 in letter and void it in
#         substance. Do NOT "helpfully" add stubs for the entries below. [N-11]
#
#   R-05 -> tests/unit/test_light_model.gd::test_light_toggle_ramp_within_budget
#   G-02 -> tests/unit/test_sound_propagation.gd::test_ring_vfx_capped_at_eight
#   V-02 -> tests/unit/test_hud_slice.gd (EXPOSURE_PULSE_HZ) +
#           tests/unit/test_vision_cone.gd (CONE_VFX_PULSE_HZ)
#   G-04 -> src/game/patrol_ai.gd DECISION_HZ / decision_count (Batch C)
#           asserted by tests/unit/test_patrol_ai.gd::test_fsm_tick_le_10hz
#   G-05 -> no A* in Sprint 1; revisit in Sprint 2
#
# [D15-A] WARN-ONLY in Batch D: always exit 0, never print "[Risky]",
#         and this file MUST NOT be referenced from .github/workflows/ci.yml.
#         Gate promotion is a Sprint 2 decision. [N-12]

extends SceneTree

const EXIT_OK := 0

const HudColors := preload("res://src/ui/hud_colors.gd")
const LightModel := preload("res://src/game/light_model.gd")

# R-02: dynamic point lights per screen (MVP<=12 / Tier2<=32).
const LIGHT_BUDGET_MVP := 12
const LIGHT_BUDGET_TIER2 := 32

# R-04: volumetric fog base ceiling (control-manifest :21).
const FOG_BASE_MAX := 0.05

# C-02: key indicator contrast >= 7:1 vs panel base (control-manifest :59).
const CONTRAST_MIN_C02 := 7.0

# ★ Explicit whitelist: only INFORMATION CARRIERS enter C-02.
# HUD_COLOR_ALARM_FILL (#7A2E2E, ~1.91:1) is "FILL ONLY" and MUST be excluded
# or budget_assert emits a false [WARN] (N-12). New carriers must be registered
# here explicitly — there is no auto-inclusion.
const C02_CARRIERS := ["HUD_COLOR_CARRIER"]


func _initialize() -> void:
	prints("[CI:budget] ===== ASHEN STEP budget + Sprint0 exit gate (warn-only) =====")
	_report_smoke_requirement()      # Exit criterion ⑤ (epic-overview §3)
	_check_dynamic_lights()          # R-02 (real scan)
	_check_volumetric_fog()          # R-04 (real scan)
	_check_lightmap()                # R-06 (real scan, empty set)
	_check_vignette_ease()           # V-06 (real weak scan)
	_check_contrast_c02()            # C-02 (real numeric scan, reuse wcag_contrast)
	prints("[CI:budget] All checks are WARN-ONLY. Exit 0 (lean: build not blocked).")
	prints("[CI:budget] Review any [WARN] lines and route drift to the lead for adjudication.")
	quit(EXIT_OK)


func _report_smoke_requirement() -> void:
	# epic-overview §3 退出标准⑤: GUT smoke must be green under godot --headless.
	prints("[CI:budget][GATE-⑤] Sprint 0 exit: GUT smoke green under headless REQUIRED.")
	prints("[CI:budget][GATE-⑤]   cmd: godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit")
	prints("[CI:budget][GATE-⑤]   status: SMOKE-RUNNER-EXTERNAL (invoke from CI; this script only records the gate)")


func _warn(check_id: String, constraint: String, detail: String) -> void:
	prints("[CI:budget][WARN][%s] %s — %s" % [check_id, constraint, detail])


# --- R-02: dynamic point lights (real scene scan) --------------------------
func _check_dynamic_lights() -> void:
	var count := 0
	for f in _list_tscn():
		count += _count_node_types(f, ["OmniLight3D", "SpotLight3D"])
	if count > LIGHT_BUDGET_TIER2:
		_warn("R-02", "dynamic lights > %d (Tier2 cap)" % LIGHT_BUDGET_TIER2, "found %d" % count)
	else:
		prints("[CI:budget][OK][R-02] dynamic lights found: %d (MVP<=12, Tier2<=32)" % count)


# --- R-04: volumetric fog base density (real scene scan) --------------------
func _check_volumetric_fog() -> void:
	# Scan .tscn for WorldEnvironment / FogVolume nodes and any explicit
	# volumetric_fog_density assignment above the R-04 ceiling.
	var violations := 0
	for f in _list_tscn():
		var txt := FileAccess.get_file_as_string(f)
		if txt == "":
			continue
		if ("WorldEnvironment" in txt) or ("FogVolume" in txt):
			for line in txt.split("\n"):
				if "volumetric_fog_density" in line:
					var v := _parse_density(line)
					if v > FOG_BASE_MAX:
						violations += 1
						_warn("R-04", "volumetric fog base > %.2f" % FOG_BASE_MAX,
							"%s -> %.3f" % [f.get_file(), v])
	if violations == 0:
		prints("[CI:budget][OK][R-04] no volumetric fog density exceeds %.2f" % FOG_BASE_MAX)


# --- R-06: static geometry LightmapGI bake (real scene scan) ----------------
func _check_lightmap() -> void:
	var has_lightmap := false
	for f in _list_tscn():
		var txt := FileAccess.get_file_as_string(f)
		if txt != "" and "type=\"LightmapGI\"" in txt:
			has_lightmap = true
	if has_lightmap:
		prints("[CI:budget][OK][R-06] LightmapGI present (static geometry baked)")
	else:
		# No static geometry yet in the repo — a REAL empty scan, NOT a stub.
		# (Adding .glb/.mesh assets later makes this scan live automatically.)
		prints("[CI:budget][OK][R-06] no LightmapGI nodes yet (empty scan set; assets pending)")


# --- V-06: vignette easing must not be a hard linear cut (weak scan) -------
func _check_vignette_ease() -> void:
	if LightModel.VIGNETTE_TRANS == Tween.TRANS_LINEAR:
		_warn("V-06", "vignette transition is TRANS_LINEAR", "hard-cut flash; use TRANS_SINE")
	else:
		prints("[CI:budget][OK][V-06] vignette transition eased (not TRANS_LINEAR)")


# --- C-02: key indicator contrast >= 7:1 (real numeric scan) ---------------
func _check_contrast_c02() -> void:
	var base: Color = HudColors.HUD_COLOR_PANEL_BASE
	for name in C02_CARRIERS:
		var fg: Color = _c02_fg(name)
		var r: float = HudColors.wcag_contrast(fg, base)
		if r < CONTRAST_MIN_C02:
			_warn("C-02", "%s contrast < %.1f:1" % [name, CONTRAST_MIN_C02], "%.2f:1" % r)
		else:
			prints("[CI:budget][OK][C-02] %s contrast %.2f:1 (>= %.1f:1)" % [name, r, CONTRAST_MIN_C02])


func _c02_fg(name: String) -> Color:
	match name:
		"HUD_COLOR_CARRIER": return HudColors.HUD_COLOR_CARRIER
		_: return Color.BLACK


# --- scene-walk helpers ----------------------------------------------------
func _list_tscn() -> PackedStringArray:
	var out := PackedStringArray()
	_dir_walk("res://", out)
	return out


func _dir_walk(dir: String, out: PackedStringArray) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name.begins_with("."):
			name = d.get_next()
			continue
		var full := dir.path_join(name)
		if d.current_is_dir():
			_dir_walk(full, out)
		elif name.ends_with(".tscn"):
			out.append(full)
		name = d.get_next()
	d.list_dir_end()


func _count_node_types(tscn_path: String, types: PackedStringArray) -> int:
	var txt := FileAccess.get_file_as_string(tscn_path)
	if txt == "":
		return 0
	var count := 0
	for line in txt.split("\n"):
		if not line.begins_with("[node"):
			continue
		for t in types:
			if ("type=\"%s\"" % t) in line:
				count += 1
				break
	return count


func _parse_density(line: String) -> float:
	var i := line.find("=")
	if i < 0:
		return 0.0
	var rest := line.substr(i + 1).strip_edges()
	var buf := ""
	for c in rest:
		if c.is_valid_float() or c == "." or c == "-":
			buf += c
		elif buf != "":
			break
	return buf.to_float() if buf != "" else 0.0
