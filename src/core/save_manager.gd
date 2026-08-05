# src/core/save_manager.gd
# ASHEN STEP — Sprint 2, Batch A. E11 SaveManager **data layer** (L2 service).
#
# Stories: SAV-S1 (slot schema + version-first) · SAV-S2 (write_slot/read_slot,
#          async, checkpoint cooldown, 3 bus events) · SAV-S3 (restore_checkpoint,
#          D9 seam) · SAV-S4 (field-agnostic prefs delegation + a11y.cfg one-time
#          migration) · SAV-S6 (version reject + corruption, never swallow).
#
# Authority: design/gdd/systems/save-system.md §2/§3/§4/§6 (constants and field
#            order are frozen there); production/sprints/sprint2-stories.md §2
#            Batch A; docs/architecture/architecture.md §2 (L2 service layer).
#
# ── Why there is NO `class_name` here ────────────────────────────────────────
# This script is registered as the autoload singleton `SaveManager` in
# project.godot, because SAV-S3 locks the D9 injection to the literal one-liner
#     set_checkpoint_sink(SaveManager.restore_checkpoint)
# in src/game/patrol_ai.gd. Godot 4 rejects a global class whose name shadows an
# autoload ("Class 'X' hides an autoload singleton"), so the global class name is
# deliberately omitted. Tests reach the type via
#     const SaveManager = preload("res://src/core/save_manager.gd")
# exactly like test_patrol_ai.gd does for GuardBrain.
#
# ── Layering discipline (architecture.md §2, one-way dependencies) ───────────
# L2 does NOT reach into L3/L4 nodes. restore_checkpoint() publishes the restored
# world snapshot on `restored_state` and broadcasts `checkpoint_restored`; ⑥/⑧
# consume that. There is no back-reference from this file to GuardBrain/HUD.
#
# ── Async discipline (GDD §6) ────────────────────────────────────────────────
# write_slot() validates + snapshots on the calling frame and returns IMMEDIATELY;
# the FileAccess round-trip and the `save_completed` broadcast run from a deferred
# call, so no gameplay tick ever pays for disk IO. Tests `await` the bus signal.
#
# Headless-safe: no rendering, no scene-tree requirement (the bus can be injected
# and the message queue flushes deferred calls whether or not this node is in the
# tree). Test isolation goes through configure_paths().

extends Node

const EventBus = preload("res://src/core/event_bus.gd")

# ── GDD-locked constants (save-system.md §3 — values are frozen) ─────────────
const SAVE_VERSION: int = 2
const CHECKPOINT_SLOT_ID: int = -1
const MAX_MANUAL_SLOTS: int = 3
const SAVE_DIR: String = "user://saves/"
const PREFS_PATH: String = "user://prefs.json"

# Sprint 0 slice legacy file (a11y_settings.gd:11). SAV-S4: the ONLY real
# migration path in this system. Slot files are reject-not-migrate (SAV-S6).
const LEGACY_A11Y_PATH: String = "user://a11y.cfg"

# GDD §6: checkpoint writes are rate-limited so standing in a checkpoint volume
# cannot write every frame. ">= 0.5s" — 0.5s is the locked floor.
const CHECKPOINT_WRITE_COOLDOWN: float = 0.5

# GDD §6 / @ci:save-size-budget: single slot JSON <= 32 KB. WARN-ONLY — an
# oversized slot is still written; it is a budget signal, not a failure.
const SLOT_SIZE_BUDGET_BYTES: int = 32768

# FLAG-A mitigation ①: this array IS the wire order. `version` is index 0 and
# must stay index 0 — every read path reads it BEFORE parsing anything else, and
# @ci:save-schema-has-version reverse-asserts the position statically.
# Field set is save-system.md §3 verbatim (11 fields).
const SLOT_FIELD_ORDER := [
	"version",
	"slot_id",
	"is_checkpoint",
	"timestamp",
	"checkpoint_id",
	"player_pose",
	"suspicion",
	"guard_states",
	"interactable_charges",
	"light_states",
	"a11y_prefs",
]

# Corruption reasons published on `corrupt_slots` (SAV-S6). Strings, not an enum,
# so ⑧ can surface them verbatim without an L2->L5 vocabulary dependency.
const REASON_PARSE_FAILED := "parse_failed"
const REASON_NOT_A_DICT := "not_a_dictionary"
const REASON_MISSING_VERSION := "missing_version"
const REASON_VERSION_MISMATCH := "version_mismatch"
const REASON_MISSING_FILE := "missing_file"
const REASON_UNREADABLE := "unreadable"
const REASON_BAD_SLOT_ID := "bad_slot_id"

# ── Collaborators ────────────────────────────────────────────────────────────
var _bus: EventBus = null

# ── Configurable paths (test isolation — sprint2-stories.md §4「SaveManager
#    测试隔离」: persistence tests must NEVER touch the real user:// files) ────
var _save_dir: String = SAVE_DIR
var _prefs_path: String = PREFS_PATH
var _legacy_a11y_path: String = LEGACY_A11Y_PATH

# ── State ────────────────────────────────────────────────────────────────────
# Rolling in-memory mirror of the checkpoint slot, so restore_checkpoint() does
# not have to hit the disk on the soft-fail path (E08-S4 is a gameplay tick).
var _checkpoint_cache: Dictionary = {}
var _last_checkpoint_write_ms: int = -1_000_000

# Observability for tests / ⑧. Never used for control flow.
var checkpoint_write_count: int = 0
var last_slot_size_bytes: int = 0
var corrupt_slots: Dictionary = {}          # slot_id:int -> reason:String

# SAV-S3: the world snapshot produced by the last restore_checkpoint(), already
# normalised (suspicion zeroed, guards forced to RETURN). ⑥ reads this when it
# receives `checkpoint_restored`.
var restored_state: Dictionary = {}

# SAV-S4 migration bookkeeping. The migration runs LAZILY on the first
# load_prefs() call, never from _ready(), so simply having the autoload alive in
# a headless test run cannot eat a developer's real user://a11y.cfg.
var _migration_checked: bool = false
var legacy_a11y_migrated: bool = false

var _prefs_cache: Dictionary = {}
var _prefs_loaded: bool = false


func _ready() -> void:
	# Group registration only — no disk IO on boot (see the migration note above).
	add_to_group("save_manager")


# =============================================================================
# Wiring
# =============================================================================
func set_event_bus(bus: EventBus) -> void:
	_bus = bus


## Test-isolation hook. Production code never calls this; the defaults are the
## GDD-locked user:// paths. `legacy_a11y_path` defaults to "" = keep current.
func configure_paths(save_dir: String, prefs_path: String, legacy_a11y_path := "") -> void:
	_save_dir = save_dir if save_dir.ends_with("/") else save_dir + "/"
	_prefs_path = prefs_path
	if legacy_a11y_path != "":
		_legacy_a11y_path = legacy_a11y_path
	# Paths changed => every cached view of the old location is stale.
	_prefs_cache = {}
	_prefs_loaded = false
	_migration_checked = false
	legacy_a11y_migrated = false
	_checkpoint_cache = {}
	corrupt_slots = {}


func get_save_dir() -> String:
	return _save_dir


func get_prefs_path() -> String:
	return _prefs_path


# =============================================================================
# SAV-S1 — slot schema. Pure/static so CI can scan it without a running game.
# =============================================================================
## Build an in-memory (TYPED) slot. `version` is inserted FIRST and Dictionary
## preserves insertion order — but that alone is NOT enough to put `version`
## first on disk: the encoder must also be told not to sort (see slot_to_json).
## Unknown keys in `data` are DROPPED —
## only the 11 GDD fields ever reach the wire ("世界差异态" discipline, §3).
static func make_slot(slot_id: int, is_checkpoint: bool, data: Dictionary) -> Dictionary:
	var slot: Dictionary = {}
	slot["version"] = SAVE_VERSION
	slot["slot_id"] = slot_id
	slot["is_checkpoint"] = is_checkpoint
	slot["timestamp"] = float(data.get("timestamp", Time.get_unix_time_from_system()))
	slot["checkpoint_id"] = str(data.get("checkpoint_id", ""))
	slot["player_pose"] = _norm_pose(data.get("player_pose", {}))
	slot["suspicion"] = _norm_int_float(data.get("suspicion", {}))
	slot["guard_states"] = _norm_int_int(data.get("guard_states", {}))
	slot["interactable_charges"] = _norm_int_int(data.get("interactable_charges", {}))
	slot["light_states"] = _norm_int_bool(data.get("light_states", {}))
	slot["a11y_prefs"] = _as_dict(data.get("a11y_prefs", {})).duplicate(true)
	return slot


## TYPED slot -> JSON-safe slot (Vector3 -> [x,y,z]; int keys -> string keys).
## Walks SLOT_FIELD_ORDER, so the version-first invariant survives encoding.
static func encode_slot(slot: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for field in SLOT_FIELD_ORDER:
		match field:
			"player_pose":
				out[field] = _encode_pose(slot.get(field, {}))
			"suspicion", "guard_states", "interactable_charges", "light_states":
				out[field] = _keys_to_string(slot.get(field, {}))
			_:
				out[field] = slot.get(field)
	return out


## JSON-safe slot -> TYPED slot. Inverse of encode_slot(); roundtrip-stable.
static func decode_slot(raw: Dictionary) -> Dictionary:
	var slot: Dictionary = {}
	slot["version"] = int(raw.get("version", -1))
	slot["slot_id"] = int(raw.get("slot_id", CHECKPOINT_SLOT_ID))
	slot["is_checkpoint"] = bool(raw.get("is_checkpoint", false))
	slot["timestamp"] = float(raw.get("timestamp", 0.0))
	slot["checkpoint_id"] = str(raw.get("checkpoint_id", ""))
	slot["player_pose"] = _decode_pose(raw.get("player_pose", {}))
	# The _norm_* helpers already coerce keys with int(), which parses the string
	# keys JSON produces ("12" -> 12), so no separate key pass is needed here.
	slot["suspicion"] = _norm_int_float(raw.get("suspicion", {}))
	slot["guard_states"] = _norm_int_int(raw.get("guard_states", {}))
	slot["interactable_charges"] = _norm_int_int(raw.get("interactable_charges", {}))
	slot["light_states"] = _norm_int_bool(raw.get("light_states", {}))
	slot["a11y_prefs"] = _as_dict(raw.get("a11y_prefs", {})).duplicate(true)
	return slot


## ★ `sort_keys` MUST stay false. Godot's JSON.stringify() defaults it to TRUE,
## which re-orders the object ALPHABETICALLY on the wire ("a11y_prefs" first) and
## silently breaks the version-first invariant even though the Dictionary itself
## is correctly ordered. Passing false makes the encoder walk insertion order,
## so the bytes begin with {"version":2. Do not drop these two arguments.
static func slot_to_json(slot: Dictionary) -> String:
	return JSON.stringify(encode_slot(slot), "", false)


static func is_valid_slot_id(slot_id: int) -> bool:
	return slot_id == CHECKPOINT_SLOT_ID or (slot_id >= 0 and slot_id < MAX_MANUAL_SLOTS)


# =============================================================================
# SAV-S2 — write_slot / read_slot
# =============================================================================
## Async by contract (GDD §6): returns on the calling frame; the disk write and
## the `save_completed(slot_id, success)` broadcast happen from a deferred call.
func write_slot(slot_id: int, data: Dictionary) -> void:
	if not is_valid_slot_id(slot_id):
		push_error("SaveManager.write_slot: invalid slot id %d (expected %d or 0..%d)"
			% [slot_id, CHECKPOINT_SLOT_ID, MAX_MANUAL_SLOTS - 1])
		_mark_corrupt(slot_id, REASON_BAD_SLOT_ID)
		_emit_deferred(&"save_completed", [slot_id, false])
		return

	if slot_id == CHECKPOINT_SLOT_ID and _checkpoint_write_throttled():
		# GDD §6 rate limit. Reported as success=false rather than swallowed —
		# ⑧ ignores slot -1 toasts (§5: checkpoints are diegetic, never popups),
		# so this is an observable no-op, not a user-facing error.
		_emit_deferred(&"save_completed", [slot_id, false])
		return

	var slot := make_slot(slot_id, slot_id == CHECKPOINT_SLOT_ID, data)

	if slot_id == CHECKPOINT_SLOT_ID:
		_checkpoint_cache = slot.duplicate(true)
		_last_checkpoint_write_ms = Time.get_ticks_msec()
		checkpoint_write_count += 1

	# Everything above is O(fields) on the caller's frame; the IO is deferred.
	call_deferred("_flush_write", slot_id, slot)


## Synchronous return of the TYPED slot ({} on any failure) + deferred
## `load_completed(slot_id, success)`. SAV-S6: rejects never crash, never
## swallow (push_error + corrupt_slots), and never write anything back.
func read_slot(slot_id: int) -> Dictionary:
	if not is_valid_slot_id(slot_id):
		push_error("SaveManager.read_slot: invalid slot id %d" % slot_id)
		_mark_corrupt(slot_id, REASON_BAD_SLOT_ID)
		_emit_deferred(&"load_completed", [slot_id, false])
		return {}

	var path := slot_path(slot_id)
	if not FileAccess.file_exists(path):
		# Not corruption — an empty slot is a legal state. Still reported.
		_emit_deferred(&"load_completed", [slot_id, false])
		return {}

	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return _reject(slot_id, REASON_UNREADABLE, "empty or unreadable file: %s" % path)

	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		return _reject(slot_id, REASON_PARSE_FAILED, "JSON parse failed: %s" % path)
	if not (parsed is Dictionary):
		return _reject(slot_id, REASON_NOT_A_DICT, "top level is %s, not a Dictionary: %s"
			% [type_string(typeof(parsed)), path])

	var raw: Dictionary = parsed

	# ── FLAG-A mitigation ①: VERSION FIRST. Nothing below this block touches any
	#    other field. Do NOT hoist field reads above this gate.
	if not raw.has("version"):
		return _reject(slot_id, REASON_MISSING_VERSION, "no `version` field: %s" % path)
	var keys: Array = raw.keys()
	if keys.size() > 0 and str(keys[0]) != "version":
		# Position drift is a WARN (matches @ci:save-schema-has-version, WARN-ONLY);
		# the value gate below is what actually decides accept/reject.
		push_warning("SaveManager.read_slot: `version` is not the first field in %s (found `%s`)"
			% [path, str(keys[0])])
	var file_version := int(raw["version"])
	if file_version != SAVE_VERSION:
		# GDD §2: v1 is an incompatible state — reject and rebuild, DO NOT migrate.
		return _reject(slot_id, REASON_VERSION_MISMATCH,
			"version %d != SAVE_VERSION %d: %s" % [file_version, SAVE_VERSION, path])
	# ── Version accepted; only now is the rest of the payload parsed. ──────────

	var slot := decode_slot(raw)
	corrupt_slots.erase(slot_id)
	if slot_id == CHECKPOINT_SLOT_ID:
		_checkpoint_cache = slot.duplicate(true)
	_emit_deferred(&"load_completed", [slot_id, true])
	return slot


func slot_path(slot_id: int) -> String:
	return "%sslot_%d.json" % [_save_dir, slot_id]


## O-3 (Sprint 3 · S3-B ruling): staging path for the atomic slot write.
## DERIVED from slot_path() so the two can never drift onto different
## directories, and SUFFIXED rather than prefixed so a leftover staging file
## sorts next to the slot it belongs to during triage.
func slot_tmp_path(slot_id: int) -> String:
	return slot_path(slot_id) + ".tmp"


func has_checkpoint() -> bool:
	return not _checkpoint_cache.is_empty() or FileAccess.file_exists(slot_path(CHECKPOINT_SLOT_ID))


func is_slot_corrupt(slot_id: int) -> bool:
	return corrupt_slots.has(slot_id)


func get_corrupt_reason(slot_id: int) -> String:
	return str(corrupt_slots.get(slot_id, ""))


func _checkpoint_write_throttled() -> bool:
	# Real (wall-clock) time — Engine.time_scale must never gate persistence
	# (ADR-002/ADR-003 + T-02, same rule as patrol_ai.gd's timers).
	var now := Time.get_ticks_msec()
	var elapsed_ms := now - _last_checkpoint_write_ms
	return elapsed_ms < int(CHECKPOINT_WRITE_COOLDOWN * 1000.0)


func _flush_write(slot_id: int, slot: Dictionary) -> void:
	var ok := true
	var err := DirAccess.make_dir_recursive_absolute(_save_dir)
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_error("SaveManager: cannot create save dir %s (err=%d)" % [_save_dir, err])
		ok = false

	if ok:
		var json := slot_to_json(slot)
		last_slot_size_bytes = json.to_utf8_buffer().size()
		if last_slot_size_bytes > SLOT_SIZE_BUDGET_BYTES:
			# @ci:save-size-budget — WARN-ONLY, the write still goes through.
			push_warning("SaveManager: slot %d is %d bytes (> %d budget)"
				% [slot_id, last_slot_size_bytes, SLOT_SIZE_BUDGET_BYTES])
		ok = _write_atomic(slot_id, json)

	_emit_now(&"save_completed", [slot_id, ok])


## ── O-3 · ATOMIC SLOT WRITE (staging file + rename) ─────────────────────────
##
## THE FAILURE THIS CLOSES. The Sprint 2 implementation opened the REAL slot
## path with FileAccess.WRITE, and WRITE truncates the destination to zero
## length before the first byte lands. A crash, a power cut or a full disk
## between that truncation and the final store_string() left a slot that
## existed, was readable, and was half a JSON document. read_slot() would then
## reject it as `parse_failed` — and the player's previous, perfectly good save
## was already gone. SAV-S6 promises「不覆盖写回」and UX spec EC-7 promises the
## row still shows its ORIGINAL content after a failed write. Neither promise
## could be kept while the destination was being truncated in place.
##
## THE GUARD. Every byte goes to `<slot>.json.tmp` first. The destination is
## touched only by the rename, which cannot produce a partial file: either the
## rename lands and the slot is the COMPLETE new document, or it does not and
## the slot is the COMPLETE old one. There is no third state.
##
## ★ HONEST LIMIT — do not oversell this in review. rename() is atomic on
## POSIX. On Windows, Godot's DirAccess::rename() removes an existing
## destination before renaming, so a narrow window exists in which the slot is
## ABSENT. That is a strictly weaker guarantee, but the failure it leaves is
## "slot missing", which read_slot() already reports as an empty slot — a legal,
## honest state. The old behaviour left "slot corrupt", which is silent data
## loss wearing the mask of a valid file. Closing the Windows window completely
## needs ReplaceFileW, which GDScript cannot reach; if that ever matters, it is
## a GDExtension task, not a tweak here.
##
## The staging file is removed on EVERY failure path, so a botched write cannot
## leave litter that later triage mistakes for a real slot.
func _write_atomic(slot_id: int, json: String) -> bool:
	var final_path := slot_path(slot_id)
	var tmp_path := slot_tmp_path(slot_id)

	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_error("SaveManager: cannot open staging file %s for writing (err=%d)"
			% [tmp_path, FileAccess.get_open_error()])
		return false
	f.store_string(json)
	# flush() before close() is deliberate belt-and-braces: close() flushes too,
	# but doing it explicitly means the bytes are pushed at a point where
	# get_error() is still readable, rather than inside a destructor whose
	# result nobody can see.
	f.flush()
	var write_err := f.get_error()
	f.close()
	if write_err != OK:
		push_error("SaveManager: staging write failed for slot %d (err=%d) — slot left untouched"
			% [slot_id, write_err])
		_discard_staging(tmp_path)
		return false

	# Reverse check BEFORE the swap. A staging file whose length is not the
	# length we just serialised means the bytes did not all land (short write on
	# a full disk is the common case), and promoting it over a good slot would
	# be the exact data loss this function exists to prevent.
	var staged := FileAccess.open(tmp_path, FileAccess.READ)
	if staged == null:
		push_error("SaveManager: staging file %s unreadable before rename (err=%d) — slot left untouched"
			% [tmp_path, FileAccess.get_open_error()])
		_discard_staging(tmp_path)
		return false
	var staged_len := int(staged.get_length())
	staged.close()
	var expected_len := json.to_utf8_buffer().size()
	if staged_len != expected_len:
		push_error("SaveManager: staging file %s is %d bytes, expected %d — slot left untouched"
			% [tmp_path, staged_len, expected_len])
		_discard_staging(tmp_path)
		return false

	var err := DirAccess.rename_absolute(tmp_path, final_path)
	if err != OK:
		push_error("SaveManager: cannot promote %s to %s (err=%d) — slot left untouched"
			% [tmp_path, final_path, err])
		_discard_staging(tmp_path)
		return false
	return true


func _discard_staging(tmp_path: String) -> void:
	if FileAccess.file_exists(tmp_path):
		DirAccess.remove_absolute(tmp_path)


func _reject(slot_id: int, reason: String, detail: String) -> Dictionary:
	# SAV-S6: loud, marked, non-destructive. No overwrite-back, no crash.
	push_error("SaveManager: slot %d rejected (%s) — %s" % [slot_id, reason, detail])
	_mark_corrupt(slot_id, reason)
	_emit_deferred(&"load_completed", [slot_id, false])
	return {}


func _mark_corrupt(slot_id: int, reason: String) -> void:
	corrupt_slots[slot_id] = reason


# =============================================================================
# SAV-S3 — restore_checkpoint (D9 seam target)
# =============================================================================
## ★ SIGNATURE LOCKED BY FLAG-A(a): ZERO ARGUMENTS.
## src/game/patrol_ai.gd:371 calls `_checkpoint_sink.call()` with zero args, and
## BOTH sides are pinned by tests (test_save_manager.gd::
## test_checkpoint_sink_arity_contract and test_patrol_ai.gd:413's reverse
## assertion). Adding a parameter here is a one-sided drift and is forbidden
## without re-opening FLAG-A through the lead (sprint2-stories.md §2 SAV-S3).
func restore_checkpoint() -> void:
	var slot := _checkpoint_cache
	if slot.is_empty():
		if not FileAccess.file_exists(slot_path(CHECKPOINT_SLOT_ID)):
			# Legal state (no checkpoint written yet) — a safe no-op, exactly like
			# the un-injected Callable() default on the GuardBrain side.
			push_warning("SaveManager.restore_checkpoint: no checkpoint available — no-op.")
			return
		slot = read_slot(CHECKPOINT_SLOT_ID)
		if slot.is_empty():
			# read_slot already reported + emitted load_completed(-1, false).
			return

	restored_state = _normalise_restored(slot)
	_emit_deferred(&"checkpoint_restored", [str(slot.get("checkpoint_id", ""))])


## GDD §2/SAV-S3: restoring a checkpoint zeroes suspicion and forces every known
## guard back to RETURN, while world diff state (pose / lights / charges) comes
## back verbatim. L2 only PUBLISHES this; ⑥ applies it on `checkpoint_restored`.
static func _normalise_restored(slot: Dictionary) -> Dictionary:
	var suspicion: Dictionary = {}
	for gid in _as_dict(slot.get("suspicion", {})).keys():
		suspicion[int(gid)] = 0.0

	var guard_states: Dictionary = {}
	for gid in _as_dict(slot.get("guard_states", {})).keys():
		guard_states[int(gid)] = EventBus.GuardState.RETURN
	# A guard that only appears in the suspicion map still has to be reset.
	for gid in suspicion.keys():
		if not guard_states.has(gid):
			guard_states[gid] = EventBus.GuardState.RETURN

	return {
		"checkpoint_id": str(slot.get("checkpoint_id", "")),
		"player_pose": _norm_pose(slot.get("player_pose", {})),
		"suspicion": suspicion,
		"guard_states": guard_states,
		"interactable_charges": _norm_int_int(slot.get("interactable_charges", {})),
		"light_states": _norm_int_bool(slot.get("light_states", {})),
	}


# =============================================================================
# SAV-S4 — preference delegation (FIELD-AGNOSTIC, FLAG-J)
# =============================================================================
# There is deliberately NO a11y field name anywhere below. A section is an
# opaque String key and its payload an opaque Dictionary, so E09-S7 can grow the
# a11y model in Batch C without touching this file (dependency stays one-way:
# SAV-S4 -> E09-S7).
func save_prefs(section: String, data: Dictionary) -> void:
	_ensure_prefs_loaded()
	_prefs_cache[section] = data.duplicate(true)
	_write_prefs()


func load_prefs(section: String) -> Dictionary:
	_ensure_prefs_loaded()
	return _as_dict(_prefs_cache.get(section, {})).duplicate(true)


func has_prefs_section(section: String) -> bool:
	_ensure_prefs_loaded()
	return _prefs_cache.has(section)


func _ensure_prefs_loaded() -> void:
	if _prefs_loaded:
		return
	_prefs_loaded = true
	_prefs_cache = _read_prefs_file()
	_migrate_legacy_config_once()


func _read_prefs_file() -> Dictionary:
	if not FileAccess.file_exists(_prefs_path):
		return {}
	var text := FileAccess.get_file_as_string(_prefs_path)
	if text == "":
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		# Loud, but recoverable: prefs are regenerable from defaults, unlike a
		# save slot, so we rebuild rather than hard-reject.
		push_error("SaveManager: %s is not valid JSON — rebuilding from defaults." % _prefs_path)
		return {}
	var raw: Dictionary = parsed
	raw.erase("version")           # bookkeeping key, not a section
	return raw


func _write_prefs() -> void:
	var out: Dictionary = {}
	out["version"] = SAVE_VERSION   # version-first here too (schema discipline)
	for section in _prefs_cache.keys():
		out[section] = _prefs_cache[section]
	var f := FileAccess.open(_prefs_path, FileAccess.WRITE)
	if f == null:
		push_error("SaveManager: cannot open %s for writing (err=%d)"
			% [_prefs_path, FileAccess.get_open_error()])
		return
	# sort_keys=false for the same reason as slot_to_json(): the default (true)
	# would sort sections alphabetically and push `version` past "a11y"/"audio".
	f.store_string(JSON.stringify(out, "", false))
	f.close()


## The ONE real migration in this system (GDD §2 / SAV-S4 Note): Sprint 0 wrote
## a11y through ConfigFile at user://a11y.cfg. Sections and keys are read
## GENERICALLY via get_sections()/get_section_keys() — no field name is hardcoded
## — then the legacy file is deleted so this can only ever run once.
func _migrate_legacy_config_once() -> void:
	if _migration_checked:
		return
	_migration_checked = true
	if not FileAccess.file_exists(_legacy_a11y_path):
		return

	var cfg := ConfigFile.new()
	var err := cfg.load(_legacy_a11y_path)
	if err != OK:
		push_error("SaveManager: legacy config %s unreadable (err=%d) — left in place."
			% [_legacy_a11y_path, err])
		return

	for section in cfg.get_sections():
		var merged: Dictionary = _as_dict(_prefs_cache.get(section, {})).duplicate(true)
		for key in cfg.get_section_keys(section):
			# Existing prefs.json values win: the new store is the authority.
			if not merged.has(key):
				merged[key] = cfg.get_value(section, key)
		_prefs_cache[section] = merged

	_write_prefs()
	var d := DirAccess.open(_legacy_a11y_path.get_base_dir())
	if d != null:
		d.remove(_legacy_a11y_path.get_file())
	legacy_a11y_migrated = true


# =============================================================================
# Event broadcast (the 3 signals live on the L2 bus, not on this node)
# =============================================================================
func _emit_deferred(sig: StringName, args: Array) -> void:
	call_deferred("_emit_now", sig, args)


func _emit_now(sig: StringName, args: Array) -> void:
	var bus := _resolve_bus()
	if bus == null:
		return
	bus.callv("emit_signal", [sig] + args)


func _resolve_bus() -> EventBus:
	if _bus != null and is_instance_valid(_bus):
		return _bus
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var n := (loop as SceneTree).get_first_node_in_group("event_bus")
		if n is EventBus:
			_bus = n
	return _bus


# =============================================================================
# Value normalisation helpers (static; JSON has no Vector3 and no int keys)
# =============================================================================
## Variant -> Dictionary with a safe empty fallback. Used everywhere instead of
## `x as Dictionary`, so a malformed payload degrades instead of throwing.
static func _as_dict(v: Variant) -> Dictionary:
	if v is Dictionary:
		var d: Dictionary = v
		return d
	return {}


static func _norm_pose(v: Variant) -> Dictionary:
	var src := _as_dict(v)
	var pos: Variant = src.get("pos", Vector3.ZERO)
	var vec := Vector3.ZERO
	if pos is Vector3:
		vec = pos
	return {
		"pos": vec,
		"facing": float(src.get("facing", 0.0)),
		"gait": int(src.get("gait", 0)),
	}


static func _encode_pose(v: Variant) -> Dictionary:
	var p := _norm_pose(v)
	var pos: Vector3 = p["pos"]
	return {"pos": [pos.x, pos.y, pos.z], "facing": p["facing"], "gait": p["gait"]}


static func _decode_pose(v: Variant) -> Dictionary:
	var src := _as_dict(v)
	var pos := Vector3.ZERO
	var raw: Variant = src.get("pos", null)
	if raw is Vector3:
		pos = raw
	elif raw is Array:
		var a: Array = raw
		if a.size() == 3:
			pos = Vector3(float(a[0]), float(a[1]), float(a[2]))
	return {"pos": pos, "facing": float(src.get("facing", 0.0)), "gait": int(src.get("gait", 0))}


static func _keys_to_string(v: Variant) -> Dictionary:
	var src := _as_dict(v)
	var out: Dictionary = {}
	for k in src.keys():
		out[str(k)] = src[k]
	return out


static func _norm_int_float(v: Variant) -> Dictionary:
	var src := _as_dict(v)
	var out: Dictionary = {}
	for k in src.keys():
		out[int(k)] = float(src[k])
	return out


static func _norm_int_int(v: Variant) -> Dictionary:
	var src := _as_dict(v)
	var out: Dictionary = {}
	for k in src.keys():
		out[int(k)] = int(src[k])
	return out


static func _norm_int_bool(v: Variant) -> Dictionary:
	var src := _as_dict(v)
	var out: Dictionary = {}
	for k in src.keys():
		out[int(k)] = bool(src[k])
	return out
