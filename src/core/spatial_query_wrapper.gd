class_name SpatialQueryWrapper
extends RefCounted

# ASHEN STEP — Sprint 0 vertical slice (Phase 5).
# L2 spatial query wrapper. Centralizes LOS raycasts so gameplay (L4) never
# calls PhysicsDirectSpaceState3D directly (architecture §2 layer contract,
# E01-S3). Only the occlusion layer (walls / pillars / doors) blocks sight.
#
# All rays go through one masked query so the occlusion mask is consistent and
# the call is cheap to throttle/batch from vision-cone ticks (ADR-002 G-03).

const DEFAULT_OCCLUSION_MASK := 1  # bit 0 reserved for occluders; tune per project


func has_line_of_sight(from: Vector3, to: Vector3, occlusion_mask: int) -> bool:
	var space_state := _get_space_state()
	# No world yet (editor/headless before a scene is active): treat as visible
	# so callers don't falsely report "blocked" before the tree is ready.
	if space_state == null:
		return true

	var query := PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = to
	query.collision_mask = occlusion_mask

	var hit := space_state.intersect_ray(query)
	# No collision between from and to => the line of sight is clear.
	return hit.is_empty()


func _get_space_state() -> PhysicsDirectSpaceState3D:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var world_3d := tree.root.world_3d
	if world_3d == null:
		return null
	return world_3d.direct_space_state
