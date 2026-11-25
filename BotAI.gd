extends CharacterBody3D

@export var team: String = "RED"
@export var move_speed: float = 9.5
@export var gravity: float = 21.0

@onready var nav: NavigationAgent3D = $NavigationAgent3D

var hp: int = 100
var fire_cd: float = 1.0
var strafe_dir: float = 1.0
var strafe_timer: float = 1.2
var target: CharacterBody3D = null

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	fire_cd -= delta
	strafe_timer -= delta
	if strafe_timer <= 0.0:
		strafe_timer = randf_range(0.7, 1.8)
		strafe_dir = -strafe_dir

	target = _find_nearest_enemy()
	if target and is_instance_valid(target):
		var to_target := target.global_position - global_position
		var horiz := Vector2(to_target.x, to_target.z)
		var dist := to_target.length()
		if horiz.length() > 0.1:
			look_at(Vector3(target.global_position.x, global_position.y, target.global_position.z), Vector3.UP)

		var move_dir := Vector3.ZERO
		if dist > 12.0:
			nav.target_position = target.global_position
			var next_pt := nav.get_next_path_position()
			var path_vec := next_pt - global_position
			path_vec.y = 0.0
			if path_vec.length() > 0.1:
				move_dir = path_vec.normalized()
		else:
			move_dir = transform.basis.x * strafe_dir

		velocity.x = move_dir.x * move_speed
		velocity.z = move_dir.z * move_speed

		if fire_cd <= 0.0 and dist < 34.0:
			fire_cd = randf_range(0.75, 1.25)
			var muzzle := global_position + Vector3(0, 1.4, 0)
			var aim_dir := (target.global_position + Vector3(0, 1.0, 0) - muzzle).normalized()
			get_tree().call_group("projectile_spawner", "spawn", "flak_shard", muzzle + aim_dir * 0.8, aim_dir * 38.0, 12, 1, self)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)

	move_and_slide()

func _find_nearest_enemy() -> CharacterBody3D:
	var best: CharacterBody3D = null
	var best_d := 999.0
	for unit in get_tree().get_nodes_in_group("combatants"):
		if not is_instance_valid(unit) or unit == self or unit.team == team:
			continue
		var d := global_position.distance_to(unit.global_position)
		if d < best_d:
			best_d = d
			best = unit
	return best

func take_damage(amount: int, attacker: Node, knockback: Vector3 = Vector3.ZERO) -> void:
	velocity += knockback
	hp -= amount
	if hp <= 0:
		GameMode.register_kill(attacker, self)
		hp = 100
		velocity = Vector3.ZERO
		var spawns := get_tree().get_nodes_in_group("spawn_" + team.to_lower())
		if not spawns.is_empty():
			global_transform = spawns.pick_random().global_transform
