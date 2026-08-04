class_name Sprint0Bootstrap
extends Node3D

# ASHEN STEP — Sprint 0 vertical slice (Phase 5). Vertical-slice demo assembly
# (NOT a full game loop). Wires the L2 core (EventBus / TimeController /
# InputManager / A11ySettings) to the L4 gameplay nodes (StepCommit / VisionCone
# / LightModel / HudSlice) and provides minimal mouse/keyboard interaction:
#   - hold right mouse / Shift  -> FOCUS (slow-mo)
#   - left click                -> set aim point (ray to ground plane y=0)
#   - release focus             -> commit step to aim point on STONE
#   - Ctrl / G                  -> toggle gait

var _bus: EventBus = null
var _time: TimeController = null
var _input: InputManager = null
var _a11y: A11ySettings = null
var _step: StepCommit = null
var _light: LightModel = null
var _vc: VisionCone = null
var _hud: HudSlice = null
var _sound: SoundPropagator = null   # G1: canonical (sole) owner of bus.sound_emitted
var _player: Marker3D = null
var _guard: Marker3D = null


func _ready() -> void:
	_register_input()
	_spawn_event_bus()
	_instantiate_systems()
	_setup_scene()
	_wire_signals()
	if _a11y != null:
		_a11y.load()


func _register_input() -> void:
	if not InputMap.has_action("ui_focus"):
		InputMap.add_action("ui_focus")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event("ui_focus", mb)
		var ks := InputEventKey.new()
		ks.keycode = KEY_SHIFT
		InputMap.action_add_event("ui_focus", ks)
	if not InputMap.has_action("toggle_gait"):
		InputMap.add_action("toggle_gait")
		var kc := InputEventKey.new()
		kc.keycode = KEY_CTRL
		InputMap.action_add_event("toggle_gait", kc)
		var kg := InputEventKey.new()
		kg.keycode = KEY_G
		InputMap.action_add_event("toggle_gait", kg)


func _spawn_event_bus() -> void:
	# EventBus is not an autoload in the slice; create it so group lookups
	# ("event_bus") resolve for every system that grabs it.
	var bus := EventBus.new()
	bus.name = "EventBus"
	add_child(bus)   # its _ready registers group "event_bus"
	_bus = get_tree().get_first_node_in_group("event_bus") as EventBus


func _instantiate_systems() -> void:
	_time = TimeController.new(); add_child(_time)
	_input = InputManager.new(); add_child(_input)
	_a11y = A11ySettings.new(); add_child(_a11y)
	_step = StepCommit.new(); add_child(_step)
	_light = LightModel.new()
	_vc = VisionCone.new()
	_vc.set_light_model(_light)   # share the demo light model (has shadow box)
	add_child(_vc)
	_hud = HudSlice.new(); add_child(_hud)
	_sound = SoundPropagator.new()   # G1: sole bus emitter of sound_emitted


func _setup_scene() -> void:
	_player = Marker3D.new()
	_player.name = "Player"
	_player.position = Vector3.ZERO
	add_child(_player)

	_guard = Marker3D.new()
	_guard.name = "Guard"
	_guard.position = Vector3(0, 0, 8)
	add_child(_guard)

	# Minimal camera so aim raycasting + HUD unproject have a projection.
	var cam := Camera3D.new()
	cam.position = Vector3(0, 12, -12)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	add_child(cam)

	# One shadow box in the demo light model (cover-shadow §2 mock).
	_light.add_shadow_box(Vector3(3, 0, 3), 2.0)


func _wire_signals() -> void:
	if _bus == null or _step == null or _vc == null:
		return
	_step.player_step_committed.connect(_bus.player_step_committed.emit)
	# G1 (S1C-FIX-01): the legacy StepCommit.sound_emitted -> bus bridge is
	# removed. SoundPropagator (E06) is now the sole owner of EventBus
	# .sound_emitted; it listens to player_step_committed and emits the full
	# payload. Keeping this bridge double-emitted sound with an incomplete dict.
	# Wire SoundPropagator into the demo so it is the functional (sole) bus
	# emitter: its _ready() binds player_step_committed -> emit(enriched).
	_sound.set_event_bus(_bus)
	add_child(_sound)
	# E05 contract: forward the raw vision stimulus onto the bus. Other
	# consumers (GuardBrain, telemetry) subscribe here. KEEP.
	_vc.vision_stimulus.connect(_bus.vision_stimulus.emit)
	# Batch C / N-6: the Sprint 0 provisional shim that converted
	# `visibility * 100` into a `suspicion_changed` emission is DELETED.
	# It was a shadow writer on a legitimate channel: in the demo scene it
	# raced GuardBrain at >=10Hz over the same guard_id (landmine (1) merely
	# moved one layer up), and unit tests could never see it because
	# test_hud_slice.gd never loads this bootstrap.
	# After E08-S2, GuardBrain is the SOLE producer of `suspicion_changed`.


func _process(_delta: float) -> void:
	if _time != null and _input != null:
		var focusing := _input.is_focus_held()
		if focusing and _time.mode != "FOCUS":
			_time.enter_focus()
		elif not focusing and _time.mode == "FOCUS":
			_time.exit_focus()
			if _step != null and _step.can_commit() and _step.aim_point != Vector3.ZERO:
				_step.commit(_player.global_position, _step.aim_point, "STONE")
				_step.aim_point = Vector3.ZERO
	if _vc != null and _player != null and _guard != null:
		_vc.observer_pos = _guard.global_position
		_vc.player_pos = _player.global_position
		_vc.observer_forward = (_player.global_position - _guard.global_position).normalized()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_aim_at_mouse(mb)
	elif event.is_action_pressed("toggle_gait"):
		if _input != null:
			_input.toggle_gait()


func _aim_at_mouse(mb: InputEventMouseButton) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _step == null or _player == null:
		return
	var origin := cam.project_ray_origin(mb.position)
	var normal := cam.project_ray_normal(mb.position)
	if abs(normal.y) < 0.0001:
		return
	var t := -origin.y / normal.y
	if t < 0.0:
		return
	var hit := origin + normal * t
	_step.aim_point = hit
	if _hud != null:
		_hud.set_aim_preview(hit)
