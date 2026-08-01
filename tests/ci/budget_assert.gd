# tests/ci/budget_assert.gd
# Headless budget static-assertion runner + Sprint 0 exit-criterion (⑤) smoke
# gate skeleton (control-manifest §7; warn-only).
#
# Run:  godot --headless --path . -s res://tests/ci/budget_assert.gd -gexit
#
# Phase 5 (quality-lead): refines the Phase 4 placeholder into a CI-callable
# skeleton. All budget items are WARN-ONLY (lean: do not block the build,
# per control-manifest §7 + tests/ci-note.md). Real scene/resource scans are
# stubbed with TODO markers and must be implemented in later Sprints.
#
# The Sprint 0 exit criterion ⑤ (GUT smoke green under godot --headless) is
# declared here as a required gate. This script does NOT run GUT itself (GUT is
# invoked separately by CI), but it records the gate + the exact command.

extends SceneTree


const EXIT_OK := 0


func _initialize() -> void:
	prints("[CI:budget] ===== ASHEN STEP budget + Sprint0 exit gate (warn-only) =====")
	_report_smoke_requirement()      # Exit criterion ⑤ (epic-overview §3)
	_check_dynamic_lights()          # R-02
	_check_volumetric_fog()          # R-04
	_check_light_extinction_ramp()   # R-05
	_check_static_mesh_uv2()         # ADR-004 / R-06
	_check_sound_rings()             # G-02
	_check_pulse_frequency()         # V-02
	prints("[CI:budget] All checks are WARN-ONLY. Exit 0 (lean: build not blocked).")
	prints("[CI:budget] Review any [WARN] lines and route drift to the lead for adjudication.")
	quit(EXIT_OK)


func _report_smoke_requirement() -> void:
	# epic-overview §3 退出标准⑤: GUT smoke must be green under godot --headless.
	prints("[CI:budget][GATE-⑤] Sprint 0 exit: GUT smoke green under headless REQUIRED.")
	prints("[CI:budget][GATE-⑤]   cmd: godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit")
	prints("[CI:budget][GATE-⑤]   status: SMOKE-RUNNER-EXTERNAL (invoke from CI; this script only records the gate)")


func _warn(check_id: String, constraint: String, detail: String) -> void:
	prints("[CI:budget][WARN][%s] %s — %s (TODO: implement scan, see tests/ci-note.md)" % [check_id, constraint, detail])


func _check_dynamic_lights() -> void:
	# R-02: dynamic OmniLight3D/SpotLight3D > 32 -> warn.
	_warn("R-02", "dynamic lights > 32", "scan .tscn for active Omni/Spot lights; warn if > 32")


func _check_volumetric_fog() -> void:
	# R-04: WorldEnvironment.volumetric_fog_density > 0.05 base -> warn.
	_warn("R-04", "volumetric fog base > 0.05", "read WorldEnvironment.fog_density; warn if > 0.05")


func _check_light_extinction_ramp() -> void:
	# R-05: light-extinction fog ramp > 0.12 or > 0.4s -> warn.
	_warn("R-05", "extinction ramp > 0.12 / > 0.4s", "measure ramp curve; warn if exceeds limits")


func _check_static_mesh_uv2() -> void:
	# ADR-004 / R-06: static mesh missing UV2 -> warn.
	_warn("R-06", "static mesh missing UV2", "verify .glb export has UV2; warn if absent (LightmapGI)")


func _check_sound_rings() -> void:
	# G-02: active sound rings > 8 -> warn.
	_warn("G-02", "sound rings > 8", "count live sound-ring instances at runtime; warn if > 8")


func _check_pulse_frequency() -> void:
	# V-02: exposure/cone pulse shader freq > 2Hz -> warn.
	_warn("V-02", "pulse freq > 2Hz", "read shader pulse uniform; warn if > 2Hz")
