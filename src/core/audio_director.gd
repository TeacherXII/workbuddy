extends Node

# ASHEN STEP — Sprint 3, Batch B. E11 · SAV-S5. THE PROJECT'S FIRST AUDIO CODE.
#
# Spec:  design/audio/s3b-save-load-audio-spec.md  (§1.3 §1.4 §2.3 §2.5 §5.2–5.8)
# ADR:   docs/architecture/adr/adr-005-audio-bus-architecture-and-world-mode-presets.md
# Plan:  design/audio/oos-resolution.md §4  (E-1 … E-11)
#
# ── ⚠ NO `class_name` ────────────────────────────────────────────────────────
# This script is an autoload (project.godot [autoload] AudioDirector). Godot 4
# refuses a global class that shadows an autoload of the same name — the exact
# same trap already documented on src/core/save_manager.gd. Do not "tidy" a
# `class_name AudioDirector` onto this file; it will not boot.
#
# ── Zero new signals (E01-S9 freeze) ────────────────────────────────────────
# This node declares NO signal and adds NO vocabulary to EventBus. It SUBSCRIBES
# to exactly one pre-existing signal, TimeController.time_scale_changed, and is
# otherwise driven by direct calls / injected Callables.
#
# ── ⚠ NO Tween, NO Timer, NO SceneTreeTimer, ANYWHERE IN THIS FILE ──────────
# AUD-F2 forbids the audio layer from owning a time source for the load fade:
# two independent clocks are precisely what produces the「先听到后看到」mismatch
# the spec exists to prevent. The 0.4s load fade is driven frame-by-frame from
# SaveSlotsScreen.tick() through fade_sink().
#
# The 120 ms world-mode ramp (AUD-V6) IS ours, but it still runs on the WALL
# CLOCK read in _process(), not on the scaled delta — because this node is the
# one thing that must keep working while Engine.time_scale is 0.0 (T-03 pause).
# A scaled delta would freeze the ramp exactly when we need it most, and a Tween
# would additionally trip E-10 assertion 7.

# ── Bus names (spec §5.2 / ADR-005 D-1) ─────────────────────────────────────
const BUS_MASTER := "Master"
const BUS_WORLD := "World"          # child of Master
const BUS_MUSIC := "Music"          # child of World
const BUS_AMBIENCE := "Ambience"    # child of World
const BUS_SFX_WORLD := "SFX_World"  # child of World
const BUS_VOICE := "Voice"          # child of World (empty this batch)
const BUS_SFX_UI := "SFX_UI"        # ★ child of MASTER, deliberately NOT World

# ── World mode presets (spec §1.4 / §5.8, ADR-005 D-3) ──────────────────────
const MODE_FLOWING := "FLOWING"
const MODE_FOCUS := "FOCUS"
const MODE_PAUSED := "PAUSED"

const WORLD_DB_FLOWING := 0.0
const WORLD_DB_FOCUS := -3.5
const WORLD_DB_PAUSED := -12.0
const WORLD_LPF_FLOWING_HZ := 20500.0   # = bypass. Never toggle `enabled` (click).
const WORLD_LPF_FOCUS_HZ := 1200.0
const WORLD_LPF_PAUSED_HZ := 700.0
const WORLD_MODE_RAMP_SEC := 0.12       # AUD-V6, the audible dual of V-06

# ── Load fade (spec §2.3 / §5.8) ────────────────────────────────────────────
const WORLD_FLOOR_DB := -60.0
const FADE_MIN_ALPHA := 0.001           # linear_to_db(0.001) == -60 dB exactly

# ── UI polyphony & retrigger (spec §2.5 / §5.8) ─────────────────────────────
const UI_POOL_SIZE := 3
const UI_RETRIGGER_SUPPRESS_MS := 80
const UI_REPEAT_STEP_DB := -2.0
const UI_REPEAT_FLOOR_DB := -9.0
const UI_REPEAT_RESET_MS := 600
# 20 ms. Hard-stopping a decaying wave is a DC step = a bright click = red line.
const UI_STEAL_FADE_SEC := 0.020

# ── Cue table ── ★ AUD-G1: every base_gain_db is EXACTLY 0.0 ────────────────
# The cue table is a NAME→ASSET map and nothing else. All relative level lives
# in the caller's gain_db, which is the single place a reviewer has to look.
#
# `action_denied` is an ALIAS of save_failure, NOT a second asset. Rendering a
# separate file 3 dB down would stack with save_slots_screen.gd L285's -3.0 and
# land at -6 dB — an error no current test can see, because the suite only
# asserts the CALLER's argument. Same reasoning for the delete path, which
# reuses save_success at -1.0 rather than minting a cue.
const CUE_TABLE := {
	"save_success": {
		"path": "res://arts/audio/ui/sfx_ui_save_success.wav",
		"base_gain_db": 0.0,
		"bus": BUS_SFX_UI,
	},
	"save_failure": {
		"path": "res://arts/audio/ui/sfx_ui_save_failure.wav",
		"base_gain_db": 0.0,
		"bus": BUS_SFX_UI,
	},
	"action_denied": {
		"path": "res://arts/audio/ui/sfx_ui_save_failure.wav",
		"base_gain_db": 0.0,
		"bus": BUS_SFX_UI,
	},
}

# ── Players (spec §5.3 / §4.4) ──────────────────────────────────────────────
var _ui_players: Array = []
var _ui_start_ms: Array = []       # int  — when this voice began (steal order)
var _ui_fade_left: Array = []      # float— seconds left of a 20 ms steal fade
var _ui_fade_from_db: Array = []   # float
var _ui_pending: Array = []        # {} or {"stream": …, "db": …} queued behind a steal
var _ambience_player: AudioStreamPlayer = null
var _music_player: AudioStreamPlayer = null

# ── World mode state ────────────────────────────────────────────────────────
var _mode := MODE_FLOWING
var _db_from := WORLD_DB_FLOWING
var _db_to := WORLD_DB_FLOWING
var _hz_from := WORLD_LPF_FLOWING_HZ
var _hz_to := WORLD_LPF_FLOWING_HZ
var _ramp_left := 0.0

# ── Load fade state ─────────────────────────────────────────────────────────
var _fading := false

# ── Retrigger ladder (AUD-R1) ───────────────────────────────────────────────
var _ladder_enabled := true
var _last_play_ms: Dictionary = {}
var _ladder_step: Dictionary = {}

# ── A-05「UI 音」总开关 (control-manifest §8 A-05) ──────────────────────────
# Gates play_cue() and NOTHING ELSE. Scope is deliberate and load-bearing:
#
#   · It does NOT touch the World bus, the load fade or the world-mode presets.
#     Those are not UI feedback, and a player who silenced the interface never
#     asked for the world to go quiet too.
#   · It does NOT suppress the SUBTITLE or the visual twin. A-02 says audio is
#     never the only channel, so turning this off must LOSE nothing — the cue
#     is a redundant third channel by construction. The subtitle sink lives on
#     save_slots_screen.gd and is not routed through here, which is what makes
#     that guarantee structural rather than a promise. Asserted in
#     tests/unit/test_audio_cues.gd.
#
# Public (no leading underscore) because the settings panel writes it through
# set_ui_sound_enabled() and tests read it back.
var ui_sound_enabled := true

# ── Misc ────────────────────────────────────────────────────────────────────
var _tc: Node = null
var _last_ms := 0
var _missing_warned: Dictionary = {}

# Observability for tests / QA. NEVER read for control flow.
var cue_log: Array = []
var fade_log: Array = []


func _ready() -> void:
	# T-03 is still undecided between get_tree().paused and Engine.time_scale=0.
	# ALWAYS is correct under BOTH, so this does not have to wait for that call.
	# Under PAUSABLE the save-success cue would simply never sound, because the
	# save screen only exists while the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_players()
	_last_ms = Time.get_ticks_msec()
	# Deliberately does NOT go looking for a TimeController. Nothing is resolved
	# implicitly here; see set_time_controller().


func _build_players() -> void:
	for i in range(UI_POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.name = "UiVoice%d" % i
		p.bus = BUS_SFX_UI
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_ui_players.append(p)
		_ui_start_ms.append(0)
		_ui_fade_left.append(0.0)
		_ui_fade_from_db.append(0.0)
		_ui_pending.append({})

	_ambience_player = AudioStreamPlayer.new()
	_ambience_player.name = "AmbienceBed"
	_ambience_player.bus = BUS_AMBIENCE
	_ambience_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_ambience_player)

	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicBed"
	_music_player.bus = BUS_MUSIC
	_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music_player)

	# World SFX players are NOT created here. They belong to the gameplay layer
	# and must keep the default PAUSABLE mode, because world sound SHOULD freeze
	# with the world (spec §4.4 last row).


# =============================================================================
# Wiring
# =============================================================================
## The ONLY subscription this node makes. TimeController is not an autoload, so
## it is injected rather than looked up. Duck-typed on purpose: a unit test can
## pass any Node that carries the same signal.
func set_time_controller(tc: Node) -> void:
	if _tc != null and is_instance_valid(_tc) \
			and _tc.has_signal("time_scale_changed") \
			and _tc.time_scale_changed.is_connected(_on_time_scale_changed):
		_tc.time_scale_changed.disconnect(_on_time_scale_changed)
	_tc = tc
	if tc == null or not is_instance_valid(tc):
		return
	if not tc.has_signal("time_scale_changed"):
		push_warning("AudioDirector: injected time controller has no time_scale_changed")
		return
	if not tc.time_scale_changed.is_connected(_on_time_scale_changed):
		tc.time_scale_changed.connect(_on_time_scale_changed)


func _on_time_scale_changed(_old: float, _new: float, mode: String) -> void:
	set_world_mode(mode)


## E-7. The fourth sink of save_slots_screen.gd (§5.6). Passing this method as a
## Callable keeps the screen headless-testable: it never names AudioDirector.
func fade_sink(phase: String, alpha: float) -> void:
	match phase:
		"begin":
			begin_load_fade()
		"tick":
			set_load_fade(alpha)
		"end":
			end_load_fade()
		_:
			push_warning("AudioDirector: unknown fade phase %s" % phase)


# =============================================================================
# Cues
# =============================================================================
## Spec §5.5. `gain_db` is the caller's and is the ONLY static source of
## relative level (AUD-G1). AUD-R1 may subtract on top of it for repeats.
func play_cue(cue: String, gain_db: float = 0.0) -> void:
	# A-05. FIRST statement on purpose: when the player has switched UI sound
	# off, nothing downstream should run — not the retrigger ladder (whose state
	# would then advance on cues nobody heard, so the first cue AFTER re-enabling
	# would come back attenuated), and not cue_log (which is the observability
	# record of what SOUNDED; logging silent cues would make it lie).
	if not ui_sound_enabled:
		return

	if not CUE_TABLE.has(cue):
		push_warning("AudioDirector: unknown cue '%s'" % cue)
		return

	var ladder: Dictionary = _ladder_tick(cue)
	if not bool(ladder.get("play", true)):
		return   # AUD-R1: < 80 ms since the last same-named cue.

	var db := effective_level_db(cue, gain_db) + float(ladder.get("db", 0.0))
	cue_log.append({"cue": cue, "gain_db": gain_db, "level_db": db})

	var path := resolve_stream_path(cue)
	# The two .wav assets are a separate delivery. Until they land this is a
	# no-op rather than a load error — the wiring above is still exercised and
	# still assertable through cue_log / effective_level_db().
	if path == "" or not ResourceLoader.exists(path):
		if not _missing_warned.has(path):
			_missing_warned[path] = true
			push_warning("AudioDirector: cue asset not present yet: %s" % path)
		return

	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		return

	var slot := _free_voice()
	if slot >= 0:
		_start_voice(slot, stream, db)
		return

	# All three voices busy → steal the OLDEST (spec §2.5.3). It fades out over
	# 20 ms and the new cue starts the instant that finishes, which keeps the
	# hard cap of 3 simultaneous UI voices AND avoids the DC-step click. The
	# ≤20 ms delay is far inside AUD-F5's 40 ms lag tolerance, and only a
	# three-deep pile-up can ever reach this branch.
	var victim := _oldest_voice()
	if victim < 0:
		return
	_begin_steal(victim, stream, db)


## Pure. base_gain_db (always 0.0, AUD-G1) + the caller's gain. Deliberately
## EXCLUDES the AUD-R1 ladder so §3 hard-point 1「失败音绝不比成功音响」can be
## asserted headlessly without driving a clock.
func effective_level_db(cue: String, gain_db: float) -> float:
	if not CUE_TABLE.has(cue):
		return WORLD_FLOOR_DB
	return float(CUE_TABLE[cue]["base_gain_db"]) + gain_db


## Pure. "" for an unknown cue. Note save_failure and action_denied resolve to
## the SAME path on purpose — the alias is visible here, by design.
func resolve_stream_path(cue: String) -> String:
	if not CUE_TABLE.has(cue):
		return ""
	return str(CUE_TABLE[cue]["path"])


## A-05. The settings panel's「UI 音效」checkbox writes here. Deliberately does
## NOT stop voices already in flight: a 114 ms cue that was already sounding
## when the box was unticked is finished, not chopped — a hard stop mid-decay is
## a DC step, i.e. the click UI_STEAL_FADE_SEC exists to avoid.
func set_ui_sound_enabled(on: bool) -> void:
	ui_sound_enabled = on


## Spec §5.5. QA turns the ladder off to make single-shot levels deterministic.
func set_retrigger_ladder_enabled(on: bool) -> void:
	_ladder_enabled = on
	_last_play_ms.clear()
	_ladder_step.clear()


func retrigger_ladder_enabled() -> bool:
	return _ladder_enabled


## AUD-R1. {"play": bool, "db": float}. Only advances state when it says play.
func _ladder_tick(cue: String) -> Dictionary:
	if not _ladder_enabled:
		return {"play": true, "db": 0.0}
	var now := Time.get_ticks_msec()
	if _last_play_ms.has(cue):
		var dt: int = now - int(_last_play_ms[cue])
		if dt < UI_RETRIGGER_SUPPRESS_MS:
			# Suppressed, and the window stays anchored to the last cue that
			# actually SOUNDED — otherwise held-key repeat would ratchet the
			# window forward forever and never let a second one through.
			return {"play": false, "db": 0.0}
		if dt > UI_REPEAT_RESET_MS:
			_ladder_step[cue] = 0
		else:
			_ladder_step[cue] = int(_ladder_step.get(cue, 0)) + 1
	else:
		_ladder_step[cue] = 0
	_last_play_ms[cue] = now
	# Never zero: 立场 3「禁用不等于沉默」— the repeat retreats to -9 dB and stops.
	var step := int(_ladder_step.get(cue, 0))
	return {"play": true, "db": maxf(UI_REPEAT_STEP_DB * float(step), UI_REPEAT_FLOOR_DB)}


func _free_voice() -> int:
	for i in range(_ui_players.size()):
		var p: AudioStreamPlayer = _ui_players[i]
		if p == null or not is_instance_valid(p):
			continue
		if _ui_fade_left[i] > 0.0:
			continue
		if not p.playing:
			return i
	return -1


func _oldest_voice() -> int:
	var best := -1
	var best_ms := 0
	for i in range(_ui_players.size()):
		if _ui_fade_left[i] > 0.0:
			continue   # already dying and already spoken for
		if best < 0 or int(_ui_start_ms[i]) < best_ms:
			best = i
			best_ms = int(_ui_start_ms[i])
	return best


func _start_voice(i: int, stream: AudioStream, db: float) -> void:
	var p: AudioStreamPlayer = _ui_players[i]
	if p == null or not is_instance_valid(p):
		return
	p.stream = stream
	p.volume_db = db
	p.play()
	_ui_start_ms[i] = Time.get_ticks_msec()
	_ui_fade_left[i] = 0.0
	_ui_pending[i] = {}


func _begin_steal(i: int, stream: AudioStream, db: float) -> void:
	var p: AudioStreamPlayer = _ui_players[i]
	if p == null or not is_instance_valid(p):
		return
	_ui_fade_from_db[i] = p.volume_db
	_ui_fade_left[i] = UI_STEAL_FADE_SEC
	_ui_pending[i] = {"stream": stream, "db": db}


# =============================================================================
# World mode (spec §1.4). 120 ms ramp, wall clock, no Tween.
# =============================================================================
func set_world_mode(mode: String) -> void:
	# AUD-F8. A pause menu closing mid-load-fade would otherwise yank World
	# straight back to 0 dB and blow the whole fade in one frame.
	if _fading:
		push_warning("AudioDirector: set_world_mode(%s) ignored during load fade (AUD-F8)" % mode)
		return
	if mode != MODE_FLOWING and mode != MODE_FOCUS and mode != MODE_PAUSED:
		push_warning("AudioDirector: unknown world mode '%s'" % mode)
		return
	if mode == _mode:
		return
	_mode = mode
	_db_from = _current_world_db()
	_hz_from = _current_world_hz()
	_db_to = world_target_db(mode)
	_hz_to = world_target_hz(mode)
	_ramp_left = WORLD_MODE_RAMP_SEC


func world_mode() -> String:
	return _mode


static func world_target_db(mode: String) -> float:
	match mode:
		MODE_FOCUS:
			return WORLD_DB_FOCUS
		MODE_PAUSED:
			return WORLD_DB_PAUSED
		_:
			return WORLD_DB_FLOWING


static func world_target_hz(mode: String) -> float:
	match mode:
		MODE_FOCUS:
			return WORLD_LPF_FOCUS_HZ
		MODE_PAUSED:
			return WORLD_LPF_PAUSED_HZ
		_:
			return WORLD_LPF_FLOWING_HZ


# =============================================================================
# Load fade (spec §2.3). Driven ENTIRELY from the screen — see fade_sink().
# =============================================================================
## AUD-F6: the floor must be reached on THIS frame. Waiting for the first
## set_load_fade() would render one full-level audio buffer at t=0 — a bang, and
## a bright one, which is the loudest thing on the red list.
func begin_load_fade() -> void:
	_fading = true
	fade_log.append({"phase": "begin", "alpha": 0.0})
	# Lock FLOWING while everything is inaudible. Switching the preset here is
	# free precisely because World is at -60 dB; doing it later would be a
	# audible「揭盖」at the end of the fade.
	_mode = MODE_FLOWING
	_ramp_left = 0.0
	_db_from = WORLD_DB_FLOWING
	_db_to = WORLD_DB_FLOWING
	_hz_from = WORLD_LPF_FLOWING_HZ
	_hz_to = WORLD_LPF_FLOWING_HZ
	_set_world_lpf(WORLD_LPF_FLOWING_HZ)
	_set_world_db(WORLD_FLOOR_DB)
	_set_bus_mute(BUS_SFX_WORLD, true)


## AUD-F1: amplitude-linear, not dB-linear. dB-linear would put a=0.5 at -30 dB
## and the whole fade would read as「前 80% 无声、最后 20% 突然出现」. `a` is the
## screen's world_fade_alpha() — the SAME float the veil's alpha was computed
## from, in the SAME frame (AUD-F3/F4).
func set_load_fade(a: float) -> void:
	if not _fading:
		return
	fade_log.append({"phase": "tick", "alpha": a})
	_set_world_db(linear_to_db(maxf(a, FADE_MIN_ALPHA)))


## AUD-F7: SNAP to 0.0 dB. The screen skips its last _set_alpha (the veil is
## already hidden), so the final alpha we ever see is ~0.97 = -0.26 dB residual.
## The snap is under 0.3 dB and inaudible; leaving it is a world that never
## quite comes back.
func end_load_fade() -> void:
	fade_log.append({"phase": "end", "alpha": 1.0})
	_fading = false
	_mode = MODE_FLOWING
	_ramp_left = 0.0
	_db_from = WORLD_DB_FLOWING
	_db_to = WORLD_DB_FLOWING
	_hz_from = WORLD_LPF_FLOWING_HZ
	_hz_to = WORLD_LPF_FLOWING_HZ
	_set_world_db(WORLD_DB_FLOWING)
	_set_world_lpf(WORLD_LPF_FLOWING_HZ)
	_set_bus_mute(BUS_SFX_WORLD, false)


func is_load_fading() -> bool:
	return _fading


# =============================================================================
# Frame update — WALL CLOCK ONLY
# =============================================================================
func _process(_scaled_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var real_delta := 0.0
	if _last_ms > 0:
		real_delta = float(now - _last_ms) / 1000.0
	_last_ms = now
	if real_delta <= 0.0:
		return
	_tick_world_ramp(real_delta)
	_tick_steal_fades(real_delta)


func _tick_world_ramp(real_delta: float) -> void:
	if _ramp_left <= 0.0:
		return
	_ramp_left = maxf(_ramp_left - real_delta, 0.0)
	var t := 1.0 - (_ramp_left / WORLD_MODE_RAMP_SEC)
	t = clampf(t, 0.0, 1.0)
	_set_world_db(lerpf(_db_from, _db_to, t))
	# Cutoff is swept GEOMETRICALLY. A linear 20500 -> 700 sweep spends most of
	# its 120 ms in the region above hearing and then drops a couple of octaves
	# in the last few frames — audibly a lurch, not a door closing.
	_set_world_lpf(_hz_from * pow(_hz_to / maxf(_hz_from, 1.0), t))


func _tick_steal_fades(real_delta: float) -> void:
	for i in range(_ui_players.size()):
		if _ui_fade_left[i] <= 0.0:
			continue
		_ui_fade_left[i] = maxf(float(_ui_fade_left[i]) - real_delta, 0.0)
		var p: AudioStreamPlayer = _ui_players[i]
		if p == null or not is_instance_valid(p):
			_ui_fade_left[i] = 0.0
			continue
		var t := 1.0 - (float(_ui_fade_left[i]) / UI_STEAL_FADE_SEC)
		p.volume_db = lerpf(float(_ui_fade_from_db[i]), WORLD_FLOOR_DB, clampf(t, 0.0, 1.0))
		if _ui_fade_left[i] > 0.0:
			continue
		p.stop()
		var pending: Dictionary = _ui_pending[i]
		_ui_pending[i] = {}
		if pending.is_empty():
			continue
		_start_voice(i, pending["stream"], float(pending["db"]))


# =============================================================================
# AudioServer helpers — every one of them survives a missing bus layout
# =============================================================================
func _current_world_db() -> float:
	var idx := AudioServer.get_bus_index(BUS_WORLD)
	if idx < 0:
		return _db_to
	return AudioServer.get_bus_volume_db(idx)


func _current_world_hz() -> float:
	var lpf := _world_lpf()
	if lpf == null:
		return _hz_to
	return lpf.cutoff_hz


func _world_lpf() -> AudioEffectLowPassFilter:
	var idx := AudioServer.get_bus_index(BUS_WORLD)
	if idx < 0:
		return null
	if AudioServer.get_bus_effect_count(idx) < 1:
		return null
	return AudioServer.get_bus_effect(idx, 0) as AudioEffectLowPassFilter


func _set_world_db(db: float) -> void:
	var idx := AudioServer.get_bus_index(BUS_WORLD)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, db)


## ADR-005 D-2: the cutoff moves, `enabled` never does. Toggling the effect on
## and off produces a click; sliding the cutoff to 20500 is a clean bypass.
func _set_world_lpf(hz: float) -> void:
	var lpf := _world_lpf()
	if lpf == null:
		return
	lpf.cutoff_hz = clampf(hz, 1.0, WORLD_LPF_FLOWING_HZ)


func _set_bus_mute(bus: String, muted: bool) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, muted)
