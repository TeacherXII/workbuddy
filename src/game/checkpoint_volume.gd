class_name CheckpointVolume
extends Area3D

# ASHEN STEP — Phase 6, D1. Checkpoint trigger volume (L4, A).
#
# The GDD §2 "玩家进入关卡检查点区（或触发 #checkpoint 锚点）即静默写入最新快照"
# trigger, implemented verbatim as a diegetic ground volume. When the player
# enters, it asks the level's CheckpointProducer to write a checkpoint under this
# volume's id. The write is SPARSE by construction (a discrete volume entry, not
# a per-step or per-action event) which is exactly the §5 diegetic / never-popup
# intent, and pairs naturally with SaveManager's 0.5s write cooldown.
#
# Visual language (sprint2-asset-spec.md:420,632): a flat, COLD ground ring in
# #3E5C76 — deliberately NEVER a warm light, so a checkpoint reads as "safe marker"
# not "objective glow". Decoration is cosmetic and headless-safe.

const EventBus = preload("res://src/core/event_bus.gd")
const CheckpointProducer = preload("res://src/game/checkpoint_producer.gd")

const COLD_RING_COLOR := Color("#3E5C76")


@export var checkpoint_id: String = "cp_unnamed"

## NodePath to the player body that should trigger this volume. If empty, ANY
## body_entered triggers (the level is responsible for ensuring only the player
## overlaps). Resolved on first entry so the volume is usable before/without a
## fully wired tree.
@export var player_path: NodePath = NodePath()

## NodePath to the CheckpointProducer. If empty, resolved via group
## "checkpoint_producer" on first entry (the producer registers itself there).
@export var producer_path: NodePath = NodePath()


# Debounce: one write per visit; re-armed when the body leaves and re-enters.
var _inside: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_decorate_cold_ring()


func _on_body_entered(body: Node) -> void:
	if not _is_player(body):
		return
	if _inside:
		return
	_inside = true
	var producer := _resolve_producer()
	if producer == null:
		push_warning("CheckpointVolume '%s': no CheckpointProducer resolved — checkpoint not written." % checkpoint_id)
		return
	producer.produce(checkpoint_id)


func _on_body_exited(body: Node) -> void:
	if _is_player(body):
		_inside = false


func _is_player(body: Node) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	if player_path.is_empty():
		return true
	var p := get_node_or_null(player_path)
	return body == p


func _resolve_producer() -> CheckpointProducer:
	if not producer_path.is_empty():
		var n := get_node_or_null(producer_path)
		if n is CheckpointProducer:
			return n
	var tree := get_tree()
	if tree != null:
		var found := tree.get_first_node_in_group("checkpoint_producer")
		if found is CheckpointProducer:
			return found
	return null


# Flat cold ring on the ground. Best-effort + headless-safe: if mesh creation is
# unavailable it simply produces no decoration and the trigger still works.
func _decorate_cold_ring() -> void:
	var ring := MeshInstance3D.new()
	ring.name = "ColdRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 1.4
	torus.outer_radius = 1.8
	ring.mesh = torus
	# Lay flat on the ground plane (XZ) and sink slightly so it reads as a mark.
	ring.rotation.x = PI / 2.0
	ring.position.y = 0.02
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLD_RING_COLOR
	mat.emission_enabled = true
	mat.emission = COLD_RING_COLOR
	mat.emission_energy_multiplier = 0.25
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.55
	ring.material_override = mat
	add_child(ring)
