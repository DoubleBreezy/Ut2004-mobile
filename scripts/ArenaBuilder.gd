extends Node3D

# ==============================================================================
# UT2004 MOBILE ARENA — DM-DECK17 EDITION (Godot 4.3, GL Compatibility 60 FPS)
# ==============================================================================

const LAYER_WORLD: int = 1
const LAYER_ACTORS: int = 2
const LAYER_SHOCK_CORE: int = 4

const TEAM_BLUE: int = 0
const TEAM_RED: int = 1

const WEP_SHOCK: int = 0
const WEP_FLAK: int = 1
const WEP_ROCKET: int = 2
const WEP_LINK: int = 3

var score_blue: int = 0
var score_red: int = 0
var match_time: float = 300.0
var first_blood_done: bool = false

var soldier_scene: PackedScene = null
var mat_floor: StandardMaterial3D = null
var mat_wall: StandardMaterial3D = null
var mat_trim: StandardMaterial3D = null
var mat_dark_steel: StandardMaterial3D = null
var mat_glow_cyan: StandardMaterial3D = null
var mat_glow_orange: StandardMaterial3D = null
var mat_glow_purple: StandardMaterial3D = null
var mat_glow_green: StandardMaterial3D = null
var mat_glow_red: StandardMaterial3D = null
var mat_acid: ShaderMaterial = null

var spawn_points_blue: Array = []
var spawn_points_red: Array = []
var jump_pads: Array = []
var pickups: Array = []
var bots: Array = []
var projectiles: Array = []
var shock_cores: Array = []
var effects: Array = []

var player: UTPlayer = null
var hud: UTHUD = null
var sfx: UTSoundBank = null
var acid_damage_timer: float = 0.0

func _ready() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()

	randomize()
	sfx = UTSoundBank.new()
	add_child(sfx)

	_load_assets_and_materials()
	_setup_environment()
	_build_deck17_arena()
	_setup_spawns_and_pickups()
	_spawn_player()
	_spawn_bots()

	hud = UTHUD.new()
	hud.arena = self
	add_child(hud)

func _load_assets_and_materials() -> void:
	if ResourceLoader.exists("res://assets/models/soldier.glb"):
		var loaded = ResourceLoader.load("res://assets/models/soldier.glb")
		if loaded is PackedScene:
			soldier_scene = loaded

	mat_floor = _make_pbr_material("floor", Color(0.55, 0.59, 0.65), 0.52, 0.72, Vector3(0.24, 0.24, 0.24), true)
	mat_wall = _make_pbr_material("wall", Color(0.42, 0.46, 0.52), 0.58, 0.65, Vector3(0.20, 0.20, 0.20), false)

	mat_dark_steel = StandardMaterial3D.new()
	mat_dark_steel.albedo_color = Color(0.18, 0.20, 0.24)
	mat_dark_steel.metallic = 0.82
	mat_dark_steel.roughness = 0.36
	if mat_wall.normal_texture != null:
		mat_dark_steel.normal_enabled = true
		mat_dark_steel.normal_texture = mat_wall.normal_texture
		mat_dark_steel.uv1_triplanar = true
		mat_dark_steel.uv1_world_triplanar = true
		mat_dark_steel.uv1_scale = Vector3(0.35, 0.35, 0.35)

	mat_trim = StandardMaterial3D.new()
	mat_trim.albedo_texture = _make_hazard_texture()
	mat_trim.roughness = 0.45
	mat_trim.metallic = 0.35
	mat_trim.uv1_triplanar = true
	mat_trim.uv1_world_triplanar = true
	mat_trim.uv1_scale = Vector3(0.5, 0.5, 0.5)

	mat_glow_cyan = _make_glow_material(Color(0.15, 0.88, 1.0), 3.0)
	mat_glow_orange = _make_glow_material(Color(1.0, 0.55, 0.12), 2.8)
	mat_glow_purple = _make_glow_material(Color(0.72, 0.22, 1.0), 3.4)
	mat_glow_green = _make_glow_material(Color(0.15, 1.0, 0.35), 3.0)
	mat_glow_red = _make_glow_material(Color(1.0, 0.18, 0.14), 3.0)
	mat_acid = _make_acid_shader_material()

func _make_pbr_material(prefix: String, tint: Color, rough: float, metal: float, uv_scale: Vector3, is_diamond: bool) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.roughness = rough
	mat.metallic = metal
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = uv_scale

	var p_col = "res://assets/textures/%s_color.jpg" % prefix
	var p_nor = "res://assets/textures/%s_normal.jpg" % prefix
	var p_rgh = "res://assets/textures/%s_roughness.jpg" % prefix
	var p_met = "res://assets/textures/%s_metalness.jpg" % prefix

	if ResourceLoader.exists(p_col):
		mat.albedo_texture = ResourceLoader.load(p_col)
		mat.albedo_color = Color(0.82, 0.85, 0.90)
	else:
		mat.albedo_texture = _make_procedural_metal_albedo(is_diamond)

	if ResourceLoader.exists(p_nor):
		mat.normal_enabled = true
		mat.normal_texture = ResourceLoader.load(p_nor)
		mat.normal_scale = 1.25
	else:
		mat.normal_enabled = true
		mat.normal_texture = _make_procedural_metal_normal(is_diamond)
		mat.normal_scale = 1.1

	if ResourceLoader.exists(p_rgh):
		mat.roughness_texture = ResourceLoader.load(p_rgh)
		mat.roughness = 0.85

	if ResourceLoader.exists(p_met):
		mat.metallic_texture = ResourceLoader.load(p_met)
		mat.metallic = 0.9

	return mat

func _make_glow_material(col: Color, energy: float) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	m.roughness = 0.2
	return m

func _make_acid_shader_material() -> ShaderMaterial:
	var sh = Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled;

void fragment() {
	vec2 uv = UV * 10.0;
	float t = TIME * 0.9;
	float w1 = sin(uv.x * 2.1 + t) * cos(uv.y * 1.9 - t * 0.8);
	float w2 = sin((uv.x + uv.y) * 3.3 - t * 1.4) * 0.5;
	float bubble = sin(length(fract(uv * 0.65) - 0.5) * 18.0 - t * 3.0);
	float v = clamp(0.5 + 0.35 * (w1 + w2) + 0.18 * bubble, 0.0, 1.0);
	vec3 dark_slime = vec3(0.03, 0.22, 0.05);
	vec3 bright_slime = vec3(0.42, 1.0, 0.12);
	vec3 col = mix(dark_slime, bright_slime, smoothstep(0.2, 0.92, v));
	ALBEDO = col;
	EMISSION = col * (1.2 + v * 1.6);
	ROUGHNESS = 0.15;
	METALLIC = 0.1;
}
"""
	var sm = ShaderMaterial.new()
	sm.shader = sh
	return sm

func _make_hazard_texture() -> ImageTexture:
	var img = Image.create_empty(128, 128, false, Image.FORMAT_RGBA8)
	for y in range(128):
		for x in range(128):
			var band = int((x + y) / 16) % 2
			var c = Color(0.95, 0.68, 0.08) if band == 0 else Color(0.09, 0.10, 0.12)
			var grit = float(((x * 37 + y * 91) % 19) - 9) * 0.006
			img.set_pixel(x, y, Color(clamp(c.r + grit, 0.0, 1.0), clamp(c.g + grit, 0.0, 1.0), clamp(c.b + grit, 0.0, 1.0), 1.0))
	return ImageTexture.create_from_image(img)

func _make_procedural_metal_albedo(is_diamond: bool) -> ImageTexture:
	var size = 128
	var img = Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			var base = 0.34 if is_diamond else 0.28
			var edge = (x < 3 or y < 3 or x > size - 4 or y > size - 4)
			var seam = (x == 64 or y == 64)
			var val = base
			if edge or seam:
				val *= 0.45
			elif is_diamond:
				var dx = (x % 16) - 8
				var dy = (y % 16) - 8
				if abs(dx) + abs(dy) < 5:
					val += 0.16
			else:
				var rivet = ((x % 32 == 6 or x % 32 == 26) and (y % 32 == 6 or y % 32 == 26))
				if rivet:
					val += 0.22
			var n = float(((x * 17 + y * 53 + x * y) % 23) - 11) * 0.004
			var c = clamp(val + n, 0.05, 0.95)
			img.set_pixel(x, y, Color(c * 0.94, c * 0.98, c * 1.06, 1.0))
	return ImageTexture.create_from_image(img)

func _make_procedural_metal_normal(is_diamond: bool) -> ImageTexture:
	var size = 128
	var img = Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			var nx = 0.5
			var ny = 0.5
			if x < 3 or x == 64:
				nx = 0.2
			elif x > size - 4 or x == 65:
				nx = 0.8
			if y < 3 or y == 64:
				ny = 0.2
			elif y > size - 4 or y == 65:
				ny = 0.8
			if is_diamond:
				var dx = (x % 16) - 8
				var dy = (y % 16) - 8
				if abs(dx) + abs(dy) < 5:
					nx = clamp(0.5 + float(dx) * 0.08, 0.1, 0.9)
					ny = clamp(0.5 + float(dy) * 0.08, 0.1, 0.9)
			img.set_pixel(x, y, Color(nx, ny, 0.96, 1.0))
	return ImageTexture.create_from_image(img)

func _setup_environment() -> void:
	var we = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.045, 0.075)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.38, 0.48)
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.15
	env.glow_enabled = true
	env.glow_intensity = 0.65
	env.glow_bloom = 0.22
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.09, 0.11)
	env.fog_density = 0.0075
	we.environment = env
	add_child(we)

	var sun = DirectionalLight3D.new()
	sun.light_color = Color(0.86, 0.91, 1.0)
	sun.light_energy = 1.15
	sun.rotation_degrees = Vector3(-58, 32, 0)
	sun.shadow_enabled = true
	add_child(sun)

	# Acid pit eerie green uplight
	_add_point_light(Vector3(0, 0.6, 0), Color(0.28, 1.0, 0.25), 5.0, 22.0)
	# Warm industrial sodium lamps over upper walkways
	_add_point_light(Vector3(-17, 9.5, -14), Color(1.0, 0.66, 0.28), 3.6, 26.0)
	_add_point_light(Vector3(17, 9.5, 14), Color(1.0, 0.66, 0.28), 3.6, 26.0)
	# Cool team base accent lights
	_add_point_light(Vector3(0, 6.5, -24), Color(0.25, 0.72, 1.0), 3.2, 22.0)
	_add_point_light(Vector3(0, 6.5, 24), Color(1.0, 0.28, 0.22), 3.2, 22.0)
	# Overhead bridge key light
	_add_point_light(Vector3(0, 9.8, 0), Color(0.75, 0.55, 1.0), 2.8, 18.0)

func _add_point_light(pos: Vector3, col: Color, energy: float, rng: float) -> void:
	var l = OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = false
	add_child(l)

func _add_box(pos: Vector3, size: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO, has_col: bool = true) -> Node3D:
	var root: Node3D = null
	if has_col:
		var body = StaticBody3D.new()
		body.collision_layer = LAYER_WORLD
		body.collision_mask = 0
		var col = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = size
		col.shape = shape
		body.add_child(col)
		root = body
	else:
		root = Node3D.new()

	var mi = MeshInstance3D.new()
	var bm = BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	root.add_child(mi)
	root.position = pos
	root.rotation_degrees = rot_deg
	add_child(root)
	return root

func _build_deck17_arena() -> void:
	# Outer bounds: X in [-24, 24], Z in [-28, 28], Ceiling at Y = 14
	# Lower floor around central acid vat (Acid vat: X in [-7, 7], Z in [-9, 9])
	_add_box(Vector3(0, -0.5, -18.5), Vector3(48, 1.0, 19.0), mat_floor) # North lower deck
	_add_box(Vector3(0, -0.5, 18.5), Vector3(48, 1.0, 19.0), mat_floor)  # South lower deck
	_add_box(Vector3(-15.5, -0.5, 0), Vector3(17.0, 1.0, 18.0), mat_floor) # West lower deck
	_add_box(Vector3(15.5, -0.5, 0), Vector3(17.0, 1.0, 18.0), mat_floor)  # East lower deck

	# Acid vat basin floor & walls
	_add_box(Vector3(0, -3.0, 0), Vector3(16.0, 1.0, 20.0), mat_dark_steel)
	_add_box(Vector3(0, -1.6, -9.2), Vector3(14.8, 2.4, 0.6), mat_dark_steel)
	_add_box(Vector3(0, -1.6, 9.2), Vector3(14.8, 2.4, 0.6), mat_dark_steel)
	_add_box(Vector3(-7.2, -1.6, 0), Vector3(0.6, 2.4, 18.8), mat_dark_steel)
	_add_box(Vector3(7.2, -1.6, 0), Vector3(0.6, 2.4, 18.8), mat_dark_steel)

	# Glowing bubbling green acid surface
	var acid_mesh = MeshInstance3D.new()
	var pm = PlaneMesh.new()
	pm.size = Vector2(14.2, 18.2)
	acid_mesh.mesh = pm
	acid_mesh.material_override = mat_acid
	acid_mesh.position = Vector3(0, -1.35, 0)
	add_child(acid_mesh)

	# Hazard warning trim strips around the acid vat
	_add_box(Vector3(0, 0.04, -9.25), Vector3(15.0, 0.08, 0.55), mat_trim, Vector3.ZERO, false)
	_add_box(Vector3(0, 0.04, 9.25), Vector3(15.0, 0.08, 0.55), mat_trim, Vector3.ZERO, false)
	_add_box(Vector3(-7.25, 0.04, 0), Vector3(0.55, 0.08, 18.0), mat_trim, Vector3.ZERO, false)
	_add_box(Vector3(7.25, 0.04, 0), Vector3(0.55, 0.08, 18.0), mat_trim, Vector3.ZERO, false)

	# Perimeter industrial walls (Height = 14)
	_add_box(Vector3(0, 7.0, -28.5), Vector3(50, 15.0, 1.0), mat_wall)
	_add_box(Vector3(0, 7.0, 28.5), Vector3(50, 15.0, 1.0), mat_wall)
	_add_box(Vector3(-24.5, 7.0, 0), Vector3(1.0, 15.0, 58.0), mat_wall)
	_add_box(Vector3(24.5, 7.0, 0), Vector3(1.0, 15.0, 58.0), mat_wall)

	# Ceiling & heavy steel roof trusses + glowing light strips
	_add_box(Vector3(0, 14.5, 0), Vector3(50, 1.0, 58), mat_dark_steel)
	for z_beam in [-20.0, -10.0, 0.0, 10.0, 20.0]:
		_add_box(Vector3(0, 13.4, z_beam), Vector3(48, 1.2, 1.2), mat_dark_steel, Vector3.ZERO, false)
		_add_box(Vector3(0, 12.75, z_beam), Vector3(26, 0.16, 0.35), mat_glow_orange, Vector3.ZERO, false)

	# Glowing Team Base Banners on North (Blue) & South (Red) walls
	_add_box(Vector3(0, 9.2, -27.85), Vector3(16.0, 0.45, 0.25), mat_glow_cyan, Vector3.ZERO, false)
	_add_box(Vector3(0, 9.2, 27.85), Vector3(16.0, 0.45, 0.25), mat_glow_red, Vector3.ZERO, false)

	# Upper Deck Catwalks (Y = 4.4)
	_add_box(Vector3(0, 4.15, -23.5), Vector3(48, 0.5, 9.0), mat_floor) # North balcony
	_add_box(Vector3(0, 4.15, 23.5), Vector3(48, 0.5, 9.0), mat_floor)  # South balcony
	_add_box(Vector3(-20.0, 4.15, 0), Vector3(8.0, 0.5, 38.0), mat_floor) # West balcony
	_add_box(Vector3(20.0, 4.15, 0), Vector3(8.0, 0.5, 38.0), mat_floor)  # East balcony

	# Central High Bridge across the acid vat (Classic Deck17 bridge!)
	_add_box(Vector3(0, 4.15, 0), Vector3(32.0, 0.48, 4.6), mat_floor)
	_add_box(Vector3(0, 4.42, -2.2), Vector3(30.0, 0.12, 0.22), mat_glow_purple, Vector3.ZERO, false)
	_add_box(Vector3(0, 4.42, 2.2), Vector3(30.0, 0.12, 0.22), mat_glow_purple, Vector3.ZERO, false)

	# Wide gentle ramps from Lower Floor (Y=0) up to Upper Deck (Y=4.4)
	# Ramp length = 12.5m, rise = 4.4m -> angle ~20.6 deg (super smooth!)
	_add_box(Vector3(-12.5, 2.05, -13.0), Vector3(4.6, 0.45, 12.8), mat_floor, Vector3(20.5, 0, 0))
	_add_box(Vector3(12.5, 2.05, 13.0), Vector3(4.6, 0.45, 12.8), mat_floor, Vector3(-20.5, 0, 0))
	# Hazard side rails on ramps
	_add_box(Vector3(-14.7, 2.35, -13.0), Vector3(0.25, 0.4, 12.8), mat_trim, Vector3(20.5, 0, 0), false)
	_add_box(Vector3(14.7, 2.35, 13.0), Vector3(0.25, 0.4, 12.8), mat_trim, Vector3(-20.5, 0, 0), false)

	# Massive Deck17 support pillars around the pit corners
	var pillar_coords = [
		Vector3(-9.5, 6.8, -11.5),
		Vector3(9.5, 6.8, -11.5),
		Vector3(-9.5, 6.8, 11.5),
		Vector3(9.5, 6.8, 11.5)
	]
	for p in pillar_coords:
		_add_box(p, Vector3(2.4, 14.0, 2.4), mat_wall)
		_add_box(Vector3(p.x, 2.2, p.z), Vector3(2.65, 0.35, 2.65), mat_trim, Vector3.ZERO, false)
		_add_box(Vector3(p.x, 7.6, p.z), Vector3(2.6, 0.25, 2.6), mat_glow_orange, Vector3.ZERO, false)

	# Tactical steel cover bunkers on lower & upper decks
	_add_box(Vector3(0, 1.1, -15.0), Vector3(5.0, 2.2, 1.4), mat_dark_steel)
	_add_box(Vector3(0, 1.1, 15.0), Vector3(5.0, 2.2, 1.4), mat_dark_steel)
	_add_box(Vector3(-13.5, 1.0, 5.5), Vector3(2.6, 2.0, 2.6), mat_dark_steel)
	_add_box(Vector3(13.5, 1.0, -5.5), Vector3(2.6, 2.0, 2.6), mat_dark_steel)
	_add_box(Vector3(-19.0, 5.4, -10.0), Vector3(1.2, 2.0, 3.8), mat_dark_steel)
	_add_box(Vector3(19.0, 5.4, 10.0), Vector3(1.2, 2.0, 3.8), mat_dark_steel)

	# Glowing Jump Pads (Lower floor corners -> Upper Deck!)
	_add_jump_pad(Vector3(13.5, 0.08, -14.5), Vector3(19.0, 6.2, -16.0))
	_add_jump_pad(Vector3(-13.5, 0.08, 14.5), Vector3(-19.0, 6.2, 16.0))

func _add_jump_pad(pos: Vector3, target_pos: Vector3) -> void:
	var pad = Node3D.new()
	pad.position = pos
	add_child(pad)

	var base = MeshInstance3D.new()
	var cm = CylinderMesh.new()
	cm.top_radius = 1.5
	cm.bottom_radius = 1.75
	cm.height = 0.22
	base.mesh = cm
	base.material_override = mat_dark_steel
	pad.add_child(base)

	var ring = MeshInstance3D.new()
	var tm = TorusMesh.new()
	tm.inner_radius = 0.95
	tm.outer_radius = 1.35
	ring.mesh = tm
	ring.material_override = mat_glow_cyan
	ring.position = Vector3(0, 0.14, 0)
	pad.add_child(ring)

	var core = MeshInstance3D.new()
	var c2 = CylinderMesh.new()
	c2.top_radius = 0.75
	c2.bottom_radius = 0.75
	c2.height = 0.08
	core.mesh = c2
	core.material_override = mat_glow_cyan
	core.position = Vector3(0, 0.12, 0)
	pad.add_child(core)

	var vel = (target_pos - pos)
	vel.y = 0.0
	var horiz = vel.normalized() * 9.5
	var launch_vel = Vector3(horiz.x, 15.8, horiz.z)
	jump_pads.append({"pos": pos, "vel": launch_vel, "ring": ring})

func _setup_spawns_and_pickups() -> void:
	spawn_points_blue = [
		Vector3(-6.0, 0.2, -22.0),
		Vector3(6.0, 0.2, -22.0),
		Vector3(0.0, 4.7, -23.5),
		Vector3(-19.5, 4.7, -14.0)
	]
	spawn_points_red = [
		Vector3(6.0, 0.2, 22.0),
		Vector3(-6.0, 0.2, 22.0),
		Vector3(0.0, 4.7, 23.5),
		Vector3(19.5, 4.7, 14.0)
	]

	# Pickups: health, armor, U-Damage
	_add_pickup(Vector3(0.0, 4.7, 0.0), "udamage", mat_glow_purple, 28.0)
	_add_pickup(Vector3(-19.5, 4.7, 0.0), "armor", mat_glow_orange, 18.0)
	_add_pickup(Vector3(19.5, 4.7, 0.0), "armor", mat_glow_orange, 18.0)
	_add_pickup(Vector3(-12.0, 0.3, -2.0), "health", mat_glow_cyan, 12.0)
	_add_pickup(Vector3(12.0, 0.3, 2.0), "health", mat_glow_cyan, 12.0)
	_add_pickup(Vector3(0.0, 4.7, -21.0), "health", mat_glow_cyan, 12.0)
	_add_pickup(Vector3(0.0, 4.7, 21.0), "health", mat_glow_cyan, 12.0)

func _add_pickup(pos: Vector3, kind: String, mat: Material, respawn_sec: float) -> void:
	var root = Node3D.new()
	root.position = pos
	add_child(root)

	var holo_base = MeshInstance3D.new()
	var bm = CylinderMesh.new()
	bm.top_radius = 0.65
	bm.bottom_radius = 0.75
	bm.height = 0.12
	holo_base.mesh = bm
	holo_base.material_override = mat_dark_steel
	root.add_child(holo_base)

	var item_node = Node3D.new()
	item_node.position = Vector3(0, 0.85, 0)
	root.add_child(item_node)

	var m = MeshInstance3D.new()
	if kind == "health":
		var b1 = BoxMesh.new()
		b1.size = Vector3(0.68, 0.24, 0.24)
		m.mesh = b1
		m.material_override = mat
		item_node.add_child(m)
		var m2 = MeshInstance3D.new()
		var b2 = BoxMesh.new()
		b2.size = Vector3(0.24, 0.68, 0.24)
		m2.mesh = b2
		m2.material_override = mat
		item_node.add_child(m2)
	elif kind == "armor":
		var sm = PrismMesh.new()
		sm.size = Vector3(0.72, 0.82, 0.32)
		m.mesh = sm
		m.material_override = mat
		item_node.add_child(m)
	else:
		var tm = TorusMesh.new()
		tm.inner_radius = 0.25
		tm.outer_radius = 0.55
		m.mesh = tm
		m.material_override = mat
		m.rotation_degrees = Vector3(90, 0, 0)
		item_node.add_child(m)

	pickups.append({
		"pos": pos,
		"kind": kind,
		"node": item_node,
		"active": true,
		"timer": 0.0,
		"respawn": respawn_sec
	})

func _spawn_player() -> void:
	player = UTPlayer.new()
	player.arena = self
	player.team = TEAM_BLUE
	add_child(player)
	player.respawn()

func _spawn_bots() -> void:
	var bot_roster = [
		{"name": "Xan Kriegor", "team": TEAM_RED},
		{"name": "Malcolm", "team": TEAM_RED},
		{"name": "Brock", "team": TEAM_RED},
		{"name": "Sapphire", "team": TEAM_BLUE},
		{"name": "Gorge", "team": TEAM_BLUE}
	]
	for info in bot_roster:
		var b = UTBot.new()
		b.arena = self
		b.bot_name = info["name"]
		b.team = info["team"]
		add_child(b)
		b.respawn()
		bots.append(b)

func get_spawn_point(team: int) -> Vector3:
	var list = spawn_points_blue if team == TEAM_BLUE else spawn_points_red
	return list[randi() % list.size()]

func _process(delta: float) -> void:
	match_time = max(0.0, match_time - delta)
	if match_time <= 0.0:
		match_time = 300.0
		score_blue = 0
		score_red = 0
		first_blood_done = false
		if hud != null:
			hud.show_banner("NEW MATCH — FIGHT!", Color(0.25, 0.9, 1.0))

	# Animate jump pads
	for jp in jump_pads:
		var r: Node3D = jp["ring"]
		r.rotation.y += delta * 2.4
		r.position.y = 0.15 + sin(Time.get_ticks_msec() * 0.006) * 0.05

	# Animate and check pickups
	for p in pickups:
		var item: Node3D = p["node"]
		if not p["active"]:
			p["timer"] -= delta
			if p["timer"] <= 0.0:
				p["active"] = true
				item.visible = true
		else:
			item.rotation.y += delta * 2.6
			item.position.y = 0.88 + sin(Time.get_ticks_msec() * 0.004 + p["pos"].x) * 0.14
			_check_pickup_collect(p)

	# Acid vat damage check
	acid_damage_timer -= delta
	if acid_damage_timer <= 0.0:
		acid_damage_timer = 0.35
		_check_acid_damage()

	# Update projectiles
	var keep_proj: Array = []
	for pr in projectiles:
		if is_instance_valid(pr):
			if pr.step_projectile(delta):
				keep_proj.append(pr)
			else:
				pr.queue_free()
	projectiles = keep_proj

	# Update shock cores
	var keep_cores: Array = []
	for sc in shock_cores:
		if is_instance_valid(sc):
			if sc.step_core(delta):
				keep_cores.append(sc)
			else:
				sc.queue_free()
	shock_cores = keep_cores

	# Update VFX
	var keep_fx: Array = []
	for fx in effects:
		if is_instance_valid(fx):
			if fx.step_fx(delta):
				keep_fx.append(fx)
			else:
				fx.queue_free()
	effects = keep_fx

func _check_pickup_collect(p: Dictionary) -> void:
	var ppos: Vector3 = p["pos"]
	var actors: Array = [player]
	for b in bots:
		actors.append(b)
	for a in actors:
		if not is_instance_valid(a) or not a.alive:
			continue
		if a.global_position.distance_to(ppos) < 1.65:
			var used = false
			if p["kind"] == "health" and a.hp < 150:
				a.hp = min(150, a.hp + 35)
				used = true
			elif p["kind"] == "armor" and a.armor < 100:
				a.armor = min(100, a.armor + 50)
				used = true
			elif p["kind"] == "udamage":
				a.udamage_timer = 15.0
				used = true
				if a == player and hud != null:
					hud.show_banner("DOUBLE DAMAGE!", Color(0.82, 0.32, 1.0))
			if used:
				p["active"] = false
				p["timer"] = p["respawn"]
				p["node"].visible = false
				if a == player:
					sfx.play_sfx("pickup")
				return

func _check_acid_damage() -> void:
	var actors: Array = [player]
	for b in bots:
		actors.append(b)
	for a in actors:
		if not is_instance_valid(a) or not a.alive:
			continue
		var gp = a.global_position
		if gp.y < -0.75 and abs(gp.x) < 7.2 and abs(gp.z) < 9.2:
			a.apply_damage(16, null, "Acid Vat", Vector3(0, 6.0, 0))
			if a == player and hud != null:
				hud.flash_screen(Color(0.2, 1.0, 0.2, 0.35))

func check_jump_pads(actor: CharacterBody3D) -> bool:
	for jp in jump_pads:
		if actor.global_position.distance_to(jp["pos"]) < 1.85 and actor.velocity.y < 10.0:
			actor.velocity = jp["vel"]
			if actor == player:
				sfx.play_sfx("jump_pad")
			return true
	return false

func register_kill(killer, victim, weapon_name: String) -> void:
	if victim.team == TEAM_RED:
		score_blue += 1
	else:
		score_red += 1

	var kname = "Environment"
	var kteam = -1
	if killer != null and is_instance_valid(killer):
		kname = "YOU" if killer == player else killer.bot_name
		kteam = killer.team
	var vname = "YOU" if victim == player else victim.bot_name

	if hud != null:
		hud.add_killfeed(kname, kteam, vname, victim.team, weapon_name)

	if killer == player:
		player.register_player_kill(weapon_name)

func spawn_beam(from_pos: Vector3, to_pos: Vector3, col: Color, radius: float, life: float) -> void:
	var fx = UTBeamFX.new()
	fx.setup(from_pos, to_pos, col, radius, life)
	add_child(fx)
	effects.append(fx)

func spawn_explosion(pos: Vector3, radius: float, col: Color, damage: int, attacker, weapon_name: String, knockback: float) -> void:
	var fx = UTExplosionFX.new()
	fx.setup(pos, radius, col, 0.38)
	add_child(fx)
	effects.append(fx)
	sfx.play_sfx("shock_combo" if weapon_name == "Shock Combo" else "explosion")

	var actors: Array = [player]
	for b in bots:
		actors.append(b)
	for a in actors:
		if not is_instance_valid(a) or not a.alive:
			continue
		var center = a.global_position + Vector3(0, 0.95, 0)
		var dist = center.distance_to(pos)
		if dist < radius:
			var falloff = clamp(1.0 - (dist / radius), 0.15, 1.0)
			var push_dir = (center - pos)
			if push_dir.length() < 0.05:
				push_dir = Vector3.UP
			push_dir = push_dir.normalized()
			var impulse = push_dir * (knockback * falloff)
			impulse.y = max(impulse.y, 4.5 * falloff)
			var dmg = int(round(float(damage) * falloff))
			if a == attacker:
				# Reduced self-damage so Rocket Jumping feels awesome!
				dmg = int(round(float(dmg) * 0.25))
				impulse *= 1.35
			elif attacker != null and a.team == attacker.team:
				continue
			a.apply_damage(dmg, attacker, weapon_name, impulse)

func spawn_projectile(pos: Vector3, vel: Vector3, kind: String, attacker, dmg: int, splash: float, bounces: int) -> void:
	var pr = UTProjectile.new()
	pr.arena = self
	pr.setup(pos, vel, kind, attacker, dmg, splash, bounces)
	add_child(pr)
	projectiles.append(pr)

func spawn_shock_core(pos: Vector3, vel: Vector3, attacker) -> void:
	var sc = UTShockCore.new()
	sc.arena = self
	sc.setup(pos, vel, attacker)
	add_child(sc)
	shock_cores.append(sc)

# ==============================================================================
# PROCEDURAL 16-BIT WAV SOUND SYNTHESIZER (Zero external audio files needed)
# ==============================================================================
class UTSoundBank extends Node:
	var bank: Dictionary = {}
	var players: Array = []
	var next_idx: int = 0

	func _ready() -> void:
		for i in range(8):
			var p = AudioStreamPlayer.new()
			p.volume_db = -8.0
			add_child(p)
			players.append(p)

		bank["shock_fire"] = _gen_tone(0.18, 920.0, 210.0, 0.25, 0.8)
		bank["shock_combo"] = _gen_tone(0.45, 360.0, 42.0, 0.65, 1.0)
		bank["flak_fire"] = _gen_tone(0.20, 220.0, 65.0, 0.85, 0.9)
		bank["rocket_fire"] = _gen_tone(0.26, 170.0, 55.0, 0.72, 0.85)
		bank["link_fire"] = _gen_tone(0.09, 680.0, 420.0, 0.15, 0.55)
		bank["explosion"] = _gen_tone(0.38, 120.0, 32.0, 0.92, 0.95)
		bank["hit"] = _gen_tone(0.055, 1480.0, 1180.0, 0.05, 0.65)
		bank["jump_pad"] = _gen_tone(0.28, 240.0, 980.0, 0.1, 0.75)
		bank["dodge"] = _gen_tone(0.13, 300.0, 140.0, 0.4, 0.55)
		bank["pickup"] = _gen_tone(0.22, 520.0, 1040.0, 0.0, 0.65)

	func _gen_tone(dur: float, f0: float, f1: float, noise_mix: float, amp: float) -> AudioStreamWAV:
		var rate = 22050
		var count = int(dur * rate)
		var data = PackedByteArray()
		data.resize(count * 2)
		var phase = 0.0
		var rng = RandomNumberGenerator.new()
		rng.seed = int(f0 * 100.0 + dur * 1000.0)
		for i in range(count):
			var t = float(i) / float(count)
			var freq = lerp(f0, f1, t)
			phase += TAU * freq / float(rate)
			var env = pow(1.0 - t, 1.65)
			var tone = sin(phase)
			var nz = rng.randf_range(-1.0, 1.0)
			var s = (tone * (1.0 - noise_mix) + nz * noise_mix) * env * amp
			var iv = int(clamp(s * 30000.0, -32767.0, 32767.0))
			data.encode_s16(i * 2, iv)
		var wav = AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = rate
		wav.stereo = false
		wav.data = data
		return wav

	func play_sfx(key: String) -> void:
		if not bank.has(key):
			return
		var p: AudioStreamPlayer = players[next_idx]
		next_idx = (next_idx + 1) % players.size()
		p.stream = bank[key]
		p.pitch_scale = randf_range(0.94, 1.06)
		p.play()

# ==============================================================================
# PLAYER CONTROLLER (UT2004 Physics + Multi-Part 3D Weapons)
# ==============================================================================
class UTPlayer extends CharacterBody3D:
	var arena: Node3D = null
	var team: int = 0
	var alive: bool = true
	var hp: int = 100
	var armor: int = 25
	var udamage_timer: float = 0.0
	var respawn_timer: float = 0.0

	var yaw: float = 0.0
	var pitch: float = 0.0
	var cam: Camera3D = null
	var weapon_pivot: Node3D = null
	var weapon_models: Array = []
	var muzzle_light: OmniLight3D = null
	var muzzle_timer: float = 0.0

	var current_weapon: int = 0
	var fire_cd: float = 0.0
	var recoil_z: float = 0.0
	var bob_t: float = 0.0

	var jumps_used: int = 0
	var dodge_cd: float = 0.0
	var kill_streak: int = 0
	var multi_kill: int = 0
	var multi_kill_timer: float = 0.0

	# Touch + Keyboard input state
	var touch_move: Vector2 = Vector2.ZERO
	var touch_fire: bool = false
	var touch_alt: bool = false

	func _ready() -> void:
		collision_layer = 2
		collision_mask = 1
		floor_max_angle = deg_to_rad(50.0)
		floor_snap_length = 0.35

		var col = CollisionShape3D.new()
		var cap = CapsuleShape3D.new()
		cap.radius = 0.42
		cap.height = 1.8
		col.shape = cap
		col.position = Vector3(0, 0.9, 0)
		add_child(col)

		cam = Camera3D.new()
		cam.position = Vector3(0, 1.56, 0)
		cam.fov = 88.0
		cam.far = 140.0
		add_child(cam)
		cam.current = true

		weapon_pivot = Node3D.new()
		weapon_pivot.position = Vector3(0.28, -0.26, -0.52)
		cam.add_child(weapon_pivot)

		muzzle_light = OmniLight3D.new()
		muzzle_light.position = Vector3(0, 0.05, -0.65)
		muzzle_light.omni_range = 7.5
		muzzle_light.light_energy = 0.0
		weapon_pivot.add_child(muzzle_light)

		_build_all_viewmodels()
		select_weapon(0)

	func _build_all_viewmodels() -> void:
		weapon_models.clear()
		# 0: Shock Rifle
		var w0 = Node3D.new()
		_vm_part(w0, Vector3(0, 0, -0.05), Vector3(0.11, 0.14, 0.72), arena.mat_dark_steel)
		_vm_part(w0, Vector3(0, 0.04, -0.22), Vector3(0.06, 0.05, 0.46), arena.mat_glow_purple)
		_vm_part(w0, Vector3(0, 0.09, -0.02), Vector3(0.04, 0.06, 0.22), arena.mat_wall)
		_vm_part(w0, Vector3(0, -0.06, -0.36), Vector3(0.08, 0.04, 0.24), arena.mat_wall)
		weapon_pivot.add_child(w0)
		weapon_models.append(w0)

		# 1: Flak Cannon
		var w1 = Node3D.new()
		var flk_yellow = StandardMaterial3D.new()
		flk_yellow.albedo_color = Color(0.92, 0.68, 0.10)
		flk_yellow.metallic = 0.65
		flk_yellow.roughness = 0.35
		_vm_part(w1, Vector3(0, -0.02, 0.0), Vector3(0.22, 0.18, 0.56), flk_yellow)
		_vm_part(w1, Vector3(-0.08, 0.02, -0.32), Vector3(0.06, 0.13, 0.26), arena.mat_dark_steel)
		_vm_part(w1, Vector3(0.08, 0.02, -0.32), Vector3(0.06, 0.13, 0.26), arena.mat_dark_steel)
		_vm_part(w1, Vector3(0, 0.01, -0.24), Vector3(0.08, 0.08, 0.18), arena.mat_glow_orange)
		weapon_pivot.add_child(w1)
		weapon_models.append(w1)

		# 2: Rocket Launcher
		var w2 = Node3D.new()
		var rkt_red = StandardMaterial3D.new()
		rkt_red.albedo_color = Color(0.55, 0.16, 0.14)
		rkt_red.metallic = 0.72
		rkt_red.roughness = 0.38
		_vm_part(w2, Vector3(0, 0.0, 0.02), Vector3(0.24, 0.24, 0.52), rkt_red)
		_vm_cyl(w2, Vector3(-0.055, 0.04, -0.30), 0.042, 0.42, arena.mat_dark_steel)
		_vm_cyl(w2, Vector3(0.055, 0.04, -0.30), 0.042, 0.42, arena.mat_dark_steel)
		_vm_cyl(w2, Vector3(0.0, -0.05, -0.30), 0.042, 0.42, arena.mat_dark_steel)
		_vm_part(w2, Vector3(0.0, 0.14, -0.10), Vector3(0.05, 0.04, 0.18), arena.mat_glow_red)
		weapon_pivot.add_child(w2)
		weapon_models.append(w2)

		# 3: Link Gun
		var w3 = Node3D.new()
		_vm_part(w3, Vector3(0, 0, -0.04), Vector3(0.14, 0.14, 0.62), arena.mat_dark_steel)
		_vm_part(w3, Vector3(-0.06, 0.02, -0.34), Vector3(0.03, 0.06, 0.30), arena.mat_glow_green)
		_vm_part(w3, Vector3(0.06, 0.02, -0.34), Vector3(0.03, 0.06, 0.30), arena.mat_glow_green)
		_vm_part(w3, Vector3(0, 0.08, -0.08), Vector3(0.08, 0.04, 0.24), arena.mat_glow_green)
		weapon_pivot.add_child(w3)
		weapon_models.append(w3)

	func _vm_part(parent: Node3D, pos: Vector3, sz: Vector3, mat: Material) -> void:
		var mi = MeshInstance3D.new()
		var bm = BoxMesh.new()
		bm.size = sz
		mi.mesh = bm
		mi.material_override = mat
		mi.position = pos
		parent.add_child(mi)

	func _vm_cyl(parent: Node3D, pos: Vector3, rad: float, h: float, mat: Material) -> void:
		var mi = MeshInstance3D.new()
		var cm = CylinderMesh.new()
		cm.top_radius = rad
		cm.bottom_radius = rad
		cm.height = h
		mi.mesh = cm
		mi.material_override = mat
		mi.position = pos
		mi.rotation_degrees = Vector3(90, 0, 0)
		parent.add_child(mi)

	func select_weapon(idx: int) -> void:
		current_weapon = clamp(idx, 0, 3)
		for i in range(weapon_models.size()):
			weapon_models[i].visible = (i == current_weapon)
		recoil_z = 0.16

	func respawn() -> void:
		alive = true
		hp = 100
		armor = 25
		udamage_timer = 0.0
		kill_streak = 0
		multi_kill = 0
		velocity = Vector3.ZERO
		global_position = arena.get_spawn_point(team)
		yaw = PI
		pitch = -0.04
		rotation.y = yaw
		cam.rotation.x = pitch

	func add_look(dx: float, dy: float) -> void:
		yaw -= dx
		pitch = clamp(pitch - dy, -1.42, 1.42)
		rotation.y = yaw
		cam.rotation.x = pitch

	func trigger_jump() -> void:
		if not alive:
			return
		if is_on_floor():
			velocity.y = 9.2
			jumps_used = 1
		elif jumps_used < 2:
			velocity.y = max(velocity.y * 0.35 + 8.6, 8.6)
			jumps_used = 2
			arena.sfx.play_sfx("dodge")

	func trigger_dodge() -> void:
		if not alive or dodge_cd > 0.0:
			return
		var input_dir = _get_move_input_world()
		if is_on_wall() and not is_on_floor():
			var wn = get_wall_normal()
			var kick = (wn + input_dir * 0.45).normalized()
			velocity.x = kick.x * 18.0
			velocity.z = kick.z * 18.0
			velocity.y = 7.4
			dodge_cd = 0.72
			arena.sfx.play_sfx("dodge")
			return
		if is_on_floor():
			var dir = input_dir if input_dir.length() > 0.1 else -global_transform.basis.z
			dir.y = 0.0
			dir = dir.normalized()
			velocity.x = dir.x * 19.5
			velocity.z = dir.z * 19.5
			velocity.y = 5.4
			dodge_cd = 0.85
			arena.sfx.play_sfx("dodge")

	func _get_move_input_world() -> Vector3:
		var ix = touch_move.x
		var iy = touch_move.y
		if Input.is_key_pressed(KEY_A):
			ix -= 1.0
		if Input.is_key_pressed(KEY_D):
			ix += 1.0
		if Input.is_key_pressed(KEY_W):
			iy -= 1.0
		if Input.is_key_pressed(KEY_S):
			iy += 1.0
		var v2 = Vector2(ix, iy)
		if v2.length() > 1.0:
			v2 = v2.normalized()
		var fwd = -global_transform.basis.z
		var right = global_transform.basis.x
		var res = right * v2.x - fwd * v2.y
		res.y = 0.0
		return res

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			add_look(event.relative.x * 0.0028, event.relative.y * 0.0028)
		elif event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_SPACE:
				trigger_jump()
			elif event.keycode == KEY_SHIFT:
				trigger_dodge()
			elif event.keycode == KEY_1:
				select_weapon(0)
			elif event.keycode == KEY_2:
				select_weapon(1)
			elif event.keycode == KEY_3:
				select_weapon(2)
			elif event.keycode == KEY_4:
				select_weapon(3)

	func _physics_process(delta: float) -> void:
		if not alive:
			respawn_timer -= delta
			if respawn_timer <= 0.0:
				respawn()
			return

		if udamage_timer > 0.0:
			udamage_timer = max(0.0, udamage_timer - delta)
		if dodge_cd > 0.0:
			dodge_cd = max(0.0, dodge_cd - delta)
		if fire_cd > 0.0:
			fire_cd = max(0.0, fire_cd - delta)
		if multi_kill_timer > 0.0:
			multi_kill_timer -= delta
			if multi_kill_timer <= 0.0:
				multi_kill = 0

		# Gravity
		if not is_on_floor():
			velocity.y -= 23.0 * delta
		else:
			jumps_used = 0

		# Arena movement
		var wish = _get_move_input_world()
		var max_spd = 11.4
		var accel = 13.0 if is_on_floor() else 3.2
		var target_vx = wish.x * max_spd
		var target_vz = wish.z * max_spd
		var hspd = Vector2(velocity.x, velocity.z).length()
		if is_on_floor() or wish.length() > 0.05:
			if is_on_floor() and hspd > max_spd + 1.0:
				# Preserve dodge momentum smoothly
				velocity.x = lerp(velocity.x, target_vx, delta * 5.0)
				velocity.z = lerp(velocity.z, target_vz, delta * 5.0)
			else:
				velocity.x = lerp(velocity.x, target_vx, clamp(delta * accel, 0.0, 1.0))
				velocity.z = lerp(velocity.z, target_vz, clamp(delta * accel, 0.0, 1.0))

		move_and_slide()
		arena.check_jump_pads(self)

		# Firing (Touch OR Mouse)
		var want_fire = touch_fire or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		var want_alt = touch_alt or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		if fire_cd <= 0.0:
			if want_fire:
				_fire_weapon(false)
			elif want_alt:
				_fire_weapon(true)

		# Weapon bob + recoil + strafe roll
		var move_ratio = clamp(Vector2(velocity.x, velocity.z).length() / max_spd, 0.0, 1.2)
		if is_on_floor() and move_ratio > 0.1:
			bob_t += delta * 11.5 * move_ratio
		recoil_z = lerp(recoil_z, 0.0, clamp(delta * 12.0, 0.0, 1.0))
		weapon_pivot.position = Vector3(
			0.28 + cos(bob_t * 0.5) * 0.014 * move_ratio,
			-0.26 + abs(sin(bob_t)) * 0.018 * move_ratio,
			-0.52 + recoil_z
		)
		var right_vel = velocity.dot(global_transform.basis.x)
		cam.rotation.z = lerp(cam.rotation.z, clamp(-right_vel * 0.004, -0.045, 0.045), delta * 8.0)

		if muzzle_timer > 0.0:
			muzzle_timer -= delta
			muzzle_light.light_energy = max(0.0, muzzle_timer * 55.0)
		else:
			muzzle_light.light_energy = 0.0

	func _fire_weapon(is_alt: bool) -> void:
		var mult = 2.0 if udamage_timer > 0.0 else 1.0
		var cam_pos = cam.global_position
		var cam_dir = -cam.global_transform.basis.z
		var muzzle_pos = weapon_pivot.global_position + cam_dir * 0.45

		if current_weapon == 0:
			# SHOCK RIFLE
			if not is_alt:
				fire_cd = 0.52
				recoil_z = 0.12
				_flash_muzzle(Color(0.75, 0.25, 1.0))
				arena.sfx.play_sfx("shock_fire")
				var hit = _raycast(cam_pos, cam_pos + cam_dir * 110.0, 1 | 2 | 4, true)
				var end_p = cam_pos + cam_dir * 110.0
				if not hit.is_empty():
					end_p = hit["position"]
					var col_obj = hit["collider"]
					if col_obj is UTShockCore:
						col_obj.detonate_combo(self, mult)
					elif col_obj is UTBot and col_obj.team != team:
						col_obj.apply_damage(int(45 * mult), self, "Shock Rifle", cam_dir * 7.5)
						if arena.hud != null:
							arena.hud.trigger_hitmarker()
				arena.spawn_beam(muzzle_pos, end_p, Color(0.78, 0.28, 1.0), 0.065, 0.16)
			else:
				fire_cd = 0.56
				recoil_z = 0.10
				_flash_muzzle(Color(0.65, 0.22, 1.0))
				arena.sfx.play_sfx("shock_fire")
				arena.spawn_shock_core(muzzle_pos + cam_dir * 0.4, cam_dir * 14.5, self)

		elif current_weapon == 1:
			# FLAK CANNON
			if not is_alt:
				fire_cd = 0.68
				recoil_z = 0.17
				_flash_muzzle(Color(1.0, 0.65, 0.15))
				arena.sfx.play_sfx("flak_fire")
				for i in range(8):
					var spread = Vector3(randf_range(-0.09, 0.09), randf_range(-0.07, 0.07), randf_range(-0.09, 0.09))
					var dir = (cam_dir + spread).normalized()
					arena.spawn_projectile(muzzle_pos, dir * 48.0, "flak", self, int(17 * mult), 0.0, 2)
			else:
				fire_cd = 0.82
				recoil_z = 0.19
				_flash_muzzle(Color(1.0, 0.55, 0.1))
				arena.sfx.play_sfx("flak_fire")
				var launch = (cam_dir + Vector3(0, 0.18, 0)).normalized() * 29.0
				arena.spawn_projectile(muzzle_pos, launch, "flak_shell", self, int(85 * mult), 5.2, 0)

		elif current_weapon == 2:
			# ROCKET LAUNCHER
			if not is_alt:
				fire_cd = 0.78
				recoil_z = 0.20
				_flash_muzzle(Color(1.0, 0.35, 0.12))
				arena.sfx.play_sfx("rocket_fire")
				arena.spawn_projectile(muzzle_pos + cam_dir * 0.35, cam_dir * 34.0, "rocket", self, int(92 * mult), 5.6, 0)
			else:
				fire_cd = 1.25
				recoil_z = 0.24
				_flash_muzzle(Color(1.0, 0.28, 0.08))
				arena.sfx.play_sfx("rocket_fire")
				for ang in [-0.08, 0.0, 0.08]:
					var rdir = cam_dir.rotated(Vector3.UP, ang)
					arena.spawn_projectile(muzzle_pos + rdir * 0.4, rdir * 32.0, "rocket", self, int(68 * mult), 4.8, 0)

		elif current_weapon == 3:
			# LINK GUN
			if not is_alt:
				fire_cd = 0.115
				recoil_z = 0.045
				_flash_muzzle(Color(0.2, 1.0, 0.35))
				arena.sfx.play_sfx("link_fire")
				arena.spawn_projectile(muzzle_pos, cam_dir * 52.0, "plasma", self, int(22 * mult), 0.0, 0)
			else:
				fire_cd = 0.09
				recoil_z = 0.025
				_flash_muzzle(Color(0.2, 1.0, 0.4))
				arena.sfx.play_sfx("link_fire")
				var hit2 = _raycast(cam_pos, cam_pos + cam_dir * 26.0, 1 | 2, false)
				var end2 = cam_pos + cam_dir * 26.0
				if not hit2.is_empty():
					end2 = hit2["position"]
					var co = hit2["collider"]
					if co is UTBot and co.team != team:
						co.apply_damage(int(18 * mult), self, "Link Beam", cam_dir * 2.5)
						if arena.hud != null:
							arena.hud.trigger_hitmarker()
				arena.spawn_beam(muzzle_pos, end2, Color(0.22, 1.0, 0.38), 0.05, 0.10)

	func _flash_muzzle(col: Color) -> void:
		muzzle_light.light_color = col
		muzzle_timer = 0.08

	func _raycast(from_pos: Vector3, to_pos: Vector3, mask: int, check_areas: bool) -> Dictionary:
		var space = get_world_3d().direct_space_state
		var q = PhysicsRayQueryParameters3D.create(from_pos, to_pos, mask)
		q.exclude = [get_rid()]
		q.collide_with_areas = check_areas
		return space.intersect_ray(q)

	func apply_damage(dmg: int, attacker, weapon_name: String, impulse: Vector3) -> void:
		if not alive:
			return
		velocity += impulse
		var absorb = min(armor, int(round(float(dmg) * 0.6)))
		armor -= absorb
		hp -= (dmg - absorb)
		if arena.hud != null:
			arena.hud.flash_screen(Color(1.0, 0.12, 0.08, 0.38))
		if hp <= 0:
			hp = 0
			alive = false
			respawn_timer = 2.6
			arena.register_kill(attacker, self, weapon_name)
			if arena.hud != null:
				arena.hud.show_banner("FRAGGED! RESPAWNING...", Color(1.0, 0.25, 0.2))

	func register_player_kill(weapon_name: String) -> void:
		kill_streak += 1
		multi_kill += 1
		multi_kill_timer = 4.2
		if arena.hud == null:
			return
		if not arena.first_blood_done:
			arena.first_blood_done = true
			arena.hud.show_banner("FIRST BLOOD!", Color(1.0, 0.25, 0.18))
		elif weapon_name == "Shock Combo":
			arena.hud.show_banner("SHOCK COMBO!", Color(0.85, 0.35, 1.0))
		elif multi_kill == 2:
			arena.hud.show_banner("DOUBLE KILL!", Color(1.0, 0.72, 0.18))
		elif multi_kill == 3:
			arena.hud.show_banner("MULTI KILL!", Color(1.0, 0.45, 0.15))
		elif multi_kill >= 4:
			arena.hud.show_banner("MONSTER KILL!", Color(1.0, 0.18, 0.35))
		elif kill_streak == 5:
			arena.hud.show_banner("KILLING SPREE!", Color(0.25, 0.92, 1.0))
		elif kill_streak == 10:
			arena.hud.show_banner("UNSTOPPABLE!", Color(1.0, 0.85, 0.15))

# ==============================================================================
# ANIMATED 3D SOLDIER BOT (Mixamo Soldier.glb + Skeletal Animations + AI)
# ==============================================================================
class UTBot extends CharacterBody3D:
	var arena: Node3D = null
	var bot_name: String = "Bot"
	var team: int = 1
	var alive: bool = true
	var hp: int = 100
	var armor: int = 20
	var udamage_timer: float = 0.0
	var respawn_timer: float = 0.0

	var visual_root: Node3D = null
	var anim_player: AnimationPlayer = null
	var anim_idle: String = ""
	var anim_walk: String = ""
	var anim_run: String = ""
	var current_anim: String = ""

	var strafe_dir: float = 1.0
	var strafe_timer: float = 1.2
	var fire_cd: float = 0.7
	var jump_cd: float = 1.0
	var waypoint: Vector3 = Vector3.ZERO
	var waypoint_timer: float = 0.0

	func _ready() -> void:
		collision_layer = 2
		collision_mask = 1
		floor_max_angle = deg_to_rad(50.0)
		floor_snap_length = 0.35

		var col = CollisionShape3D.new()
		var cap = CapsuleShape3D.new()
		cap.radius = 0.44
		cap.height = 1.82
		col.shape = cap
		col.position = Vector3(0, 0.91, 0)
		add_child(col)

		visual_root = Node3D.new()
		add_child(visual_root)
		_build_visual()

	func _build_visual() -> void:
		var glow_mat = arena.mat_glow_red if team == 1 else arena.mat_glow_cyan
		var tint = Color(1.0, 0.74, 0.74) if team == 1 else Color(0.74, 0.88, 1.0)

		if arena.soldier_scene != null:
			var model = arena.soldier_scene.instantiate()
			model.scale = Vector3(1.06, 1.06, 1.06)
			visual_root.add_child(model)
			_tint_meshes(model, tint)
			anim_player = _find_anim_player(model)
			if anim_player != null:
				var names = anim_player.get_animation_list()
				for n in names:
					var an = anim_player.get_animation(n)
					if an != null:
						an.loop_mode = Animation.LOOP_LINEAR
					var low = n.to_lower()
					if low.find("run") != -1:
						anim_run = n
					elif low.find("walk") != -1:
						anim_walk = n
					elif low.find("idle") != -1:
						anim_idle = n
				if anim_run == "" and names.size() > 0:
					anim_run = names[0]
				if anim_idle == "":
					anim_idle = anim_run
		else:
			# Fallback multi-part articulated cyber-soldier (never a capsule!)
			var body_mat = StandardMaterial3D.new()
			body_mat.albedo_color = Color(0.32, 0.14, 0.14) if team == 1 else Color(0.14, 0.22, 0.36)
			body_mat.metallic = 0.75
			body_mat.roughness = 0.32
			_part(visual_root, Vector3(0, 1.15, 0), Vector3(0.56, 0.68, 0.34), body_mat)
			_part(visual_root, Vector3(0, 1.66, 0), Vector3(0.32, 0.34, 0.34), body_mat)
			_part(visual_root, Vector3(-0.16, 0.45, 0), Vector3(0.20, 0.85, 0.22), body_mat)
			_part(visual_root, Vector3(0.16, 0.45, 0), Vector3(0.20, 0.85, 0.22), body_mat)
			_part(visual_root, Vector3(-0.38, 1.15, 0), Vector3(0.18, 0.68, 0.20), body_mat)
			_part(visual_root, Vector3(0.38, 1.15, -0.15), Vector3(0.18, 0.62, 0.20), body_mat)

		# UT2004 glowing team shoulder/chest beacons + 3D sci-fi rifle
		_part(visual_root, Vector3(0, 1.68, -0.17), Vector3(0.24, 0.08, 0.06), glow_mat)
		_part(visual_root, Vector3(-0.34, 1.44, 0.0), Vector3(0.12, 0.08, 0.18), glow_mat)
		_part(visual_root, Vector3(0.34, 1.44, 0.0), Vector3(0.12, 0.08, 0.18), glow_mat)
		_part(visual_root, Vector3(0.24, 1.20, -0.45), Vector3(0.10, 0.12, 0.65), arena.mat_dark_steel)
		_part(visual_root, Vector3(0.24, 1.24, -0.58), Vector3(0.05, 0.04, 0.32), glow_mat)

	func _part(parent: Node3D, pos: Vector3, sz: Vector3, mat: Material) -> void:
		var mi = MeshInstance3D.new()
		var bm = BoxMesh.new()
		bm.size = sz
		mi.mesh = bm
		mi.material_override = mat
		mi.position = pos
		parent.add_child(mi)

	func _tint_meshes(node: Node, tint: Color) -> void:
		if node is MeshInstance3D:
			var mi: MeshInstance3D = node
			if mi.mesh != null:
				for s in range(mi.mesh.get_surface_count()):
					var orig = mi.get_active_material(s)
					if orig is StandardMaterial3D:
						var dup = orig.duplicate()
						dup.albedo_color = dup.albedo_color * tint
						mi.set_surface_override_material(s, dup)
		for c in node.get_children():
			_tint_meshes(c, tint)

	func _find_anim_player(node: Node) -> AnimationPlayer:
		if node is AnimationPlayer:
			return node
		for c in node.get_children():
			var found = _find_anim_player(c)
			if found != null:
				return found
		return null

	func _play_anim(name: String) -> void:
		if anim_player == null or name == "" or current_anim == name:
			return
		current_anim = name
		anim_player.play(name, 0.18)

	func respawn() -> void:
		alive = true
		hp = 100
		armor = 20
		udamage_timer = 0.0
		velocity = Vector3.ZERO
		global_position = arena.get_spawn_point(team) + Vector3(randf_range(-2.2, 2.2), 0.1, randf_range(-2.2, 2.2))
		visual_root.visible = true
		visual_root.rotation = Vector3.ZERO
		collision_layer = 2
		_pick_new_waypoint()

	func _pick_new_waypoint() -> void:
		var spots = [
			Vector3(-12.5, 0.2, -14.0),
			Vector3(12.5, 0.2, 14.0),
			Vector3(-14.0, 0.2, 0.0),
			Vector3(14.0, 0.2, 0.0),
			Vector3(0.0, 4.6, 0.0),
			Vector3(-19.5, 4.6, 0.0),
			Vector3(19.5, 4.6, 0.0),
			Vector3(0.0, 4.6, -22.5),
			Vector3(0.0, 4.6, 22.5)
		]
		waypoint = spots[randi() % spots.size()]
		waypoint_timer = randf_range(3.5, 6.0)

	func _find_target():
		var best = null
		var best_dist = 999.0
		var candidates: Array = [arena.player]
		for b in arena.bots:
			candidates.append(b)
		for c in candidates:
			if not is_instance_valid(c) or c == self or not c.alive or c.team == team:
				continue
			var d = global_position.distance_to(c.global_position)
			if d < best_dist:
				best_dist = d
				best = c
		return best

	func _has_los(target) -> bool:
		var space = get_world_3d().direct_space_state
		var a = global_position + Vector3(0, 1.45, 0)
		var b = target.global_position + Vector3(0, 1.25, 0)
		var q = PhysicsRayQueryParameters3D.create(a, b, 1)
		var hit = space.intersect_ray(q)
		return hit.is_empty()

	func _physics_process(delta: float) -> void:
		if not alive:
			respawn_timer -= delta
			visual_root.rotation.x = lerp(visual_root.rotation.x, -1.45, delta * 6.0)
			if respawn_timer <= 0.0:
				respawn()
			return

		if udamage_timer > 0.0:
			udamage_timer = max(0.0, udamage_timer - delta)
		if fire_cd > 0.0:
			fire_cd -= delta
		if jump_cd > 0.0:
			jump_cd -= delta
		strafe_timer -= delta
		if strafe_timer <= 0.0:
			strafe_timer = randf_range(0.8, 1.8)
			strafe_dir = -strafe_dir

		if not is_on_floor():
			velocity.y -= 23.0 * delta

		var target = _find_target()
		var see_target = false
		var move_dir = Vector3.ZERO

		if target != null:
			see_target = _has_los(target)

		if target != null and see_target:
			var to_t = target.global_position - global_position
			var flat_t = Vector3(to_t.x, 0.0, to_t.z)
			var dist = flat_t.length()
			var fwd = flat_t.normalized() if dist > 0.05 else -global_transform.basis.z
			var right = Vector3(-fwd.z, 0.0, fwd.x)

			# Smoothly face target
			var desired_yaw = atan2(-fwd.x, -fwd.z)
			rotation.y = lerp_angle(rotation.y, desired_yaw, clamp(delta * 10.0, 0.0, 1.0))

			# Strafe + maintain optimal arena range
			move_dir = right * strafe_dir * 0.85
			if dist > 15.0:
				move_dir += fwd * 0.75
			elif dist < 6.5:
				move_dir -= fwd * 0.55

			# Occasional combat jump
			if is_on_floor() and jump_cd <= 0.0 and randf() < 0.03:
				velocity.y = 8.8
				jump_cd = randf_range(1.5, 3.0)

			# Shoot!
			if fire_cd <= 0.0 and dist < 44.0:
				_fire_at(target)
		else:
			waypoint_timer -= delta
			if waypoint_timer <= 0.0 or global_position.distance_to(waypoint) < 2.5:
				_pick_new_waypoint()
			var to_w = waypoint - global_position
			to_w.y = 0.0
			if to_w.length() > 0.2:
				move_dir = to_w.normalized()
				var wyaw = atan2(-move_dir.x, -move_dir.z)
				rotation.y = lerp_angle(rotation.y, wyaw, clamp(delta * 7.0, 0.0, 1.0))

		# Pit avoidance steering (keep bots from walking straight into acid)
		if global_position.y < 2.2:
			var next_p = global_position + move_dir * 2.2
			if abs(next_p.x) < 7.8 and abs(next_p.z) < 9.8:
				var away = Vector3(global_position.x, 0.0, global_position.z).normalized()
				var tang = Vector3(-away.z, 0.0, away.x) * strafe_dir
				move_dir = (away * 0.7 + tang * 0.8).normalized()

		if move_dir.length() > 0.05:
			move_dir = move_dir.normalized()
			velocity.x = lerp(velocity.x, move_dir.x * 8.4, clamp(delta * 8.0, 0.0, 1.0))
			velocity.z = lerp(velocity.z, move_dir.z * 8.4, clamp(delta * 8.0, 0.0, 1.0))
			_play_anim(anim_run)
		else:
			velocity.x = lerp(velocity.x, 0.0, clamp(delta * 8.0, 0.0, 1.0))
			velocity.z = lerp(velocity.z, 0.0, clamp(delta * 8.0, 0.0, 1.0))
			_play_anim(anim_idle)

		move_and_slide()
		arena.check_jump_pads(self)

	func _fire_at(target) -> void:
		fire_cd = randf_range(0.62, 1.15)
		var origin = global_position + Vector3(0, 1.32, 0)
		var aim = (target.global_position + Vector3(0, 1.15, 0) - origin)
		var dist = aim.length()
		var dir = aim.normalized()
		# Fair human-like spread
		dir += Vector3(randf_range(-0.06, 0.06), randf_range(-0.04, 0.04), randf_range(-0.06, 0.06))
		dir = dir.normalized()
		var mult = 2.0 if udamage_timer > 0.0 else 1.0

		if dist > 18.0 and randf() < 0.45:
			arena.spawn_projectile(origin + dir * 0.7, dir * 30.0, "rocket", self, int(34 * mult), 4.2, 0)
		else:
			arena.spawn_projectile(origin + dir * 0.7, dir * 42.0, "plasma", self, int(14 * mult), 0.0, 0)

	func apply_damage(dmg: int, attacker, weapon_name: String, impulse: Vector3) -> void:
		if not alive:
			return
		velocity += impulse
		var absorb = min(armor, int(round(float(dmg) * 0.5)))
		armor -= absorb
		hp -= (dmg - absorb)
		if hp <= 0:
			hp = 0
			alive = false
			respawn_timer = 3.0
			collision_layer = 0
			arena.register_kill(attacker, self, weapon_name)
			var col = Color(1.0, 0.25, 0.18) if team == 1 else Color(0.2, 0.85, 1.0)
			var fx = UTExplosionFX.new()
			fx.setup(global_position + Vector3(0, 1.0, 0), 1.9, col, 0.30)
			arena.add_child(fx)
			arena.effects.append(fx)

# ==============================================================================
# PROJECTILES, SHOCK CORE & VFX
# ==============================================================================
class UTProjectile extends Node3D:
	var arena: Node3D = null
	var vel: Vector3 = Vector3.ZERO
	var kind: String = "plasma"
	var attacker = null
	var dmg: int = 20
	var splash: float = 0.0
	var bounces: int = 0
	var life: float = 4.0

	func setup(p: Vector3, v: Vector3, k: String, att, d: int, sp: float, bnc: int) -> void:
		position = p
		vel = v
		kind = k
		attacker = att
		dmg = d
		splash = sp
		bounces = bnc

		var mi = MeshInstance3D.new()
		if kind == "rocket":
			var cm = CylinderMesh.new()
			cm.top_radius = 0.07
			cm.bottom_radius = 0.09
			cm.height = 0.55
			mi.mesh = cm
			mi.rotation_degrees = Vector3(90, 0, 0)
			mi.material_override = arena.mat_glow_orange
		elif kind == "flak":
			var bm = BoxMesh.new()
			bm.size = Vector3(0.11, 0.07, 0.24)
			mi.mesh = bm
			mi.material_override = arena.mat_glow_orange
		elif kind == "flak_shell":
			var sm = SphereMesh.new()
			sm.radius = 0.16
			sm.height = 0.32
			mi.mesh = sm
			mi.material_override = arena.mat_glow_orange
		else:
			var sm2 = SphereMesh.new()
			sm2.radius = 0.13
			sm2.height = 0.26
			mi.mesh = sm2
			mi.material_override = arena.mat_glow_green if (attacker == arena.player or attacker.team == 0) else arena.mat_glow_red
		add_child(mi)

	func step_projectile(delta: float) -> bool:
		life -= delta
		if life <= 0.0:
			return false
		if kind == "flak" or kind == "flak_shell":
			vel.y -= 16.0 * delta

		var from_p = global_position
		var to_p = from_p + vel * delta
		var space = get_world_3d().direct_space_state
		var q = PhysicsRayQueryParameters3D.create(from_p, to_p, 1 | 2)
		if is_instance_valid(attacker):
			q.exclude = [attacker.get_rid()]
		var hit = space.intersect_ray(q)

		if not hit.is_empty():
			var hp_pos: Vector3 = hit["position"]
			var hn: Vector3 = hit["normal"]
			var col_obj = hit["collider"]
			if col_obj is UTBot or col_obj is UTPlayer:
				if splash > 0.0:
					arena.spawn_explosion(hp_pos, splash, Color(1.0, 0.5, 0.12), dmg, attacker, _wep_label(), 12.0)
				else:
					if is_instance_valid(attacker) and col_obj.team != attacker.team:
						col_obj.apply_damage(dmg, attacker, _wep_label(), vel.normalized() * 4.5)
						if attacker == arena.player and arena.hud != null:
							arena.hud.trigger_hitmarker()
				return false
			else:
				if bounces > 0:
					bounces -= 1
					vel = vel.bounce(hn) * 0.85
					global_position = hp_pos + hn * 0.1
					return true
				if splash > 0.0:
					arena.spawn_explosion(hp_pos + hn * 0.15, splash, Color(1.0, 0.52, 0.12), dmg, attacker, _wep_label(), 13.5)
				else:
					var fx = UTExplosionFX.new()
					fx.setup(hp_pos, 0.45, Color(0.4, 1.0, 0.5) if kind == "plasma" else Color(1.0, 0.65, 0.2), 0.14)
					arena.add_child(fx)
					arena.effects.append(fx)
				return false

		global_position = to_p
		return true

	func _wep_label() -> String:
		if kind == "rocket":
			return "Rocket Launcher"
		if kind == "flak":
			return "Flak Cannon"
		if kind == "flak_shell":
			return "Flak Shell"
		return "Link Gun"

class UTShockCore extends Area3D:
	var arena: Node3D = null
	var vel: Vector3 = Vector3.ZERO
	var attacker = null
	var life: float = 5.0

	func setup(p: Vector3, v: Vector3, att) -> void:
		position = p
		vel = v
		attacker = att
		collision_layer = 4
		collision_mask = 0

		var cs = CollisionShape3D.new()
		var sp = SphereShape3D.new()
		sp.radius = 0.72
		cs.shape = sp
		add_child(cs)

		var mi = MeshInstance3D.new()
		var sm = SphereMesh.new()
		sm.radius = 0.34
		sm.height = 0.68
		mi.mesh = sm
		mi.material_override = arena.mat_glow_purple
		add_child(mi)

	func detonate_combo(detonator, mult: float) -> void:
		arena.spawn_explosion(global_position, 8.2, Color(0.78, 0.25, 1.0), int(135 * mult), detonator, "Shock Combo", 16.5)
		life = -1.0

	func step_core(delta: float) -> bool:
		life -= delta
		if life <= 0.0:
			return false
		var from_p = global_position
		var to_p = from_p + vel * delta
		var space = get_world_3d().direct_space_state
		var q = PhysicsRayQueryParameters3D.create(from_p, to_p, 1 | 2)
		if is_instance_valid(attacker):
			q.exclude = [attacker.get_rid()]
		var hit = space.intersect_ray(q)
		if not hit.is_empty():
			arena.spawn_explosion(hit["position"], 3.4, Color(0.75, 0.25, 1.0), 48, attacker, "Shock Core", 8.0)
			return false
		global_position = to_p
		rotation.y += delta * 5.0
		return true

class UTBeamFX extends Node3D:
	var life: float = 0.16
	var max_life: float = 0.16
	var mat: StandardMaterial3D = null

	func setup(a: Vector3, b: Vector3, col: Color, rad: float, dur: float) -> void:
		life = dur
		max_life = dur
		var dist = a.distance_to(b)
		if dist < 0.05:
			return
		var mi = MeshInstance3D.new()
		var cm = CylinderMesh.new()
		cm.top_radius = rad
		cm.bottom_radius = rad
		cm.height = dist
		mi.mesh = cm
		mat = StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = col
		mi.material_override = mat
		mi.rotation_degrees = Vector3(90, 0, 0)
		add_child(mi)
		position = (a + b) * 0.5
		var dir = (b - a).normalized()
		var up = Vector3.UP if abs(dir.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
		look_at(b, up)

	func step_fx(delta: float) -> bool:
		life -= delta
		if life <= 0.0:
			return false
		if mat != null:
			mat.albedo_color.a = clamp(life / max_life, 0.0, 1.0)
		return true

class UTExplosionFX extends Node3D:
	var life: float = 0.35
	var max_life: float = 0.35
	var target_r: float = 3.0
	var mat: StandardMaterial3D = null
	var mesh_node: MeshInstance3D = null

	func setup(p: Vector3, rad: float, col: Color, dur: float) -> void:
		position = p
		target_r = rad
		life = dur
		max_life = dur
		mesh_node = MeshInstance3D.new()
		var sm = SphereMesh.new()
		sm.radius = 0.45
		sm.height = 0.9
		mesh_node.mesh = sm
		mat = StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(col.r, col.g, col.b, 0.85)
		mesh_node.material_override = mat
		add_child(mesh_node)

	func step_fx(delta: float) -> bool:
		life -= delta
		if life <= 0.0:
			return false
		var prog = 1.0 - (life / max_life)
		var sc = lerp(0.35, target_r * 1.45, prog)
		mesh_node.scale = Vector3(sc, sc, sc)
		mat.albedo_color.a = clamp((1.0 - prog) * 0.82, 0.0, 1.0)
		return true

# ==============================================================================
# UT2004 METALLIC MOBILE HUD + RESPONSIVE MULTI-TOUCH CONTROLS
# ==============================================================================
class UTHUD extends CanvasLayer:
	var arena: Node3D = null
	var root: Control = null

	var score_lbl: Label = null
	var fps_lbl: Label = null
	var status_lbl: Label = null
	var banner_lbl: Label = null
	var killfeed_lbl: Label = null
	var flash_rect: ColorRect = null

	var hp_bar: ProgressBar = null
	var armor_bar: ProgressBar = null

	var joy_center: Vector2 = Vector2(165, 540)
	var joy_radius: float = 95.0
	var joy_knob: Vector2 = Vector2.ZERO
	var move_finger: int = -1
	var look_finger: int = -1
	var fire_finger: int = -1
	var alt_finger: int = -1

	var btn_rects: Dictionary = {}
	var hitmarker_timer: float = 0.0
	var banner_timer: float = 0.0
	var flash_alpha: float = 0.0
	var flash_color: Color = Color(1, 0, 0, 0)
	var killfeed_lines: Array = []

	func _ready() -> void:
		root = Control.new()
		root.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.draw.connect(_on_draw_hud)
		add_child(root)

		flash_rect = ColorRect.new()
		flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		flash_rect.color = Color(1, 0, 0, 0)
		flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(flash_rect)

		score_lbl = _make_label(22, Color(0.92, 0.96, 1.0))
		score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		score_lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
		score_lbl.offset_top = 12
		root.add_child(score_lbl)

		fps_lbl = _make_label(16, Color(0.35, 1.0, 0.55))
		fps_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		fps_lbl.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		fps_lbl.offset_left = -160
		fps_lbl.offset_right = -18
		fps_lbl.offset_top = 14
		root.add_child(fps_lbl)

		killfeed_lbl = _make_label(15, Color(0.88, 0.92, 0.98))
		killfeed_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		killfeed_lbl.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		killfeed_lbl.offset_left = -380
		killfeed_lbl.offset_right = -18
		killfeed_lbl.offset_top = 46
		root.add_child(killfeed_lbl)

		banner_lbl = _make_label(34, Color(1.0, 0.78, 0.2))
		banner_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		banner_lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
		banner_lbl.offset_top = 82
		root.add_child(banner_lbl)

		status_lbl = _make_label(18, Color(0.95, 0.97, 1.0))
		status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status_lbl.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		status_lbl.offset_top = -44
		root.add_child(status_lbl)

		hp_bar = _make_bar(Color(0.15, 0.85, 0.98))
		armor_bar = _make_bar(Color(1.0, 0.72, 0.15))
		root.add_child(hp_bar)
		root.add_child(armor_bar)

		_layout_controls()

	func _make_label(sz: int, col: Color) -> Label:
		var l = Label.new()
		l.add_theme_font_size_override("font_size", sz)
		l.add_theme_color_override("font_color", col)
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override("shadow_offset_x", 2)
		l.add_theme_constant_override("shadow_offset_y", 2)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return l

	func _make_bar(fill_col: Color) -> ProgressBar:
		var pb = ProgressBar.new()
		pb.show_percentage = false
		pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bg = StyleBoxFlat.new()
		bg.bg_color = Color(0.06, 0.08, 0.12, 0.75)
		bg.border_color = Color(0.45, 0.55, 0.68, 0.65)
		bg.set_border_width_all(1)
		bg.set_corner_radius_all(4)
		var fg = StyleBoxFlat.new()
		fg.bg_color = fill_col
		fg.set_corner_radius_all(3)
		pb.add_theme_stylebox_override("background", bg)
		pb.add_theme_stylebox_override("fill", fg)
		return pb

	func _layout_controls() -> void:
		var vs = get_viewport().get_visible_rect().size
		var w = vs.x
		var h = vs.y
		joy_center = Vector2(w * 0.13, h * 0.75)
		joy_radius = clamp(h * 0.135, 72.0, 110.0)

		hp_bar.position = Vector2(w * 0.5 - 170, h - 72)
		hp_bar.size = Vector2(160, 16)
		armor_bar.position = Vector2(w * 0.5 + 10, h - 72)
		armor_bar.size = Vector2(160, 16)

		var bw = clamp(w * 0.085, 86.0, 118.0)
		var bh = clamp(h * 0.125, 68.0, 92.0)
		var rx = w - bw - 22.0
		var by = h - bh - 24.0

		btn_rects["fire"] = Rect2(rx, by, bw, bh)
		btn_rects["alt"] = Rect2(rx - bw - 14.0, by, bw, bh)
		btn_rects["jump"] = Rect2(rx, by - bh - 14.0, bw, bh * 0.82)
		btn_rects["dodge"] = Rect2(rx - bw - 14.0, by - bh - 14.0, bw, bh * 0.82)

		var ww = clamp(w * 0.062, 66.0, 88.0)
		var wh = 42.0
		var wy = by - bh * 2.0 - 10.0
		var start_wx = w - (ww * 4.0 + 30.0) - 22.0
		for i in range(4):
			btn_rects["w%d" % i] = Rect2(start_wx + i * (ww + 10.0), wy, ww, wh)

	func trigger_hitmarker() -> void:
		hitmarker_timer = 0.16
		arena.sfx.play_sfx("hit")

	func show_banner(txt: String, col: Color) -> void:
		banner_lbl.text = txt
		banner_lbl.add_theme_color_override("font_color", col)
		banner_timer = 2.2

	func flash_screen(col: Color) -> void:
		flash_color = col
		flash_alpha = col.a

	func add_killfeed(kname: String, _kteam: int, vname: String, _vteam: int, wep: String) -> void:
		killfeed_lines.append("%s  [%s]  %s" % [kname, wep, vname])
		if killfeed_lines.size() > 4:
			killfeed_lines.pop_front()
		killfeed_lbl.text = "\n".join(killfeed_lines)

	func _input(event: InputEvent) -> void:
		var vs = get_viewport().get_visible_rect().size
		if event is InputEventScreenTouch:
			var idx = event.index
			var pos = event.position
			if event.pressed:
				if btn_rects["fire"].has_point(pos):
					fire_finger = idx
					arena.player.touch_fire = true
					return
				if btn_rects["alt"].has_point(pos):
					alt_finger = idx
					arena.player.touch_alt = true
					return
				if btn_rects["jump"].has_point(pos):
					arena.player.trigger_jump()
					return
				if btn_rects["dodge"].has_point(pos):
					arena.player.trigger_dodge()
					return
				for i in range(4):
					if btn_rects["w%d" % i].has_point(pos):
						arena.player.select_weapon(i)
						return
				if pos.x < vs.x * 0.42 and move_finger == -1:
					move_finger = idx
					_update_joystick(pos)
				elif look_finger == -1:
					look_finger = idx
			else:
				if idx == move_finger:
					move_finger = -1
					joy_knob = Vector2.ZERO
					arena.player.touch_move = Vector2.ZERO
				if idx == look_finger:
					look_finger = -1
				if idx == fire_finger:
					fire_finger = -1
					arena.player.touch_fire = false
				if idx == alt_finger:
					alt_finger = -1
					arena.player.touch_alt = false

		elif event is InputEventScreenDrag:
			var idx2 = event.index
			if idx2 == move_finger:
				_update_joystick(event.position)
			elif idx2 == look_finger or idx2 == fire_finger or idx2 == alt_finger:
				arena.player.add_look(event.relative.x * 0.0042, event.relative.y * 0.0042)

	func _update_joystick(pos: Vector2) -> void:
		var diff = pos - joy_center
		if diff.length() > joy_radius:
			diff = diff.normalized() * joy_radius
		joy_knob = diff
		arena.player.touch_move = diff / joy_radius

	func _process(delta: float) -> void:
		_layout_controls()
		if hitmarker_timer > 0.0:
			hitmarker_timer = max(0.0, hitmarker_timer - delta)
		if banner_timer > 0.0:
			banner_timer -= delta
			if banner_timer <= 0.0:
				banner_lbl.text = ""
		if flash_alpha > 0.0:
			flash_alpha = max(0.0, flash_alpha - delta * 1.1)
			flash_rect.color = Color(flash_color.r, flash_color.g, flash_color.b, flash_alpha)

		var mins = int(arena.match_time) / 60
		var secs = int(arena.match_time) % 60
		score_lbl.text = "BLUE  %d   |   DM-DECK17  %02d:%02d   |   %d  RED" % [arena.score_blue, mins, secs, arena.score_red]
		fps_lbl.text = "FPS: %d" % Engine.get_frames_per_second()

		var p = arena.player
		if p != null:
			hp_bar.value = clamp(p.hp, 0, 100)
			armor_bar.value = clamp(p.armor, 0, 100)
			var wnames = ["SHOCK RIFLE", "FLAK CANNON", "ROCKET LAUNCHER", "LINK GUN"]
			var ud = "  |  2X DMG %.0fs" % p.udamage_timer if p.udamage_timer > 0.0 else ""
			status_lbl.text = "HP %d   |   ARMOR %d   |   %s%s" % [p.hp, p.armor, wnames[p.current_weapon], ud]

		root.queue_redraw()

	func _on_draw_hud() -> void:
		var vs = get_viewport().get_visible_rect().size
		var c = vs * 0.5
		var font = ThemeDB.fallback_font

		# Dynamic UT2004 crosshair
		var c_col = Color(0.78, 0.35, 1.0)
		if arena.player.current_weapon == 1:
			c_col = Color(1.0, 0.72, 0.15)
		elif arena.player.current_weapon == 2:
			c_col = Color(1.0, 0.32, 0.22)
		elif arena.player.current_weapon == 3:
			c_col = Color(0.22, 1.0, 0.42)
		root.draw_arc(c, 11.0, 0.0, TAU, 24, Color(c_col.r, c_col.g, c_col.b, 0.75), 1.8)
		root.draw_line(c + Vector2(-17, 0), c + Vector2(-6, 0), c_col, 2.0)
		root.draw_line(c + Vector2(6, 0), c + Vector2(17, 0), c_col, 2.0)
		root.draw_line(c + Vector2(0, -17), c + Vector2(0, -6), c_col, 2.0)
		root.draw_line(c + Vector2(0, 6), c + Vector2(0, 17), c_col, 2.0)
		root.draw_circle(c, 2.2, Color.WHITE)

		if hitmarker_timer > 0.0:
			var hc = Color(1.0, 0.22, 0.15, clamp(hitmarker_timer * 6.0, 0.0, 1.0))
			root.draw_line(c + Vector2(-12, -12), c + Vector2(-5, -5), hc, 2.8)
			root.draw_line(c + Vector2(12, -12), c + Vector2(5, -5), hc, 2.8)
			root.draw_line(c + Vector2(-12, 12), c + Vector2(-5, 5), hc, 2.8)
			root.draw_line(c + Vector2(12, 12), c + Vector2(5, 5), hc, 2.8)

		# Sleek translucent virtual joystick
		root.draw_circle(joy_center, joy_radius, Color(0.06, 0.09, 0.14, 0.36))
		root.draw_arc(joy_center, joy_radius, 0.0, TAU, 36, Color(0.25, 0.85, 1.0, 0.55), 2.2)
		root.draw_circle(joy_center + joy_knob, joy_radius * 0.36, Color(0.25, 0.85, 1.0, 0.58))
		root.draw_arc(joy_center + joy_knob, joy_radius * 0.36, 0.0, TAU, 24, Color(0.9, 0.98, 1.0, 0.85), 2.0)

		# Touch action buttons
		_draw_btn(btn_rects["fire"], "FIRE", Color(0.95, 0.22, 0.18), arena.player.touch_fire, font)
		_draw_btn(btn_rects["alt"], "ALT", Color(0.72, 0.25, 0.98), arena.player.touch_alt, font)
		_draw_btn(btn_rects["jump"], "JUMP", Color(0.18, 0.78, 0.96), false, font)
		_draw_btn(btn_rects["dodge"], "DODGE", Color(0.98, 0.65, 0.14), false, font)

		var wlabels = ["1:SHK", "2:FLK", "3:RKT", "4:LNK"]
		for i in range(4):
			var active = (arena.player.current_weapon == i)
			_draw_btn(btn_rects["w%d" % i], wlabels[i], Color(0.25, 0.88, 1.0) if active else Color(0.45, 0.52, 0.64), active, font)

	func _draw_btn(r: Rect2, txt: String, col: Color, pressed: bool, font: Font) -> void:
		var bg_a = 0.52 if pressed else 0.26
		root.draw_rect(r, Color(col.r * 0.35, col.g * 0.35, col.b * 0.35, bg_a), true)
		root.draw_rect(r, Color(col.r, col.g, col.b, 0.85), false, 2.2)
		var fsize = 16
		var tsz = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fsize)
		var tpos = Vector2(r.position.x + (r.size.x - tsz.x) * 0.5, r.position.y + (r.size.y + fsize * 0.7) * 0.5)
		root.draw_string(font, tpos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0.96, 0.98, 1.0))
