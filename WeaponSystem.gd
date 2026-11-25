extends Node3D

enum WeaponId { BIO_RIFLE, SHOCK_RIFLE, FLAK_CANNON, ROCKET_LAUNCHER }

@export var owner_body: CharacterBody3D
@export var muzzle_point: Marker3D
@export var viewmodels: Node3D

var current_weapon: WeaponId = WeaponId.FLAK_CANNON
var cooldown: float = 0.0
var bio_charge: int = 0
var bio_charging: bool = false
var rocket_load: int = 0
var rocket_charging: bool = false

var ammo := {
	WeaponId.BIO_RIFLE: 40,
	WeaponId.SHOCK_RIFLE: 30,
	WeaponId.FLAK_CANNON: 24,
	WeaponId.ROCKET_LAUNCHER: 18
}

func _process(delta: float) -> void:
	if cooldown > 0.0:
		cooldown -= delta

func update_viewmodel(delta: float, speed_ratio: float, grounded: bool) -> void:
	if viewmodels and viewmodels.has_method("update_motion"):
		viewmodels.update_motion(delta, speed_ratio, grounded)

func get_charge_ratio() -> float:
	if bio_charging:
		return float(bio_charge) / 10.0
	if rocket_charging:
		return float(rocket_load) / 3.0
	return 0.0

func switch_weapon(id: int) -> void:
	var wid := clampi(id, 0, 3) as WeaponId
	if current_weapon == wid:
		return
	bio_charging = false
	rocket_charging = false
	bio_charge = 0
	rocket_load = 0
	if viewmodels:
		viewmodels.set_charge_level(0, 0)
		viewmodels.set_charge_level(3, 0)
		viewmodels.set_weapon(wid)
	current_weapon = wid
	cooldown = 0.25

func fire_primary() -> void:
	if cooldown > 0.0 or ammo[current_weapon] <= 0:
		return
	match current_weapon:
		WeaponId.FLAK_CANNON:
			ammo[WeaponId.FLAK_CANNON] -= 1
			cooldown = 0.72
			SoundFX.play("flak_fire", -1.5, 0.06)
			if viewmodels: viewmodels.trigger_recoil(1.2, Color(1.0, 0.72, 0.15))
			_fire_flak_shrapnel(9, 0.14)
		WeaponId.BIO_RIFLE:
			ammo[WeaponId.BIO_RIFLE] -= 1
			cooldown = 0.26
			SoundFX.play("bio_fire", -2.5, 0.09)
			if viewmodels: viewmodels.trigger_recoil(0.65, Color(0.2, 1.0, 0.25))
			_spawn_bio_glob(1)
		WeaponId.SHOCK_RIFLE:
			ammo[WeaponId.SHOCK_RIFLE] -= 1
			cooldown = 0.56
			SoundFX.play("shock_beam", -2.0, 0.05)
			if viewmodels: viewmodels.trigger_recoil(0.85, Color(0.78, 0.28, 1.0))
			_fire_shock_beam()
		WeaponId.ROCKET_LAUNCHER:
			ammo[WeaponId.ROCKET_LAUNCHER] -= 1
			cooldown = 0.85
			SoundFX.play("rocket_fire", -1.5, 0.06)
			if viewmodels: viewmodels.trigger_recoil(1.3, Color(1.0, 0.35, 0.12))
			_spawn_rocket(0.0)

func fire_alt_pressed() -> void:
	if cooldown > 0.0 or ammo[current_weapon] <= 0:
		return
	match current_weapon:
		WeaponId.FLAK_CANNON:
			ammo[WeaponId.FLAK_CANNON] -= 1
			cooldown = 0.88
			SoundFX.play("flak_alt", -1.5, 0.06)
			if viewmodels: viewmodels.trigger_recoil(1.1, Color(1.0, 0.65, 0.12))
			_spawn_flak_shell()
		WeaponId.SHOCK_RIFLE:
			ammo[WeaponId.SHOCK_RIFLE] -= 1
			cooldown = 0.60
			SoundFX.play("shock_core", -2.0, 0.06)
			if viewmodels: viewmodels.trigger_recoil(0.7, Color(0.78, 0.28, 1.0))
			_spawn_shock_core()
		WeaponId.BIO_RIFLE:
			bio_charging = true
			var next_c := mini(bio_charge + 1, mini(10, ammo[WeaponId.BIO_RIFLE]))
			if next_c != bio_charge:
				bio_charge = next_c
				SoundFX.play("bio_charge", -5.0, 0.08)
				if viewmodels: viewmodels.set_charge_level(0, bio_charge)
		WeaponId.ROCKET_LAUNCHER:
			rocket_charging = true
			var next_r := mini(rocket_load + 1, mini(3, ammo[WeaponId.ROCKET_LAUNCHER]))
			if next_r != rocket_load:
				rocket_load = next_r
				SoundFX.play("pickup", -7.0, 0.05)
				if viewmodels: viewmodels.set_charge_level(3, rocket_load)

func fire_alt_released() -> void:
	if bio_charging and bio_charge > 0:
		ammo[WeaponId.BIO_RIFLE] -= bio_charge
		SoundFX.play("bio_fire", -1.0, 0.05)
		if viewmodels:
			viewmodels.trigger_recoil(1.0, Color(0.2, 1.0, 0.25))
			viewmodels.set_charge_level(0, 0)
		_spawn_bio_glob(bio_charge)
		bio_charging = false
		bio_charge = 0
		cooldown = 0.55
	elif rocket_charging and rocket_load > 0:
		ammo[WeaponId.ROCKET_LAUNCHER] -= rocket_load
		SoundFX.play("rocket_fire", -0.5, 0.04)
		if viewmodels:
			viewmodels.trigger_recoil(1.4, Color(1.0, 0.35, 0.12))
			viewmodels.set_charge_level(3, 0)
		for i in range(rocket_load):
			var spread_angle := (i - (rocket_load - 1) * 0.5) * 0.075
			_spawn_rocket(spread_angle)
		rocket_charging = false
		rocket_load = 0
		cooldown = 1.05

func _fire_shock_beam() -> void:
	var space := get_world_3d().direct_space_state
	var from := muzzle_point.global_position
	var forward := -muzzle_point.global_transform.basis.z
	var to := from + forward * 120.0

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [owner_body.get_rid()]
	query.collide_with_areas = true
	var hit := space.intersect_ray(query)

	var end_pos := to
	if not hit.is_empty():
		end_pos = hit["position"]
		var collider: Object = hit["collider"]
		if collider.is_in_group("shock_core"):
			# BOOM! Легендарное Shock Combo (200 урона по области 7.5 м)
			SoundFX.play("shock_combo", 0.5, 0.03)
			get_tree().call_group("projectile_spawner", "trigger_shock_combo", collider.global_position, owner_body)
			collider.queue_free()
		elif collider.has_method("take_damage"):
			collider.take_damage(45, owner_body, forward * 7.5)
			SoundFX.play("hit_confirm", -2.0, 0.05)

	get_tree().call_group("projectile_spawner", "spawn_beam", from, end_pos, Color(0.82, 0.32, 1.0))

func _fire_flak_shrapnel(count: int, spread: float) -> void:
	for i in range(count):
		var dir := (-muzzle_point.global_transform.basis.z
			+ Vector3(randf_range(-spread, spread), randf_range(-spread, spread), 0)).normalized()
		_spawn_simple_projectile("flak_shard", dir * 48.0, 14, 2)

func _spawn_flak_shell() -> void:
	var dir := (-muzzle_point.global_transform.basis.z + Vector3(0, 0.22, 0)).normalized()
	_spawn_simple_projectile("flak_shell", dir * 24.0, 90, 0)

func _spawn_bio_glob(charge_level: int) -> void:
	var dir := (-muzzle_point.global_transform.basis.z + Vector3(0, 0.18, 0)).normalized()
	_spawn_simple_projectile("bio_glob", dir * 22.0, 20 * charge_level, 0)

func _spawn_shock_core() -> void:
	var dir := -muzzle_point.global_transform.basis.z
	_spawn_simple_projectile("shock_core", dir * 13.5, 45, 0)

func _spawn_rocket(yaw_offset: float) -> void:
	var dir := (-muzzle_point.global_transform.basis.z).rotated(Vector3.UP, yaw_offset)
	_spawn_simple_projectile("rocket", dir * 34.0, 90, 0)

func _spawn_simple_projectile(kind: String, vel: Vector3, dmg: int, bounces: int) -> void:
	get_tree().call_group("projectile_spawner", "spawn", kind, muzzle_point.global_position, vel, dmg, bounces, owner_body)
