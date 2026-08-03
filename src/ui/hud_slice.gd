class_name HudSlice
extends CanvasLayer

# ASHEN STEP — Sprint 0 vertical slice (Phase 5). E09 core HUD + a11y.
# Near-diegetic, low-glare panel: focus dim overlay (#10141C), status / focus
# readout, suspicion placeholder bar (0-100), and a landing preview footprint
# (#C8862F, C-05/C-03 brightness + shape coding). Dark panel + #3E5C76 stroke
# (ux-spec §3). No flashing UI (V-06).

const FOCUS_TINT := Color("#10141C")
const PREVIEW_COLOR := Color("#C8862F")
const STROKE_COLOR := Color("#3E5C76")

var _bus: EventBus = null
var _dim: ColorRect = null
var _status: Label = null
var _suspicion: ProgressBar = null
var _preview: Control = null


func _ready() -> void:
	# Prefer an explicitly injected bus (set_event_bus). The group lookup is only
	# a fallback for scene-driven wiring: get_first_node_in_group returns the
	# FIRST registered EventBus, which is not necessarily the one this HUD is
	# meant to observe when several buses exist in the tree.
	if _bus == null:
		_bus = get_tree().get_first_node_in_group("event_bus") as EventBus
	_build_ui()
	_connect_bus()


# Explicit dependency injection (preferred over the group lookup). Safe to call
# before or after the node enters the tree: the UI widgets are null-guarded in
# every handler, and _connect_bus is idempotent.
func set_event_bus(bus: EventBus) -> void:
	_bus = bus
	_connect_bus()


func _connect_bus() -> void:
	if _bus == null or not is_instance_valid(_bus):
		return
	# Idempotent: _ready and set_event_bus may both run, in either order.
	if not _bus.time_scale_changed.is_connected(_on_time_scale_changed):
		_bus.time_scale_changed.connect(_on_time_scale_changed)
	if not _bus.vision_stimulus.is_connected(_on_vision_stimulus):
		_bus.vision_stimulus.connect(_on_vision_stimulus)
	if not _bus.suspicion_changed.is_connected(_on_suspicion_changed):
		_bus.suspicion_changed.connect(_on_suspicion_changed)
	if not _bus.player_step_committed.is_connected(_on_step_committed):
		_bus.player_step_committed.connect(_on_step_committed)


func _build_ui() -> void:
	# Focus dim overlay (covers viewport, only visible while focusing).
	_dim = ColorRect.new()
	_dim.color = Color(FOCUS_TINT.r, FOCUS_TINT.g, FOCUS_TINT.b, 0.35)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.visible = false
	add_child(_dim)

	# Status / focus readout (top-left).
	_status = Label.new()
	_status.text = "灰烬之步 · Sprint0"
	_status.add_theme_color_override("font_color", Color("#DCE3EC"))
	_status.position = Vector2(16, 12)
	add_child(_status)

	# Suspicion placeholder bar (bottom, 0-100).
	_suspicion = ProgressBar.new()
	_suspicion.min_value = 0.0
	_suspicion.max_value = 100.0
	_suspicion.value = 0.0
	_suspicion.show_percentage = false
	_suspicion.custom_minimum_size = Vector2(240, 18)
	_suspicion.position = Vector2(16, 40)
	add_child(_suspicion)

	# Landing preview footprint (color #C8862F, shape-coded) — hidden until aim.
	_preview = Control.new()
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.custom_minimum_size = Vector2(28, 28)
	var fp := ColorRect.new()
	fp.color = Color(PREVIEW_COLOR.r, PREVIEW_COLOR.g, PREVIEW_COLOR.b, 0.85)
	fp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview.add_child(fp)
	_preview.visible = false
	add_child(_preview)


func set_aim_preview(world_pos: Vector3) -> void:
	if _preview == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		_preview.visible = false
		return
	var screen := cam.unproject_position(world_pos)
	_preview.position = screen - _preview.custom_minimum_size * 0.5
	_preview.visible = true


func _on_time_scale_changed(_old: float, _new: float, mode: String) -> void:
	if _status == null:
		return
	if mode == "FOCUS":
		_status.text = "凝神 0.25×"
		if _dim != null:
			_dim.visible = true
	else:
		_status.text = "FLOWING 1.0×"
		if _dim != null:
			_dim.visible = false


func _on_vision_stimulus(_guard_id: int, _target: Node, visibility: float) -> void:
	if _suspicion != null:
		_suspicion.value = clampf(visibility * 100.0, 0.0, 100.0)


func _on_suspicion_changed(_guard_id: int, value: float, _tier: int) -> void:
	if _suspicion != null:
		_suspicion.value = clampf(value, 0.0, 100.0)


func _on_step_committed(_payload: Dictionary) -> void:
	# Optional: confirm footprint on commit.
	if _preview != null:
		_preview.visible = true
