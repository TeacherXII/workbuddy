class_name FootfallVFX
extends Node

# ASHEN STEP — Sprint 1, E03-S7. Footfall visual feedback, kept self-contained so
# StepCommit stays headless-safe: StepCommit only instantiates/uses this when a
# live scene tree exists (Engine.get_main_loop() + is_inside_tree()).
#
# Feedback (art-bible §1: physical/tactile, NOT celebratory):
#   - landing micro-glow: emissive quad, color #C8862F (C-06 主色板), alpha <= 0.10
#     (non-realtime light, saves R-02 dynamic-light budget).
#   - footfall foley: surface-variant subtitle stub (X-02 字幕占位). Real audio is
#     wired by the audio system; here we only emit a signal carrying the label.
#   - ghost_trail: owned by StepCommit (gameplay data, capped at MAX_GHOST); this
#     class only renders the visual fade, which scales with time_scale (T-04).

const LANDING_GLOW_COLOR := Color("#C8862F")   # C-06 主色板内
const LANDING_GLOW_ALPHA_CAP := 0.10           # <=10% 画面纪律 (art-bible §2.1)

# surface -> foley subtitle label (X-02 字幕占位)
const FOOTFALL_SUBTITLE := {
	"STONE": "足音·石板",
	"GRASS": "足音·草甸",
	"METAL": "足音·金属",
	"MOSS":  "足音·苔地",
	"WOOD":  "足音·木",
}

signal footfall_foley(surface: String, subtitle: String)


func spawn_landing_glow(pos: Vector3) -> MeshInstance3D:
	# Emissive quad micro-glow at the landing point. Non-realtime light (R-02):
	# a flat emissive quad on the ground, never an OmniLight3D.
	var quad := MeshInstance3D.new()
	quad.mesh = QuadMesh.new()
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.emissive_enabled = true
	mat.emissive_color = LANDING_GLOW_COLOR
	mat.emissive_intensity = LANDING_GLOW_ALPHA_CAP
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var col := LANDING_GLOW_COLOR
	col.a = LANDING_GLOW_ALPHA_CAP
	mat.albedo_color = col
	quad.material_override = mat
	quad.position = pos
	# lie flat on the ground plane (top-down camera)
	quad.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	add_child(quad)
	return quad


func emit_foley(surface: String) -> void:
	var label: String = FOOTFALL_SUBTITLE.get(surface, "足音")
	footfall_foley.emit(surface, label)


func footfall_subtitle(surface: String) -> String:
	return FOOTFALL_SUBTITLE.get(surface, "足音")
