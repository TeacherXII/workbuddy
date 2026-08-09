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

# Phase 6, D1 — checkpoint loop nodes. Unlike SaveSlotsScreen (deliberately NOT
# mounted in the slice), the restore consumer is a HARD dependency of the core
# loop, so it is wired here. The producer captures the world diff on safe-progress
# triggers; both resolve SaveManager/EventBus via their groups at _ready.
var _checkpoint_producer: CheckpointProducer = null
var _checkpoint_applier: CheckpointApplier = null


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
	_wire_audio_director()


## E-7 (S3-B). The audio layer's ONE subscription, made from the side that owns
## the publisher: AudioDirector is an autoload, TimeController is not, so the
## director cannot go looking for it (and deliberately does not — see
## audio_director.gd set_time_controller()).
##
## Skip this call and nothing breaks loudly: the director still boots, still
## plays UI cues, still runs the load fade. What silently disappears is every
## World-bus preset (ADR-005 D-3) — 凝神 and 暂停 stop ducking, with no error,
## no crash and nothing for CI to see. Same failure class as F-5, so the wire
## lives here, on the line after the controller is born.
##
## get_node_or_null rather than a hard $ path: a unit test may build this
## bootstrap inside a tree where the autoload was never registered, and a
## missing ducking wire must not take the whole slice down with it.
func _wire_audio_director() -> void:
	var director := get_node_or_null("/root/AudioDirector")
	if director == null:
		return
	if not director.has_method("set_time_controller"):
		push_warning("Sprint0Bootstrap: /root/AudioDirector has no set_time_controller")
		return
	director.set_time_controller(_time)


# ── ★ The other half of E-7 has no construction site yet ────────────────────
# SaveSlotsScreen (SCR_SLOTS) is NOT mounted in this vertical slice; today it is
# built only by tests/unit/test_save_ui.gd. So the cue sink and the fade sink
# have nowhere to be attached from production code, and inventing a call site
# here would mean bolting a save UI onto a demo that has no menu to open it.
#
# When the screen does get a real home, wire it with the ONE call that attaches
# both sinks together:
#
#     screen.wire_audio(get_node("/root/AudioDirector"))
#
# NOT set_audio_sink() alone. Attaching only the cue sink is exactly the F-5
# defect: the load fade would never reach the director, so nothing would ever
# call end_load_fade(), and the World bus would stay parked at -12 dB / LPF
# 700 Hz for the rest of the session. wire_audio() exists so that the wrong
# half cannot be wired on its own, and test_audio_bus_layout.gd fails the build
# if a future construction site tries.


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
	cam.look_at_from_position(cam.position, Vector3.ZERO, Vector3.UP)
	add_child(cam)

	# One shadow box in the demo light model (cover-shadow §2 mock).
	_light.add_shadow_box(Vector3(3, 0, 3), 2.0)


func _wire_signals() -> void:
	if _bus == null or _step == null or _vc == null:
		return
	# Phase 6, D1 — the player now exists (built in _setup_scene); hand it to the
	# checkpoint nodes so a restore can reposition the player to the snapshot.
	if _checkpoint_producer != null:
		_checkpoint_producer.player_node = _player
	if _checkpoint_applier != null:
		_checkpoint_applier.player_node = _player
	_step.player_step_committed.connect(_bus.player_step_committed.emit)
	# G1 (S1C-FIX-01): the legacy StepCommit.sound_emitted -> bus bridge is
	# removed. SoundPropagator (E06) is now the sole owner of EventBus
	# .sound_emitted; it listens to player_step_committed and emits the full
	# payload. Keeping this bridge double-emitted sound with an incomplete dict.
	# Wire SoundPropagator into the demo so it is the functional (sole) bus
	# emitter: its _ready() binds player_step_committed -> emit(enriched).
	_sound.set_event_bus(_bus)
	add_child(_sound)

	# Phase 6, D1 — mount the checkpoint write-end + restore-end. The slice has no
	# GuardSpawner / InteractableRegistry, so those collaborators stay null here;
	# a full level wires them. The producer/applier resolve SaveManager + EventBus
	# via their groups on _ready, and player_node is assigned in _wire_signals
	# (after _setup_scene builds _player).
	_checkpoint_producer = CheckpointProducer.new()
	_checkpoint_producer.light_model = _light
	add_child(_checkpoint_producer)
	_checkpoint_applier = CheckpointApplier.new()
	_checkpoint_applier.light_model = _light
	add_child(_checkpoint_applier)
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
