# tests/ci/budget_checks.gd
# Real static-budget scan logic for ASHEN STEP (E10-S2 / D14-A / D15-A).
#
# Extracted from budget_assert.gd so the logic is unit-testable (RefCounted)
# while budget_assert.gd stays a thin SceneTree entry for headless CI.
#
# [D14-A] STATIC-FEASIBLE budgets are scanned here with REAL scans.
# [D14-A] RUNTIME-ONLY budgets are deliberately NOT scanned here.
#         A static scan of a runtime quantity is an ALWAYS-PASS assertion, which
#         would satisfy Sprint 1 exit criterion #4 in letter and void it in
#         substance. Do NOT "helpfully" add stubs for the entries below. [N-11]
#   R-05 -> tests/unit/test_light_model.gd::test_light_toggle_ramp_within_budget
#   G-02 -> tests/unit/test_sound_propagation.gd::test_ring_vfx_capped_at_eight
#   V-02 -> tests/unit/test_hud_slice.gd (EXPOSURE_PULSE_HZ) +
#           tests/unit/test_vision_cone.gd (CONE_VFX_PULSE_HZ)
#   G-04 -> src/game/patrol_ai.gd DECISION_HZ / decision_count (Batch C)
#           asserted by tests/unit/test_patrol_ai.gd::test_fsm_tick_le_10hz
#   G-05 -> no A* in Sprint 1; revisit in Sprint 2
#
# [D15-A] WARN-ONLY: run() always returns a list (never exits non-zero) and
#         never emits "[Risky]". Gate promotion is a Sprint 2 decision. [N-12]
#
# N-11/N-12 reverse-assertion surface: run() RETURNS the emitted warning
# check-ids, so a GUT test can inject a real violation and prove the scanner
# emits [WARN] (closes the "rots-while-green" gap from QA review).

extends RefCounted

const HudColors := preload("res://src/ui/hud_colors.gd")
const LightModel := preload("res://src/game/light_model.gd")
# [Sprint 2 · Batch A] SAV-S1/S2 static budgets. Only STATIC members are touched
# (constants + static funcs) — this file never instantiates the L2 service.
const SaveManagerScript := preload("res://src/core/save_manager.gd")
# [Sprint 2 · Batch B] E07-S7/S8. Only the STATIC cap constant is read; this
# file never instantiates the registry.
const InteractableRegistryScript := preload("res://src/game/interactables/interactable_registry.gd")

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

# --- E07-S7 / E07-S8 (Sprint 2 · Batch B) -----------------------------------
# Where the interactable entity layer lives. Every .gd here must stay on a
# RefCounted lineage: a Node dropped without queue_free() becomes a Godot
# ORPHAN, and orphan-freedom is this story's whole point.
const INTERACTABLE_DIR := "res://src/game/interactables"

# Legal base classes for an interactable script. `RefCounted` is the root of the
# lineage; `InteractableEntity` is its subclass base. Anything else (Node,
# Node3D, Area3D...) is an orphan risk.
const ORPHAN_SAFE_BASES := ["RefCounted", "InteractableEntity"]


var _captured: PackedStringArray = []
var _scan_root := "res://"

# @ci:save-size-budget — directory of REAL on-disk slots to measure. Empty by
# default so unit tests stay hermetic (they must never read a developer's real
# user://saves/). tests/ci/budget_assert.gd wires the live path for headless CI.
var save_scan_dir := ""


# Run every real scan against `scan_root` and return the emitted warning ids.
func run(scan_root := "res://") -> PackedStringArray:
	_captured = PackedStringArray()
	_scan_root = scan_root
	_check_dynamic_lights()
	_check_volumetric_fog()
	_check_lightmap()
	_check_vignette_ease()
	_check_contrast_c02()
	_check_save_schema()
	_check_save_size()
	_check_no_orphan_interactables()
	_check_interactable_instance_cap()
	return _captured


func _warn(check_id: String, constraint: String, detail: String) -> void:
	prints("[CI:budget][WARN][%s] %s — %s" % [check_id, constraint, detail])
	_captured.append(check_id)


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


# --- @ci:save-schema-has-version (SAV-S1, WARN-ONLY) ------------------------
# FLAG-A mitigation ①: `version` must exist, be the FIRST field on the wire, and
# equal SAVE_VERSION. This is a REAL scan of the real serializer — it encodes a
# slot exactly the way SaveManager.write_slot() does and inspects the result —
# not a stub (N-11).
func _check_save_schema() -> void:
	var before := _captured.size()

	# ① The declared wire order constant.
	var order: Array = SaveManagerScript.SLOT_FIELD_ORDER
	if order.is_empty() or str(order[0]) != "version":
		var head := str(order[0]) if not order.is_empty() else "<empty>"
		_warn("save-schema-has-version", "SLOT_FIELD_ORDER[0] is not `version`",
			"save_manager.gd -> first declared field is `%s`" % head)

	# ② The bytes the serializer actually produces.
	var slot: Dictionary = SaveManagerScript.make_slot(
		SaveManagerScript.CHECKPOINT_SLOT_ID, true, {})
	_scan_slot_schema(SaveManagerScript.encode_slot(slot), "save_manager.gd::encode_slot")

	if _captured.size() == before:
		prints("[CI:budget][OK][save-schema-has-version] `version` is field #0 and == %d"
			% SaveManagerScript.SAVE_VERSION)


## Reverse-assertion surface (N-11/N-12): feed an arbitrary slot dictionary and
## get the emitted warning ids back, so a GUT test can prove a real violation
## produces a [WARN] instead of rotting green.
func scan_slot_schema(slot: Dictionary, source := "<inline>") -> PackedStringArray:
	_captured = PackedStringArray()
	_scan_slot_schema(slot, source)
	return _captured


func _scan_slot_schema(slot: Dictionary, source: String) -> void:
	if not slot.has("version"):
		_warn("save-schema-has-version", "slot has no `version` field", source)
		return
	var keys: Array = slot.keys()
	var head := str(keys[0]) if not keys.is_empty() else "<empty>"
	if head != "version":
		_warn("save-schema-has-version", "`version` is not the first field",
			"%s -> first key is `%s`" % [source, head])
		return
	var v := int(slot["version"])
	if v != SaveManagerScript.SAVE_VERSION:
		_warn("save-schema-has-version",
			"`version` != SAVE_VERSION (%d)" % SaveManagerScript.SAVE_VERSION,
			"%s -> %d" % [source, v])


# --- @ci:save-size-budget (SAV-S2, WARN-ONLY) -------------------------------
# GDD §6: a single slot JSON must stay <= 32 KB (diff state only). Scans the
# serializer's own output plus any real slot files under `save_scan_dir`.
func _check_save_size() -> void:
	var before := _captured.size()
	var budget: int = SaveManagerScript.SLOT_SIZE_BUDGET_BYTES

	var baseline: String = SaveManagerScript.slot_to_json(
		SaveManagerScript.make_slot(SaveManagerScript.CHECKPOINT_SLOT_ID, true, {}))
	_scan_slot_size(baseline.to_utf8_buffer().size(), "save_manager.gd::default slot")

	var scanned := 0
	for f in _list_slot_files():
		var txt := FileAccess.get_file_as_string(f)
		if txt == "":
			continue
		scanned += 1
		_scan_slot_size(txt.to_utf8_buffer().size(), f)

	if _captured.size() == before:
		prints("[CI:budget][OK][save-size-budget] %d on-disk slot(s) scanned; all <= %d bytes"
			% [scanned, budget])


## Reverse-assertion surface: assert a byte count against the budget directly.
func scan_slot_size(size_bytes: int, source := "<inline>") -> PackedStringArray:
	_captured = PackedStringArray()
	_scan_slot_size(size_bytes, source)
	return _captured


func _scan_slot_size(size_bytes: int, source: String) -> void:
	var budget: int = SaveManagerScript.SLOT_SIZE_BUDGET_BYTES
	if size_bytes > budget:
		_warn("save-size-budget", "slot JSON > %d bytes" % budget,
			"%s -> %d bytes" % [source, size_bytes])


func _list_slot_files() -> PackedStringArray:
	var out := PackedStringArray()
	if save_scan_dir == "":
		return out
	var d := DirAccess.open(save_scan_dir)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if (not d.current_is_dir()) and name.begins_with("slot_") and name.ends_with(".json"):
			out.append(save_scan_dir.path_join(name))
		name = d.get_next()
	d.list_dir_end()
	return out


func _c02_fg(name: String) -> Color:
	match name:
		"HUD_COLOR_CARRIER": return HudColors.HUD_COLOR_CARRIER
		_: return Color.BLACK


# --- @ci:no-orphan-interactables (E07-S7, WARN-ONLY) ------------------------
# ★ WARN-ONLY BY DESIGN. sprint2-stories E07-S7 is explicit: "静态扫描 orphan>0
#   仅 WARN-ONLY，不进 N-7 门". Do NOT promote this to a hard failure without a
#   design decision — same [D15-A]/[N-12] rule the SAV checks live under.
#
# Two REAL scans, no stubs (N-11):
#   ① Every interactable script must sit on a RefCounted lineage. This is the
#      structural reason an interactable can never orphan — there is no
#      queue_free() to forget.
#   ② No .tscn may attach an interactable script to a scene node. Placing one in
#      a scene hands its lifetime to the scene tree instead of the registry,
#      which is exactly the ownership split E07-S7 exists to prevent.
func _check_no_orphan_interactables() -> void:
	var before := _captured.size()
	var files := _list_gd(INTERACTABLE_DIR)
	for f in files:
		var base := _extends_of(f)
		if base == "":
			continue
		if not ORPHAN_SAFE_BASES.has(base):
			_warn("no-orphan-interactables",
				"interactable extends `%s` (Node lineage can orphan)" % base,
				"%s -> must extend RefCounted or InteractableEntity" % f.get_file())
	for f in _list_tscn():
		var n := _count_interactable_script_refs(f)
		if n > 0:
			_warn("no-orphan-interactables",
				"interactable script attached to a scene node",
				"%s -> %d attachment(s); spawn via InteractableRegistry instead"
					% [f.get_file(), n])
	if _captured.size() == before:
		prints("[CI:budget][OK][no-orphan-interactables] %d interactable script(s) on a RefCounted lineage; 0 attached to a scene node"
			% files.size())


# --- @ci:interactable-instance-cap (E07-S8, WARN-ONLY) ----------------------
# The interactable instance ceiling is DERIVED from the two hard control-manifest
# budgets this system can push against, and E07-S8 requires that adding DECOY /
# LIGHT_TOGGLE must not break them:
#   R-02 realtime lights  <= 12 MVP / <= 32 Tier2  (a LIT LightToggleEntity holds one)
#   G-02 sound rings      <= 8                     (a thrown DECOY claims one)
# Neither existing assertion is modified: _check_dynamic_lights() still counts
# real OmniLight3D/SpotLight3D nodes, and G-02 stays a RUNTIME assertion owned by
# test_sound_propagation.gd::test_ring_vfx_capped_at_eight [D14-A].
func _check_interactable_instance_cap() -> void:
	var before := _captured.size()
	var cap: int = InteractableRegistryScript.INSTANCE_CAP

	# ① The cap constant itself must stay inside R-02. If someone raises it past
	#    the Tier2 light budget, a level of all-lit fixtures could exceed R-02
	#    before this check ever fires on a scene — so check the NUMBER, not just
	#    the scenes.
	if cap > LIGHT_BUDGET_TIER2:
		_warn("interactable-instance-cap",
			"INSTANCE_CAP %d exceeds the R-02 Tier2 light budget (%d)" % [cap, LIGHT_BUDGET_TIER2],
			"interactable_registry.gd -> an all-LIT level could break R-02")

	# ② Per-scene static placement count.
	var worst := 0
	var worst_file := ""
	for f in _list_tscn():
		var n := _count_interactable_script_refs(f)
		if n > worst:
			worst = n
			worst_file = f.get_file()
		if n > cap:
			_warn("interactable-instance-cap",
				"scene declares %d interactables > cap %d" % [n, cap], f.get_file())

	if _captured.size() == before:
		var where := worst_file if worst_file != "" else "<none>"
		prints("[CI:budget][OK][interactable-instance-cap] cap=%d (<= R-02 Tier2 %d); busiest scene: %s (%d)"
			% [cap, LIGHT_BUDGET_TIER2, where, worst])


## Reverse-assertion surface (N-11/N-12): hand in a base-class name and get the
## emitted warning ids back, so a GUT test can prove a Node-based interactable
## really produces a [WARN] instead of the scan rotting green.
func scan_interactable_base(base: String, source := "<inline>") -> PackedStringArray:
	_captured = PackedStringArray()
	if not ORPHAN_SAFE_BASES.has(base):
		_warn("no-orphan-interactables",
			"interactable extends `%s` (Node lineage can orphan)" % base,
			"%s -> must extend RefCounted or InteractableEntity" % source)
	return _captured


## Reverse-assertion surface: hand in a per-scene instance count.
func scan_interactable_count(count: int, source := "<inline>") -> PackedStringArray:
	_captured = PackedStringArray()
	var cap: int = InteractableRegistryScript.INSTANCE_CAP
	if count > cap:
		_warn("interactable-instance-cap",
			"scene declares %d interactables > cap %d" % [count, cap], source)
	return _captured


func _count_interactable_script_refs(tscn_path: String) -> int:
	var txt := FileAccess.get_file_as_string(tscn_path)
	if txt == "":
		return 0
	var count := 0
	for line in txt.split("\n"):
		# An ext_resource line pointing into the interactable dir means the
		# scene carries one of these scripts on a node.
		if "src/game/interactables/" in line and ".gd" in line:
			count += 1
	return count


func _extends_of(gd_path: String) -> String:
	var txt := FileAccess.get_file_as_string(gd_path)
	if txt == "":
		return ""
	for line in txt.split("\n"):
		var t := line.strip_edges()
		if t.begins_with("extends "):
			return t.substr(8).strip_edges()
	return ""


# --- scene-walk helpers ----------------------------------------------------
func _list_tscn() -> PackedStringArray:
	var out := PackedStringArray()
	_dir_walk(_scan_root, out)
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


## Every .gd directly inside `dir` (non-recursive: the interactable layer is
## deliberately flat). Returns an empty list when the dir does not exist, so the
## scan degrades to "nothing to check" instead of crashing CI.
func _list_gd(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if (not d.current_is_dir()) and name.ends_with(".gd"):
			out.append(dir.path_join(name))
		name = d.get_next()
	d.list_dir_end()
	return out


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
