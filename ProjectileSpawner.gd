extends Node3D

var _projectiles: Array[Dictionary] = []
var _flashes: Array[Dictionary] = []
var _beams: Array[Dictionary] = []

var _mat_flak: StandardMaterial3D
var _mat_bio: StandardMaterial3D
var _mat_shock: StandardMaterial3D
var _mat_rocket: StandardMaterial3D

func _ready() -> void:
	add_to_group("projectile_spawner")
	_mat_flak = _make_glow_mat(Color(1.0, 0.72, 0.15))
	_mat_bio = _make_glow_mat(Color(0.18, 1.0, 0.25))
	_mat_shock = _make_glow_mat(Color(0.75, 0.25, 1.0))
	_mat_rocket = _make_glow_mat(Color(1.0, 0.25, 0.12))

func _make_glow_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	return m

func spawn_beam(from_pos: Vector3, to_pos: Vector3, col: Color) -> void:
	var dist := from_pos.distance_to(to_pos)
	if dist < 0.2:
		return
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.045
	cyl.bottom_radius = 0.045
	cyl.height = dist
	cyl.radial_segments = 6
	mi.mesh = cyl
	var mat := _make_glow_mat(col)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.9
	mi.material_override = mat
	add_child(mi)
	var mid := (from_pos + to_pos) * 0.5
	mi.global_position = mid
	var dir := (to_pos - from_pos).normalized()
	if absf(dir.dot(Vector3.UP)) < 0.99:
		mi.look_at(to_pos, Vector3.UP)
		mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	_beams.append({ "node": mi, "mat": mat, "t": 0.0, "dur": 0.18 })

func trigger_shock_combo(origin: Vector3, owner_body: Node) -> void:
	_explode(origin, 7.5, 200, 18.0, owner_body, Color(0.82, 0.28, 1.0), false)

func spawn(kind: String, pos: Vector3, vel: Vector3, dmg: int, bounces: int, owner_body: Node) -> void:
	var root: Node3D
	var mesh_inst := MeshInstance3D.new()

	match kind:
		"shock_core":
			var area := Area3D.new()
			area.add_to_group("shock_core")
			var col := CollisionShape3D.new()
			var shape := SphereShape3D.new()
			shape.radius = 0.72
			col.shape = shape
			area.add_child(col)
			var sph := SphereMesh.new()
			sph.radius = 0.30
			sph.height = 0.60
			sph.radial_segments = 10
			sph.rings = 6
			mesh_inst.mesh = sph
			mesh_inst.material_override = _mat_shock
			area.add_child(mesh_inst)
			root = area
		"bio_glob":
			root = Node3D.new()
			var sph := SphereMesh.new()
			var r := clampf(0.14 + dmg * 0.0025, 0.16, 0.42)
			sph.radius = r
			sph.height = r * 2.0
			sph.radial_segments = 8
			sph.rings = 5
			mesh_inst.mesh = sph
			mesh_inst.material_override = _mat_bio
			root.add_child(mesh_inst)
		"flak_shell":
			root = Node3D.new()
			var sph := SphereMesh.new()
			sph.radius = 0.18
			sph.height = 0.36
			mesh_inst.mesh = sph
			mesh_inst.material_override = _mat_flak
			root.add_child(mesh_inst)
		"rocket":
			root = Node3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.07
			cyl.bottom_radius = 0.11
			cyl.height = 0.48
			mesh_inst.mesh = cyl
			mesh_inst.rotation_degrees.x = 90.0
			mesh_inst.material_override = _mat_rocket
			root.add_child(mesh_inst)
		_:
			root = Node3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.09, 0.09, 0.22)
			mesh_inst.mesh = box
			mesh_inst.material_override = _mat_flak
			root.add_child(mesh_inst)

	add_child(root)
	root.global_position = pos
	if vel.length() > 0.1:
		var dn := vel.normalized()
		if absf(dn.dot(Vector3.UP)) < 0.99:
			root.look_at(pos + dn, Vector3.UP)

	var gravity_scale := 0.0
	if kind == "bio_glob" or kind == "flak_shell":
		gravity_scale = 18.0
	elif kind == "flak_shard":
		gravity_scale = 5.0

	_projectiles.append({
		"node": root,
		"kind": kind,
		"vel": vel,
		"dmg": dmg,
		"bounces": bounces,
		"owner": owner_body,
		"gravity": gravity_scale,
		"stuck": false,
		"life": 5.5 if kind == "bio_glob" else 3.2
	})

func _physics_process(delta: float) -> void:
	var space := get_world_3d().direct_space_state

	for i in range(_projectiles.size() - 1, -1, -1):
		var p: Dictionary = _projectiles[i]
		var node: Node3D = p["node"]

		if not is_instance_valid(node):
			_projectiles.remove_at(i)
			continue

		p["life"] -= delta
		if p["life"] <= 0.0:
			if p["kind"] == "bio_glob" and p["stuck"]:
				_explode(node.global_position, 2.8, p["dmg"], 7.0, p["owner"], Color(0.2, 1.0, 0.25))
			node.queue_free()
			_projectiles.remove_at(i)
			continue

		if p["stuck"]:
			var detonate := false
			for unit in get_tree().get_nodes_in_group("combatants"):
				if is_instance_valid(unit) and unit != p["owner"]:
					if node.global_position.distance_to(unit.global_position + Vector3(0, 0.9, 0)) < 1.8:
						detonate = true
						break
			if detonate:
				_explode(node.global_position, 3.4, p["dmg"], 9.0, p["owner"], Color(0.2, 1.0, 0.25))
				node.queue_free()
				_projectiles.remove_at(i)
			continue

		var vel: Vector3 = p["vel"]
		vel.y -= p["gravity"] * delta
		p["vel"] = vel

		var from := node.global_position
		var to := from + vel * delta

		var query := PhysicsRayQueryParameters3D.create(from, to)
		if is_instance_valid(p["owner"]):
			query.exclude = [p["owner"].get_rid()]
		var hit := space.intersect_ray(query)

		if hit.is_empty():
			node.global_position = to
			continue

		var collider: Object = hit["collider"]
		var hit_pos: Vector3 = hit["position"]
		var hit_norm: Vector3 = hit["normal"]
		var kind: String = p["kind"]

		if collider.has_method("take_damage"):
			if is_instance_valid(p["owner"]) and p["owner"].is_in_group("player") and collider != p["owner"]:
				SoundFX.play("hit_confirm", -3.0, 0.06)
			if kind == "rocket" or kind == "flak_shell":
				_explode(hit_pos, 4.6, p["dmg"], 14.0, p["owner"], Color(1.0, 0.45, 0.1))
				if kind == "flak_shell":
					_spawn_cluster_shards(hit_pos + hit_norm * 0.2, hit_norm, p["owner"])
			elif kind == "shock_core":
				_explode(hit_pos, 3.6, p["dmg"], 11.0, p["owner"], Color(0.75, 0.25, 1.0))
			elif kind == "bio_glob":
				_explode(hit_pos, 2.8, p["dmg"], 7.0, p["owner"], Color(0.2, 1.0, 0.25))
			else:
				collider.take_damage(p["dmg"], p["owner"], vel.normalized() * 4.5)
				_spawn_flash(hit_pos, 0.45, Color(1.0, 0.8, 0.2))
			node.queue_free()
			_projectiles.remove_at(i)
		else:
			if kind == "flak_shard" and p["bounces"] > 0:
				p["bounces"] -= 1
				p["vel"] = vel.bounce(hit_norm) * 0.78
				node.global_position = hit_pos + hit_norm * 0.06
				_spawn_flash(hit_pos, 0.3, Color(1.0, 0.85, 0.3))
				if randf() < 0.45:
					SoundFX.play("flak_ricochet", -9.0, 0.18)
			elif kind == "bio_glob":
				p["stuck"] = true
				p["vel"] = Vector3.ZERO
				node.global_position = hit_pos + hit_norm * 0.12
			else:
				if kind == "rocket":
					_explode(hit_pos, 4.8, p["dmg"], 15.0, p["owner"], Color(1.0, 0.35, 0.1))
				elif kind == "flak_shell":
					_explode(hit_pos, 4.2, p["dmg"], 12.0, p["owner"], Color(1.0, 0.65, 0.15))
					_spawn_cluster_shards(hit_pos + hit_norm * 0.25, hit_norm, p["owner"])
				elif kind == "shock_core":
					_explode(hit_pos, 3.4, p["dmg"], 10.0, p["owner"], Color(0.75, 0.25, 1.0))
				else:
					_spawn_flash(hit_pos, 0.35, Color(1.0, 0.75, 0.2))
				node.queue_free()
				_projectiles.remove_at(i)

	for j in range(_flashes.size() - 1, -1, -1):
		var f: Dictionary = _flashes[j]
		f["t"] += delta
		var ratio: float = f["t"] / f["dur"]
		if ratio >= 1.0:
			f["node"].queue_free()
			_flashes.remove_at(j)
		else:
			var sc: float = lerpf(0.25, f["max_r"], ratio)
			f["node"].scale = Vector3(sc, sc, sc)

	for k in range(_beams.size() - 1, -1, -1):
		var b: Dictionary = _beams[k]
		b["t"] += delta
		var ratio: float = b["t"] / b["dur"]
		if ratio >= 1.0:
			b["node"].queue_free()
			_beams.remove_at(k)
		else:
			b["mat"].albedo_color.a = (1.0 - ratio) * 0.9

func _spawn_cluster_shards(origin: Vector3, normal: Vector3, owner_body: Node) -> void:
	for k in range(6):
		var dir := (normal + Vector3(randf_range(-0.7, 0.7), randf_range(0.1, 0.8), randf_range(-0.7, 0.7))).normalized()
		spawn("flak_shard", origin, dir * 32.0, 14, 1, owner_body)

func _explode(origin: Vector3, radius: float, max_dmg: int, impulse: float, owner_body: Node, color: Color, play_sfx: bool = true) -> void:
	_spawn_flash(origin, radius * 0.58, color)
	if play_sfx:
		SoundFX.play("explosion", -3.0, 0.08)
	for unit in get_tree().get_nodes_in_group("combatants"):
		if not is_instance_valid(unit):
			continue
		var center := unit.global_position + Vector3(0, 0.9, 0)
		var dist := origin.distance_to(center)
		if dist <= radius:
			var falloff := 1.0 - (dist / radius)
			var dmg := int(max_dmg * falloff)
			var dir := (center - origin).normalized()
			if dir.length() < 0.01:
				dir = Vector3.UP
			unit.take_damage(dmg, owner_body, dir * impulse * falloff)

func _spawn_flash(pos: Vector3, max_r: float, col: Color) -> void:
	if _flashes.size() > 16:
		return
	var mi := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	sph.radial_segments = 8
	sph.rings = 5
	mi.mesh = sph
	var mat := _make_glow_mat(col)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.65
	mi.material_override = mat
	add_child(mi)
	mi.global_position = pos
	_flashes.append({ "node": mi, "t": 0.0, "dur": 0.24, "max_r": max_r })
