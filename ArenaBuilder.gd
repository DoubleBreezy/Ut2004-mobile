extends Node3D

const PlayerScript := preload("res://scripts/PlayerController.gd")
const WeaponScript := preload("res://scripts/WeaponSystem.gd")
const ViewmodelsScript := preload("res://scripts/WeaponViewmodels.gd")
const BotScript := preload("res://scripts/BotAI.gd")
const SpawnerScript := preload("res://scripts/ProjectileSpawner.gd")
const HudScript := preload("res://scripts/TouchHUD.gd")

var _mat_floor: StandardMaterial3D
var _mat_wall: StandardMaterial3D
var _mat_upper: StandardMaterial3D
var _mat_acid: StandardMaterial3D
var _mat_pad: StandardMaterial3D
var _mat_red_trim: StandardMaterial3D
var _mat_blue_trim: StandardMaterial3D

var _pickups: Array[Dictionary] = []

func _ready() -> void:
	_register_input_actions()
	_create_materials()
	_setup_environment()

	var spawner := Node3D.new()
	spawner.name = "ProjectileSpawner"
	spawner.set_script(SpawnerScript)
	add_child(spawner)

	var nav_region := NavigationRegion3D.new()
	nav_region.name = "ArenaNavRegion"
	add_child(nav_region)

	_build_deck17_arena(nav_region)
	_build_jump_pads()
	_build_acid_pit()
	_build_spawn_points()
	_build_pickups()

	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_radius = 0.55
	nav_mesh.agent_height = 1.9
	nav_mesh.agent_max_climb = 0.65
	nav_region.navigation_mesh = nav_mesh
	nav_region.bake_navigation_mesh(false)

	var player := _spawn_player()
	_spawn_bots()

	var hud := CanvasLayer.new()
	hud.name = "TouchHUD"
	hud.set_script(HudScript)
	add_child(hud)
	hud.bind_player(player)

	GameMode.start_match(GameMode.Mode.TEAM_DEATHMATCH, 35)

func _register_input_actions() -> void:
	var bindings := {
		"move_forward": KEY_W,
		"move_back": KEY_S,
		"move_left": KEY_A,
		"move_right": KEY_D
	}
	for action in bindings.keys():
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventKey.new()
			ev.keycode = bindings[action]
			InputMap.action_add_event(action, ev)

func _make_grid_tex(bg: Color, line: Color, accent: Color) -> ImageTexture:
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(bg)
	for i in range(64):
		img.set_pixel(i, 0, line)
		img.set_pixel(0, i, line)
		img.set_pixel(i, 32, line)
		img.set_pixel(32, i, line)
		if i % 8 == 0:
			img.set_pixel(i, 4, accent)
			img.set_pixel(i, 60, accent)
	return ImageTexture.create_from_image(img)

func _create_materials() -> void:
	_mat_floor = StandardMaterial3D.new()
	_mat_floor.albedo_texture = _make_grid_tex(Color(0.13, 0.15, 0.19), Color(0.22, 0.26, 0.32), Color(0.85, 0.65, 0.1))
	_mat_floor.uv1_triplanar = true
	_mat_floor.uv1_scale = Vector3(0.25, 0.25, 0.25)

	_mat_wall = StandardMaterial3D.new()
	_mat_wall.albedo_texture = _make_grid_tex(Color(0.17, 0.19, 0.24), Color(0.09, 0.11, 0.14), Color(0.2, 0.75, 1.0))
	_mat_wall.uv1_triplanar = true
	_mat_wall.uv1_scale = Vector3(0.2, 0.2, 0.2)

	_mat_upper = StandardMaterial3D.new()
	_mat_upper.albedo_texture = _make_grid_tex(Color(0.22, 0.20, 0.18), Color(0.35, 0.30, 0.22), Color(1.0, 0.55, 0.1))
	_mat_upper.uv1_triplanar = true
	_mat_upper.uv1_scale = Vector3(0.3, 0.3, 0.3)

	_mat_acid = StandardMaterial3D.new()
	_mat_acid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_acid.albedo_color = Color(0.16, 0.88, 0.24)

	_mat_pad = StandardMaterial3D.new()
	_mat_pad.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_pad.albedo_color = Color(0.15, 0.85, 1.0)

	_mat_red_trim = StandardMaterial3D.new()
	_mat_red_trim.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_red_trim.albedo_color = Color(0.95, 0.18, 0.18)

	_mat_blue_trim = StandardMaterial3D.new()
	_mat_blue_trim.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_blue_trim.albedo_color = Color(0.2, 0.55, 1.0)

func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.52, 0.65)
	env.ambient_light_energy = 0.78
	env.fog_enabled = true
	env.fog_light_color = Color(0.06, 0.08, 0.11)
	env.fog_density = 0.011

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 35, 0)
	sun.light_energy = 1.15
	sun.light_color = Color(0.95, 0.92, 0.85)
	add_child(sun)

func _add_block(parent: Node, pos: Vector3, size: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation_degrees = rot_deg
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_inst.mesh = box
	mesh_inst.material_override = mat
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(mesh_inst)
	body.add_child(col)
	parent.add_child(body)

func _build_deck17_arena(parent: Node) -> void:
	# Нижний пол вокруг центральной кислотной ямы
	_add_block(parent, Vector3(0, -0.5, -16), Vector3(52, 1, 20), _mat_floor)
	_add_block(parent, Vector3(0, -0.5, 16), Vector3(52, 1, 20), _mat_floor)
	_add_block(parent, Vector3(-16, -0.5, 0), Vector3(20, 1, 12), _mat_floor)
	_add_block(parent, Vector3(16, -0.5, 0), Vector3(20, 1, 12), _mat_floor)
	_add_block(parent, Vector3(0, -4.5, 0), Vector3(14, 1, 14), _mat_wall)

	# Стены и потолок
	_add_block(parent, Vector3(0, 7, -26.5), Vector3(54, 15, 1), _mat_wall)
	_add_block(parent, Vector3(0, 7, 26.5), Vector3(54, 15, 1), _mat_wall)
	_add_block(parent, Vector3(-26.5, 7, 0), Vector3(1, 15, 54), _mat_wall)
	_add_block(parent, Vector3(26.5, 7, 0), Vector3(1, 15, 54), _mat_wall)
	_add_block(parent, Vector3(0, 14.5, 0), Vector3(54, 1, 54), _mat_wall)

	# Неоновые полосы сторон команд (RED север, BLUE юг)
	_add_block(parent, Vector3(0, 9.5, -25.8), Vector3(44, 0.45, 0.25), _mat_red_trim)
	_add_block(parent, Vector3(0, 9.5, 25.8), Vector3(44, 0.45, 0.25), _mat_blue_trim)

	# Верхние галереи по периметру
	_add_block(parent, Vector3(0, 5.0, -21), Vector3(44, 0.7, 9), _mat_upper)
	_add_block(parent, Vector3(0, 5.0, 21), Vector3(44, 0.7, 9), _mat_upper)
	_add_block(parent, Vector3(-21, 5.0, 0), Vector3(9, 0.7, 34), _mat_upper)
	_add_block(parent, Vector3(21, 5.0, 0), Vector3(9, 0.7, 34), _mat_upper)

	# Центральный мостик над кислотной ямой
	_add_block(parent, Vector3(0, 5.0, 0), Vector3(4.5, 0.6, 34), _mat_upper)

	# Наклонные рампы на второй ярус
	_add_block(parent, Vector3(-12, 2.5, -14.5), Vector3(4.5, 0.6, 13.5), _mat_upper, Vector3(22, 0, 0))
	_add_block(parent, Vector3(12, 2.5, 14.5), Vector3(4.5, 0.6, 13.5), _mat_upper, Vector3(-22, 0, 0))

	# Опорные колонны
	for sx in [-12.0, 12.0]:
		for sz in [-8.0, 8.0]:
			_add_block(parent, Vector3(sx, 2.5, sz), Vector3(2.2, 5.2, 2.2), _mat_wall)

func _build_jump_pads() -> void:
	var pads := [
		{ "pos": Vector3(-19, 0.1, -14), "vel": Vector3(0, 14.8, -6.5) },
		{ "pos": Vector3(19, 0.1, 14), "vel": Vector3(0, 14.8, 6.5) },
		{ "pos": Vector3(-19, 0.1, 14), "vel": Vector3(0, 14.8, 6.5) },
		{ "pos": Vector3(19, 0.1, -14), "vel": Vector3(0, 14.8, -6.5) }
	]
	for cfg in pads:
		var area := Area3D.new()
		area.position = cfg["pos"]
		var col := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 1.35
		shape.height = 0.6
		col.shape = shape
		var mesh := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.3
		cyl.bottom_radius = 1.45
		cyl.height = 0.18
		mesh.mesh = cyl
		mesh.material_override = _mat_pad
		area.add_child(col)
		area.add_child(mesh)
		var launch: Vector3 = cfg["vel"]
		area.body_entered.connect(func(body: Node):
			if body.has_method("apply_jump_pad"):
				body.apply_jump_pad(launch)
			elif body is CharacterBody3D:
				body.velocity = launch
		)
		add_child(area)

func _build_acid_pit() -> void:
	var area := Area3D.new()
	area.position = Vector3(0, -3.2, 0)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(12, 1.4, 12)
	col.shape = shape
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(12, 0.25, 12)
	mesh.mesh = box
	mesh.material_override = _mat_acid
	area.add_child(col)
	area.add_child(mesh)
	area.body_entered.connect(func(body: Node):
		if body.has_method("take_damage"):
			body.take_damage(120, null, Vector3(0, 12, 0))
	)
	add_child(area)

func _build_spawn_points() -> void:
	var blue_pts := [Vector3(-18, 1.2, 20), Vector3(0, 6.5, 21), Vector3(18, 1.2, 20)]
	var red_pts := [Vector3(-18, 1.2, -20), Vector3(0, 6.5, -21), Vector3(18, 1.2, -20)]
	for p in blue_pts:
		var m := Marker3D.new()
		m.position = p
		m.add_to_group("spawn_blue")
		m.add_to_group("spawn_any")
		add_child(m)
	for p in red_pts:
		var m := Marker3D.new()
		m.position = p
		m.add_to_group("spawn_red")
		m.add_to_group("spawn_any")
		add_child(m)

func _build_pickups() -> void:
	var defs := [
		{ "pos": Vector3(0, 6.1, 0), "kind": "armor", "col": Color(1.0, 0.85, 0.1) },
		{ "pos": Vector3(-21, 6.1, 0), "kind": "health", "col": Color(0.2, 0.75, 1.0) },
		{ "pos": Vector3(21, 6.1, 0), "kind": "health", "col": Color(0.2, 0.75, 1.0) },
		{ "pos": Vector3(0, 0.8, 13), "kind": "ammo", "col": Color(0.75, 0.3, 1.0) },
		{ "pos": Vector3(0, 0.8, -13), "kind": "ammo", "col": Color(0.75, 0.3, 1.0) }
	]
	for d in defs:
		var area := Area3D.new()
		area.position = d["pos"]
		var col := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 0.9
		col.shape = shape
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.65, 0.65, 0.65)
		mesh.mesh = box
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = d["col"]
		mesh.material_override = mat
		area.add_child(col)
		area.add_child(mesh)
		add_child(area)

		var entry := { "area": area, "mesh": mesh, "kind": d["kind"], "respawn": 0.0 }
		_pickups.append(entry)
		area.body_entered.connect(func(body: Node):
			if entry["respawn"] > 0.0 or not body.is_in_group("player"):
				return
			match entry["kind"]:
				"health":
					body.hp = mini(body.max_hp, body.hp + 35)
				"armor":
					body.armor = mini(150, body.armor + 50)
				"ammo":
					for k in body.weapons.ammo.keys():
						body.weapons.ammo[k] += 15
			SoundFX.play("pickup", -3.0, 0.05)
			entry["respawn"] = 14.0
			entry["mesh"].visible = false
		)

func _process(delta: float) -> void:
	for p in _pickups:
		if p["respawn"] > 0.0:
			p["respawn"] -= delta
			if p["respawn"] <= 0.0:
				p["mesh"].visible = true
		else:
			p["mesh"].rotate_y(delta * 2.2)

func _spawn_player() -> CharacterBody3D:
	var p := CharacterBody3D.new()
	p.name = "Player"
	p.set_script(PlayerScript)
	p.add_to_group("combatants")
	p.add_to_group("player")

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	p.add_child(col)

	var head := Node3D.new()
	head.name = "Head"
	head.position.y = 1.55
	p.add_child(head)

	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.fov = 82.0
	cam.current = true
	head.add_child(cam)

	var wpn := Node3D.new()
	wpn.name = "WeaponSystem"
	wpn.set_script(WeaponScript)
	wpn.owner_body = p
	cam.add_child(wpn)

	var muzzle := Marker3D.new()
	muzzle.name = "MuzzlePoint"
	muzzle.position = Vector3(0.24, -0.18, -0.82)
	wpn.add_child(muzzle)
	wpn.muzzle_point = muzzle

	# Подключаем полноценные 3D-модели 4 пушек UT2004
	var vm := Node3D.new()
	vm.name = "WeaponViewmodels"
	vm.set_script(ViewmodelsScript)
	wpn.add_child(vm)
	wpn.viewmodels = vm

	p.position = Vector3(0, 6.5, 21)
	add_child(p)
	return p

func _spawn_bots() -> void:
	var configs := [
		{ "team": "RED", "pos": Vector3(-16, 1.2, -18) },
		{ "team": "RED", "pos": Vector3(0, 6.5, -20) },
		{ "team": "RED", "pos": Vector3(16, 1.2, -18) },
		{ "team": "BLUE", "pos": Vector3(-16, 1.2, 18) },
		{ "team": "BLUE", "pos": Vector3(16, 1.2, 18) }
	]
	for i in range(configs.size()):
		var cfg: Dictionary = configs[i]
		var b := CharacterBody3D.new()
		b.name = "Bot_%d" % i
		b.set_script(BotScript)
		b.team = cfg["team"]
		b.add_to_group("combatants")

		var col := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.45
		cap.height = 1.8
		col.shape = cap
		col.position.y = 0.9
		b.add_child(col)

		var nav := NavigationAgent3D.new()
		nav.name = "NavigationAgent3D"
		b.add_child(nav)

		var body_mesh := MeshInstance3D.new()
		var body_cap := CapsuleMesh.new()
		body_cap.radius = 0.42
		body_cap.height = 1.75
		body_mesh.mesh = body_cap
		body_mesh.position.y = 0.9
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(0.9, 0.18, 0.18) if cfg["team"] == "RED" else Color(0.18, 0.45, 0.95)
		body_mesh.material_override = bmat
		b.add_child(body_mesh)

		var visor := MeshInstance3D.new()
		var vbox := BoxMesh.new()
		vbox.size = Vector3(0.45, 0.14, 0.15)
		visor.mesh = vbox
		visor.position = Vector3(0, 1.45, -0.36)
		var vmat := StandardMaterial3D.new()
		vmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		vmat.albedo_color = Color(1.0, 0.9, 0.2)
		visor.material_override = vmat
		b.add_child(visor)

		b.position = cfg["pos"]
		add_child(b)
