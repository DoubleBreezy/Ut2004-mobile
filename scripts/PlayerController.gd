extends CharacterBody3D

@export var team: String = "BLUE"
@export var move_speed: float = 11.5
@export var jump_velocity: float = 7.6
@export var double_jump_velocity: float = 7.0
@export var dodge_speed: float = 18.5
@export var dodge_up_boost: float = 4.6
@export var gravity: float = 21.0
@export var air_control: float = 0.35

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapons: Node3D = $Head/Camera3D/WeaponSystem

var hp: int = 100
var armor: int = 50
var max_hp: int = 199
var jumps_left: int = 2
var dodge_cooldown: float = 0.0
var step_timer: float = 0.0
var touch_move_vec: Vector2 = Vector2.ZERO

func _physics_process(delta: float) -> void:
	if dodge_cooldown > 0.0:
		dodge_cooldown -= delta

	var input_dir := _get_move_input()
	var wish_dir := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	if is_on_floor():
		jumps_left = 2
		velocity.x = lerpf(velocity.x, wish_dir.x * move_speed, 14.0 * delta)
		velocity.z = lerpf(velocity.z, wish_dir.z * move_speed, 14.0 * delta)
	else:
		velocity.y -= gravity * delta
		velocity.x = lerpf(velocity.x, wish_dir.x * move_speed, air_control * 5.0 * delta)
		velocity.z = lerpf(velocity.z, wish_dir.z * move_speed, air_control * 5.0 * delta)

	move_and_slide()

	# Шаги и покачивание 3D-модели пушки
	var horiz_speed := Vector2(velocity.x, velocity.z).length()
	var speed_ratio := clampf(horiz_speed / move_speed, 0.0, 1.2)
	if is_on_floor() and horiz_speed > 2.2:
		step_timer -= delta
		if step_timer <= 0.0:
			step_timer = 0.34
			SoundFX.play("footstep", -11.0, 0.14)
	if weapons and weapons.has_method("update_viewmodel"):
		weapons.update_viewmodel(delta, speed_ratio, is_on_floor())

func _get_move_input() -> Vector2:
	if touch_move_vec.length() > 0.05:
		return touch_move_vec
	if InputMap.has_action("move_left"):
		return Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	return Vector2.ZERO

func _unhandled_input(event: InputEvent) -> void:
	# Поддержка клавиатуры и мыши (для ПК / DeX)
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_SPACE: trigger_jump()
			KEY_SHIFT: trigger_dodge()
			KEY_1: weapons.switch_weapon(0)
			KEY_2: weapons.switch_weapon(1)
			KEY_3: weapons.switch_weapon(2)
			KEY_4: weapons.switch_weapon(3)
	elif event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		apply_look_delta(event.relative, 0.0028)

func trigger_jump() -> void:
	if is_on_floor():
		velocity.y = jump_velocity
		jumps_left = 1
		SoundFX.play("jump", -6.0, 0.08)
	elif jumps_left > 0:
		velocity.y = double_jump_velocity
		jumps_left = 0
		SoundFX.play("jump", -5.0, 0.12)

func trigger_dodge() -> void:
	if not is_on_floor() or dodge_cooldown > 0.0:
		return
	var dir_2d := _get_move_input()
	if dir_2d.length() < 0.2:
		dir_2d = Vector2(0, -1)
	var dodge_dir := (transform.basis * Vector3(dir_2d.x, 0.0, dir_2d.y)).normalized()
	velocity.x = dodge_dir.x * dodge_speed
	velocity.z = dodge_dir.z * dodge_speed
	velocity.y = dodge_up_boost
	dodge_cooldown = 0.72
	jumps_left = 1
	SoundFX.play("dodge", -4.0, 0.08)

func apply_jump_pad(launch_vel: Vector3) -> void:
	velocity = launch_vel
	jumps_left = 1
	SoundFX.play("jump_pad", -2.5, 0.05)

func apply_look_delta(delta_xy: Vector2, sensitivity: float = 0.004) -> void:
	rotate_y(-delta_xy.x * sensitivity)
	head.rotate_x(-delta_xy.y * sensitivity)
	head.rotation.x = clampf(head.rotation.x, -1.35, 1.35)

func take_damage(amount: int, attacker: Node, knockback: Vector3 = Vector3.ZERO) -> void:
	velocity += knockback
	var absorbed := mini(armor, int(amount * 0.65))
	armor -= absorbed
	hp -= (amount - absorbed)
	SoundFX.play("hurt", -4.0, 0.1)
	if hp <= 0:
		GameMode.register_kill(attacker, self)
		_respawn()

func _respawn() -> void:
	hp = 100
	armor = 25
	velocity = Vector3.ZERO
	var spawns := get_tree().get_nodes_in_group("spawn_" + team.to_lower())
	if spawns.is_empty():
		spawns = get_tree().get_nodes_in_group("spawn_any")
	if not spawns.is_empty():
		global_transform = spawns.pick_random().global_transform
