extends Node3D

# ==============================================================================
# UT2004 MOBILE ARENA — DM-DECK17 NEXT-GEN EDITION
# Fixed Bot Strafing + Death Pose + Full-Map Roaming + Clear Team Contrast
# ==============================================================================

const LAYER_WORLD: int = 1
const LAYER_ACTORS: int = 2
const LAYER_SHOCK_CORE: int = 4

const TEAM_BLUE: int = 0
const TEAM_RED: int = 1

const MODE_TDM: int = 0
const MODE_FFA: int = 1
const MODE_INSTAGIB: int = 2

const STATE_MENU: int = 0
const STATE_PLAYING: int = 1
const STATE_PAUSED: int = 2
const STATE_MATCH_OVER: int = 3

var game_state: int = STATE_MENU

# Match & Settings
var cfg_mode: int = MODE_TDM
var cfg_bot_count: int = 6
var cfg_difficulty: int = 1
var cfg_high_gfx: bool = false
var cfg_sensitivity: float = 1.0
var cfg_music_on: bool = true

var score_blue: int = 0
var score_red: int = 0
var player_frags: int = 0
var player_deaths: int = 0
var frag_limit: int = 25
var match_time: float = 300.0
var first_blood_done: bool = false

# Assets & Materials
var soldier_scene: PackedScene = null
var world_env: WorldEnvironment = null
var orbital_station: Node3D = null
var mat_floor: StandardMaterial3D = null
var mat_wall: StandardMaterial3D = null
var mat_trim: StandardMaterial3D = null
var mat_dark_steel: StandardMaterial3D = null
var mat_chrome: StandardMaterial3D = null
var mat_crate: StandardMaterial3D = null
var mat_glass: StandardMaterial3D = null
var mat_glow_cyan: StandardMaterial3D = null
var mat_glow_orange: StandardMaterial3D = null
var mat_glow_purple: StandardMaterial3D = null
var mat_glow_green: StandardMaterial3D = null
var mat_glow_red: StandardMaterial3D = null
var mat_team_blue: StandardMaterial3D = null
var mat_team_red: StandardMaterial3D = null
var mat_acid: ShaderMaterial = null

var spawn_points_blue: Array = []
var spawn_points_red: Array = []
var jump_pads: Array = []
var pickups: Array = []
var bots: Array = []
var projectiles: Array = []
var shock_cores: Array = []
var effects: Array = []

var menu_cam: Camera3D = null
var menu_orbit_angle: float = 0.0
var player: UTPlayer = null
var hud: UTHUD = null
var menu_ui: UTMenuUI = null
var sfx: UTSoundBank = null
var acid_damage_timer: float = 0.0

func _ready() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()

	randomize()
	_apply_graphics_settings()

	sfx = UTSoundBank.new()
	add_child(sfx)

	_load_assets_and_materials()
	_setup_environment()
	_build_orbital_backdrop()
	_build_deck17_arena()
	_setup_spawns_and_pickups()

	menu_cam = Camera3D.new()
	menu_cam.fov = 74.0
	menu_cam.far = 220.0
	add_child(menu_cam)
	menu_cam.current = true

	player = UTPlayer.new()
	player.arena = self
	player.team = TEAM_BLUE
	add_child(player)
	player.visible = false
	player.alive = false

	_spawn_bots_roster()

	hud = UTHUD.new()
	hud.arena = self
	add_child(hud)
	hud.set_hud_visible(false)

	menu_ui = UTMenuUI.new()
	menu_ui.arena = self
	add_child(menu_ui)
	menu_ui.open_main_menu()

	sfx.set_music_enabled(cfg_music_on)

func _apply_graphics_settings() -> void:
	var root_win = get_tree().root
	root_win.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root_win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root_win.content_scale_size = Vector2i(1280, 720)
	root_win.msaa_3d = Viewport.MSAA_2X
	root_win.scaling_3d_scale = 0.92 if cfg_high_gfx else 0.78
	Engine.max_fps = 60
	if world_env != null and world_env.environment != null:
		world_env.environment.glow_enabled = cfg_high_gfx

func start_new_match() -> void:
	score_blue = 0
	score_red = 0
	player_frags = 0
	player_deaths = 0
	match_time = 300.0
	first_blood_done = false

	for pr in projectiles:
		if is_instance_valid(pr):
			pr.queue_free()
	projectiles.clear()
	for sc in shock_cores:
		if is_instance_valid(sc):
			sc.queue_free()
	shock_cores.clear()

	for p in pickups:
		p["active"] = true
		p["timer"] = 0.0
		p["node"].visible = true

	_spawn_bots_roster()

	player.team = TEAM_BLUE
	player.visible = true
	player.respawn()
	if cfg_mode == MODE_INSTAGIB:
		player.select_weapon(0)

	game_state = STATE_PLAYING
	menu_cam.current = false
	player.cam.current = true
	menu_ui.close_menu()
	hud.clear_killfeed()
	hud.set_hud_visible(true)
	var m_title = "TEAM DEATHMATCH"
	if cfg_mode == MODE_FFA:
		m_title = "FREE FOR ALL"
	elif cfg_mode == MODE_INSTAGIB:
		m_title = "INSTAGIB ARENA"
	hud.show_banner(m_title + " — FIGHT!", Color(0.25, 0.92, 1.0))
	sfx.play_announcer("ann_play")

func pause_match() -> void:
	if game_state != STATE_PLAYING:
		return
	game_state = STATE_PAUSED
	player.touch_fire = false
	player.touch_alt = false
	player.touch_move = Vector2.ZERO
	hud.set_hud_visible(false)
	menu_ui.open_pause_menu()

func resume_match() -> void:
	if game_state != STATE_PAUSED:
		return
	game_state = STATE_PLAYING
	menu_ui.close_menu()
	hud.set_hud_visible(true)

func return_to_main_menu() -> void:
	game_state = STATE_MENU
	player.alive = false
	player.visible = false
	player.touch_fire = false
	player.touch_alt = false
	player.touch_move = Vector2.ZERO
	menu_cam.current = true
	hud.set_hud_visible(false)
	menu_ui.open_main_menu()

func _finish_match(winner_text: String, win_col: Color) -> void:
	game_state = STATE_MATCH_OVER
	player.touch_fire = false
	player.touch_alt = false
	player.touch_move = Vector2.ZERO
	menu_cam.current = true
	hud.set_hud_visible(false)
	sfx.play_announcer("ann_victory")
	menu_ui.open_match_over(winner_text, win_col)

func _load_assets_and_materials() -> void:
	if ResourceLoader.exists("res://assets/models/soldier.glb"):
		var loaded = ResourceLoader.load("res://assets/models/soldier.glb")
		if loaded is PackedScene:
			soldier_scene = loaded

	if soldier_scene == null and FileAccess.file_exists("res://assets/models/soldier.glb"):
		var gltf = GLTFDocument.new()
		var state = GLTFState.new()
		if gltf.append_from_file("res://assets/models/soldier.glb", state) == OK:
			var root_node = gltf.generate_scene(state)
			if root_node != null:
				var ps = PackedScene.new()
				ps.pack(root_node)
				soldier_scene = ps
				root_node.queue_free()

	mat_floor = _make_pbr_material("floor", Color(0.46, 0.52, 0.60), 0.42, 0.78, Vector3(0.11, 0.11, 0.11), true, true)
	mat_wall = _make_pbr_material("wall", Color(0.38, 0.44, 0.52), 0.48, 0.72, Vector3(0.09, 0.09, 0.09), false, false)

	mat_dark_steel = StandardMaterial3D.new()
	mat_dark_steel.albedo_color = Color(0.16, 0.20, 0.26)
	mat_dark_steel.metallic = 0.80
	mat_dark_steel.roughness = 0.34

	mat_chrome = StandardMaterial3D.new()
	mat_chrome.albedo_color = Color(0.74, 0.80, 0.88)
	mat_chrome.metallic = 0.90
	mat_chrome.roughness = 0.22

	mat_crate = StandardMaterial3D.new()
	mat_crate.albedo_color = Color(0.28, 0.34, 0.42)
	mat_crate.metallic = 0.65
	mat_crate.roughness = 0.38

	mat_glass = StandardMaterial3D.new()
	mat_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_glass.albedo_color = Color(0.25, 0.65, 0.90, 0.16)
	mat_glass.roughness = 0.10
	mat_glass.metallic = 0.20

	mat_trim = StandardMaterial3D.new()
	mat_trim.albedo_texture = _make_hazard_texture()
	mat_trim.roughness = 0.42
	mat_trim.metallic = 0.30
	mat_trim.uv1_triplanar = true
	mat_trim.uv1_world_triplanar = true
	mat_trim.uv1_scale = Vector3(0.28, 0.28, 0.28)

	mat_glow_cyan = _make_glow_material(Color(0.16, 0.92, 1.0), 2.8)
	mat_glow_orange = _make_glow_material(Color(1.0, 0.58, 0.12), 2.6)
	mat_glow_purple = _make_glow_material(Color(0.82, 0.28, 1.0), 3.1)
	mat_glow_green = _make_glow_material(Color(0.18, 1.0, 0.38), 2.8)
	mat_glow_red = _make_glow_material(Color(1.0, 0.22, 0.16), 2.9)

	# High-contrast team armor materials
	mat_team_blue = StandardMaterial3D.new()
	mat_team_blue.albedo_color = Color(0.12, 0.52, 1.0)
	mat_team_blue.metallic = 0.35
	mat_team_blue.roughness = 0.36
	mat_team_blue.emission_enabled = true
	mat_team_blue.emission = Color(0.06, 0.32, 0.78)
	mat_team_blue.emission_energy_multiplier = 0.65

	mat_team_red = StandardMaterial3D.new()
	mat_team_red.albedo_color = Color(1.0, 0.18, 0.12)
	mat_team_red.metallic = 0.35
	mat_team_red.roughness = 0.36
	mat_team_red.emission_enabled = true
	mat_team_red.emission = Color(0.82, 0.10, 0.06)
	mat_team_red.emission_energy_multiplier = 0.72

	mat_acid = _make_acid_shader_material()

func _make_pbr_material(prefix: String, tint: Color, rough: float, metal: float, uv_scale: Vector3, is_diamond: bool, use_normal: bool) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.roughness = rough
	mat.metallic = metal
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = uv_scale

	var p_col = "res://assets/textures/%s_color.jpg" % prefix
	var p_nor = "res://assets/textures/%s_normal.jpg" % prefix

	if ResourceLoader.exists(p_col):
		mat.albedo_texture = ResourceLoader.load(p_col)
		mat.albedo_color = Color(0.64, 0.68, 0.76)
	else:
		mat.albedo_texture = _make_procedural_metal_albedo(is_diamond)

	if use_normal:
		if ResourceLoader.exists(p_nor):
			mat.normal_enabled = true
			mat.normal_texture = ResourceLoader.load(p_nor)
			mat.normal_scale = 0.28
		else:
			mat.normal_enabled = true
			mat.normal_texture = _make_procedural_metal_normal(is_diamond)
			mat.normal_scale = 0.25

	return mat

func _make_glow_material(col: Color, energy: float) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	m.roughness = 0.20
	return m

func _make_acid_shader_material() -> ShaderMaterial:
	var sh = Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled;

void fragment() {
	vec2 uv = UV * 7.5;
	float t = TIME * 0.90;
	float w1 = sin(uv.x * 2.0 + t) * cos(uv.y * 1.8 - t * 0.8);
	float w2 = sin((uv.x + uv.y) * 2.8 - t * 1.3) * 0.5;
	float bubble = sin(length(fract(uv * 0.6) - 0.5) * 15.0 - t * 2.7);
	float v = clamp(0.5 + 0.32 * (w1 + w2) + 0.18 * bubble, 0.0, 1.0);
	vec3 dark_slime = vec3(0.03, 0.25, 0.05);
	vec3 bright_slime = vec3(0.40, 1.0, 0.16);
	vec3 col = mix(dark_slime, bright_slime, smoothstep(0.18, 0.92, v));
	ALBEDO = col;
	EMISSION = col * (1.25 + v * 1.35);
	ROUGHNESS = 0.14;
	METALLIC = 0.15;
}
"""
	var sm = ShaderMaterial.new()
	sm.shader = sh
	return sm

func _make_hazard_texture() -> ImageTexture:
	var img = Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			var band = int((x + y) / 16) % 2
			var c = Color(0.95, 0.68, 0.10) if band == 0 else Color(0.08, 0.09, 0.11)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

func _make_procedural_metal_albedo(is_diamond: bool) -> ImageTexture:
	var size = 128
	var img = Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			var base = 0.38 if is_diamond else 0.32
			var edge = (x < 2 or y < 2 or x > size - 3 or y > size - 3)
			var seam = (x == 64 or y == 64)
			var val = base
			if edge or seam:
				val *= 0.55
			elif is_diamond:
				var dx = (x % 32) - 16
				var dy = (y % 32) - 16
				if abs(dx) + abs(dy) < 9:
					val += 0.12
			else:
				var rivet = ((x % 64 == 10 or x % 64 == 54) and (y % 64 == 10 or y % 64 == 54))
				if rivet:
					val += 0.15
			var c = clamp(val, 0.10, 0.90)
			img.set_pixel(x, y, Color(c * 0.93, c * 0.98, c * 1.06, 1.0))
	return ImageTexture.create_from_image(img)

func _make_procedural_metal_normal(is_diamond: bool) -> ImageTexture:
	var size = 128
	var img = Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			var nx = 0.5
			var ny = 0.5
			if x < 2 or x == 64:
				nx = 0.32
			elif x > size - 3 or x == 65:
				nx = 0.68
			if y < 2 or y == 64:
				ny = 0.32
			elif y > size - 3 or y == 65:
				ny = 0.68
			if is_diamond:
				var dx = (x % 32) - 16
				var dy = (y % 32) - 16
				if abs(dx) + abs(dy) < 9:
					nx = clamp(0.5 + float(dx) * 0.03, 0.25, 0.75)
					ny = clamp(0.5 + float(dy) * 0.03, 0.25, 0.75)
			img.set_pixel(x, y, Color(nx, ny, 0.98, 1.0))
	return ImageTexture.create_from_image(img)

func _setup_environment() -> void:
	world_env = WorldEnvironment.new()
	var env = Environment.new()

	var sky = Sky.new()
	var sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.015, 0.025, 0.06)
	sky_mat.sky_horizon_color = Color(0.14, 0.22, 0.36)
	sky_mat.ground_bottom_color = Color(0.02, 0.08, 0.05)
	sky_mat.ground_horizon_color = Color(0.08, 0.16, 0.24)
	sky_mat.sky_energy_multiplier = 1.05
	sky.sky_material = sky_mat

	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.42
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = cfg_high_gfx
	env.glow_intensity = 0.55
	env.glow_bloom = 0.18
	env.fog_enabled = true
	env.fog_light_color = Color(0.04, 0.07, 0.11)
	env.fog_density = 0.0042

	world_env.environment = env
	add_child(world_env)

	var sun_key = DirectionalLight3D.new()
	sun_key.light_color = Color(0.96, 0.85, 0.72)
	sun_key.light_energy = 0.74
	sun_key.rotation_degrees = Vector3(-56, 36, 0)
	sun_key.shadow_enabled = false
	add_child(sun_key)

	var sun_rim = DirectionalLight3D.new()
	sun_rim.light_color = Color(0.36, 0.74, 1.0)
	sun_rim.light_energy = 0.38
	sun_rim.rotation_degrees = Vector3(-26, -142, 0)
	sun_rim.shadow_enabled = false
	add_child(sun_rim)

	_add_point_light(Vector3(0, 1.2, 0), Color(0.25, 1.0, 0.22), 3.8, 22.0)
	_add_point_light(Vector3(0, 6.8, -22), Color(0.18, 0.78, 1.0), 2.8, 24.0)
	_add_point_light(Vector3(0, 6.8, 22), Color(1.0, 0.30, 0.22), 2.8, 24.0)

func _add_point_light(pos: Vector3, col: Color, energy: float, rng: float) -> void:
	var l = OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = false
	add_child(l)

func _build_orbital_backdrop() -> void:
	var planet = MeshInstance3D.new()
	var sm = SphereMesh.new()
	sm.radius = 28.0
	sm.height = 56.0
	sm.radial_segments = 24
	sm.rings = 14
	planet.mesh = sm
	var pmat = StandardMaterial3D.new()
	pmat.albedo_color = Color(0.12, 0.26, 0.48)
	pmat.roughness = 0.75
	pmat.emission_enabled = true
	pmat.emission = Color(0.05, 0.14, 0.28)
	planet.material_override = pmat
	planet.position = Vector3(-38.0, 16.0, -95.0)
	add_child(planet)

	orbital_station = Node3D.new()
	orbital_station.position = Vector3(14.0, 14.0, -78.0)
	orbital_station.rotation_degrees = Vector3(12, -24, 18)
	add_child(orbital_station)

	var core = MeshInstance3D.new()
	var cm = CylinderMesh.new()
	cm.top_radius = 2.4
	cm.bottom_radius = 2.4
	cm.height = 28.0
	cm.radial_segments = 14
	core.mesh = cm
	core.material_override = mat_chrome
	orbital_station.add_child(core)

	for ry in [-7.0, 7.0]:
		var ring = MeshInstance3D.new()
		var tm = TorusMesh.new()
		tm.inner_radius = 7.5
		tm.outer_radius = 9.0
		tm.rings = 20
		tm.ring_segments = 8
		ring.mesh = tm
		ring.material_override = mat_dark_steel
		ring.position = Vector3(0, ry, 0)
		orbital_station.add_child(ring)

		var beacon = MeshInstance3D.new()
		var bm = BoxMesh.new()
		bm.size = Vector3(18.5, 0.35, 0.35)
		beacon.mesh = bm
		beacon.material_override = mat_glow_cyan
		beacon.position = Vector3(0, ry, 0)
		orbital_station.add_child(beacon)

	var star_mm = MultiMesh.new()
	star_mm.transform_format = MultiMesh.TRANSFORM_3D
	var sb = BoxMesh.new()
	sb.size = Vector3(0.35, 0.35, 0.35)
	star_mm.mesh = sb
	star_mm.instance_count = 90
	for i in range(90):
		var ang = randf() * TAU
		var elev = randf_range(-0.15, 0.65)
		var dist = randf_range(95.0, 145.0)
		var spos = Vector3(cos(ang) * dist, sin(elev) * dist + 15.0, sin(ang) * dist)
		star_mm.set_instance_transform(i, Transform3D(Basis(), spos))
	var mmi = MultiMeshInstance3D.new()
	mmi.multimesh = star_mm
	mmi.material_override = mat_glow_cyan
	add_child(mmi)

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

func _add_cyl(pos: Vector3, r: float, h: float, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> void:
	var mi = MeshInstance3D.new()
	var cm = CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 12
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	add_child(mi)

func _add_scifi_crate(pos: Vector3, sz: Vector3, accent_mat: Material) -> void:
	_add_box(pos, sz, mat_crate, Vector3.ZERO, true)
	_add_box(pos + Vector3(0, sz.y * 0.44, 0), Vector3(sz.x + 0.12, 0.14, sz.z + 0.12), mat_dark_steel, Vector3.ZERO, false)
	_add_box(pos + Vector3(0, -sz.y * 0.44, 0), Vector3(sz.x + 0.12, 0.14, sz.z + 0.12), mat_dark_steel, Vector3.ZERO, false)
	_add_box(pos + Vector3(0, 0.1, sz.z * 0.5 + 0.03), Vector3(sz.x * 0.55, 0.12, 0.05), accent_mat, Vector3.ZERO, false)
	_add_box(pos + Vector3(0, 0.1, -sz.z * 0.5 - 0.03), Vector3(sz.x * 0.55, 0.12, 0.05), accent_mat, Vector3.ZERO, false)

func _add_railing(a: Vector3, b: Vector3) -> void:
	var mid = (a + b) * 0.5
	var dist = a.distance_to(b)
	var dir = (b - a).normalized()
	var ang = rad_to_deg(atan2(dir.x, dir.z))
	_add_box(mid + Vector3(0, 0.92, 0), Vector3(0.09, 0.09, dist), mat_chrome, Vector3(0, ang, 0), false)
	_add_box(mid + Vector3(0, 0.48, 0), Vector3(0.06, 0.06, dist), mat_dark_steel, Vector3(0, ang, 0), false)
	var posts = max(2, int(dist / 4.5) + 1)
	for i in range(posts):
		var t = float(i) / float(posts - 1)
		var p = a.lerp(b, t)
		_add_box(p + Vector3(0, 0.48, 0), Vector3(0.11, 0.96, 0.11), mat_dark_steel, Vector3.ZERO, false)

func _add_wall_reactor(pos: Vector3, glow_mat: Material) -> void:
	_add_box(pos, Vector3(1.6, 8.2, 1.1), mat_dark_steel, Vector3.ZERO, false)
	_add_cyl(pos + Vector3(0, 0, 0.35), 0.32, 6.8, glow_mat)
	for y_ring in [-2.4, -0.8, 0.8, 2.4]:
		_add_box(pos + Vector3(0, y_ring, 0.35), Vector3(1.3, 0.24, 0.9), mat_chrome, Vector3.ZERO, false)

func _build_deck17_arena() -> void:
	_add_box(Vector3(0, -0.5, -18.5), Vector3(48, 1.0, 19.0), mat_floor)
	_add_box(Vector3(0, -0.5, 18.5), Vector3(48, 1.0, 19.0), mat_floor)
	_add_box(Vector3(-15.5, -0.5, 0), Vector3(17.0, 1.0, 18.0), mat_floor)
	_add_box(Vector3(15.5, -0.5, 0), Vector3(17.0, 1.0, 18.0), mat_floor)

	_add_box(Vector3(0, -3.0, 0), Vector3(16.0, 1.0, 20.0), mat_dark_steel)
	_add_box(Vector3(0, -1.6, -9.2), Vector3(14.8, 2.4, 0.6), mat_dark_steel)
	_add_box(Vector3(0, -1.6, 9.2), Vector3(14.8, 2.4, 0.6), mat_dark_steel)
	_add_box(Vector3(-7.2, -1.6, 0), Vector3(0.6, 2.4, 18.8), mat_dark_steel)
	_add_box(Vector3(7.2, -1.6, 0), Vector3(0.6, 2.4, 18.8), mat_dark_steel)

	var acid_mesh = MeshInstance3D.new()
	var pm = PlaneMesh.new()
	pm.size = Vector2(14.2, 18.2)
	acid_mesh.mesh = pm
	acid_mesh.material_override = mat_acid
	acid_mesh.position = Vector3(0, -1.35, 0)
	add_child(acid_mesh)

	_add_box(Vector3(0, 0.04, -9.25), Vector3(15.0, 0.08, 0.55), mat_trim, Vector3.ZERO, false)
	_add_box(Vector3(0, 0.04, 9.25), Vector3(15.0, 0.08, 0.55), mat_trim, Vector3.ZERO, false)
	_add_box(Vector3(-7.25, 0.04, 0), Vector3(0.55, 0.08, 18.0), mat_trim, Vector3.ZERO, false)
	_add_box(Vector3(7.25, 0.04, 0), Vector3(0.55, 0.08, 18.0), mat_trim, Vector3.ZERO, false)

	_add_box(Vector3(0, 4.2, -28.5), Vector3(50, 9.4, 1.0), mat_wall)
	_add_box(Vector3(0, 13.7, -28.5), Vector3(50, 1.6, 1.0), mat_wall)
	_add_box(Vector3(-19.5, 10.9, -28.5), Vector3(11.0, 4.2, 1.0), mat_wall)
	_add_box(Vector3(19.5, 10.9, -28.5), Vector3(11.0, 4.2, 1.0), mat_wall)
	_add_box(Vector3(0, 10.9, -28.5), Vector3(28.0, 4.0, 0.2), mat_glass, Vector3.ZERO, true)
	for wx in [-9.0, 0.0, 9.0]:
		_add_box(Vector3(wx, 10.9, -28.5), Vector3(0.45, 4.2, 0.9), mat_dark_steel, Vector3.ZERO, false)

	_add_box(Vector3(0, 4.2, 28.5), Vector3(50, 9.4, 1.0), mat_wall)
	_add_box(Vector3(0, 13.7, 28.5), Vector3(50, 1.6, 1.0), mat_wall)
	_add_box(Vector3(-19.5, 10.9, 28.5), Vector3(11.0, 4.2, 1.0), mat_wall)
	_add_box(Vector3(19.5, 10.9, 28.5), Vector3(11.0, 4.2, 1.0), mat_wall)
	_add_box(Vector3(0, 10.9, 28.5), Vector3(28.0, 4.0, 0.2), mat_glass, Vector3.ZERO, true)
	for wx2 in [-9.0, 0.0, 9.0]:
		_add_box(Vector3(wx2, 10.9, 28.5), Vector3(0.45, 4.2, 0.9), mat_dark_steel, Vector3.ZERO, false)

	_add_box(Vector3(-24.5, 7.0, 0), Vector3(1.0, 15.0, 58.0), mat_wall)
	_add_box(Vector3(24.5, 7.0, 0), Vector3(1.0, 15.0, 58.0), mat_wall)

	_add_box(Vector3(0, 14.5, 0), Vector3(50, 1.0, 58), mat_dark_steel)
	for z_beam in [-20.0, -10.0, 0.0, 10.0, 20.0]:
		_add_box(Vector3(0, 13.4, z_beam), Vector3(48, 1.2, 1.2), mat_dark_steel, Vector3.ZERO, false)
		_add_box(Vector3(0, 12.75, z_beam), Vector3(26, 0.16, 0.36), mat_glow_orange, Vector3.ZERO, false)
	_add_cyl(Vector3(-15.5, 12.2, 0), 0.38, 55.0, mat_chrome, Vector3(90, 0, 0))
	_add_cyl(Vector3(15.5, 12.2, 0), 0.38, 55.0, mat_chrome, Vector3(90, 0, 0))

	_add_box(Vector3(0, 8.6, -27.85), Vector3(24.0, 0.35, 0.25), mat_glow_cyan, Vector3.ZERO, false)
	_add_box(Vector3(0, 8.6, 27.85), Vector3(24.0, 0.35, 0.25), mat_glow_red, Vector3.ZERO, false)
	_add_wall_reactor(Vector3(-16.0, 8.2, -27.5), mat_glow_cyan)
	_add_wall_reactor(Vector3(16.0, 8.2, -27.5), mat_glow_cyan)
	_add_wall_reactor(Vector3(-16.0, 8.2, 27.5), mat_glow_red)
	_add_wall_reactor(Vector3(16.0, 8.2, 27.5), mat_glow_red)

	_add_box(Vector3(0, 4.15, -23.5), Vector3(48, 0.5, 9.0), mat_floor)
	_add_box(Vector3(0, 4.15, 23.5), Vector3(48, 0.5, 9.0), mat_floor)
	_add_box(Vector3(-20.0, 4.15, 0), Vector3(8.0, 0.5, 38.0), mat_floor)
	_add_box(Vector3(20.0, 4.15, 0), Vector3(8.0, 0.5, 38.0), mat_floor)

	_add_railing(Vector3(-8.5, 4.4, -19.1), Vector3(10.5, 4.4, -19.1))
	_add_railing(Vector3(-10.5, 4.4, 19.1), Vector3(8.5, 4.4, 19.1))
	_add_railing(Vector3(-16.1, 4.4, -14.0), Vector3(-16.1, 4.4, -3.0))
	_add_railing(Vector3(-16.1, 4.4, 3.0), Vector3(-16.1, 4.4, 12.5))
	_add_railing(Vector3(16.1, 4.4, -12.5), Vector3(16.1, 4.4, -3.0))
	_add_railing(Vector3(16.1, 4.4, 3.0), Vector3(16.1, 4.4, 14.0))

	_add_box(Vector3(0, 4.15, 0), Vector3(32.0, 0.48, 4.6), mat_floor)
	_add_box(Vector3(0, 4.42, -2.2), Vector3(30.0, 0.14, 0.24), mat_glow_purple, Vector3.ZERO, false)
	_add_box(Vector3(0, 4.42, 2.2), Vector3(30.0, 0.14, 0.24), mat_glow_purple, Vector3.ZERO, false)

	_add_box(Vector3(-12.5, 2.05, -13.0), Vector3(4.6, 0.45, 12.8), mat_floor, Vector3(20.5, 0, 0))
	_add_box(Vector3(12.5, 2.05, 13.0), Vector3(4.6, 0.45, 12.8), mat_floor, Vector3(-20.5, 0, 0))
	_add_box(Vector3(-14.7, 2.35, -13.0), Vector3(0.25, 0.4, 12.8), mat_trim, Vector3(20.5, 0, 0), false)
	_add_box(Vector3(14.7, 2.35, 13.0), Vector3(0.25, 0.4, 12.8), mat_trim, Vector3(-20.5, 0, 0), false)

	var pillar_coords = [
		Vector3(-9.5, 6.8, -11.5),
		Vector3(9.5, 6.8, -11.5),
		Vector3(-9.5, 6.8, 11.5),
		Vector3(9.5, 6.8, 11.5)
	]
	for p in pillar_coords:
		_add_box(p, Vector3(2.4, 14.0, 2.4), mat_wall)
		_add_box(Vector3(p.x, 0.35, p.z), Vector3(2.9, 0.7, 2.9), mat_dark_steel, Vector3.ZERO, false)
		_add_box(Vector3(p.x, 2.2, p.z), Vector3(2.65, 0.38, 2.65), mat_trim, Vector3.ZERO, false)
		_add_box(Vector3(p.x, 7.6, p.z), Vector3(2.6, 0.26, 2.6), mat_glow_orange, Vector3.ZERO, false)

	_add_scifi_crate(Vector3(0, 1.1, -15.0), Vector3(4.8, 2.2, 1.5), mat_glow_cyan)
	_add_scifi_crate(Vector3(0, 1.1, 15.0), Vector3(4.8, 2.2, 1.5), mat_glow_red)
	_add_scifi_crate(Vector3(-13.5, 1.0, 5.5), Vector3(2.5, 2.0, 2.5), mat_glow_orange)
	_add_scifi_crate(Vector3(13.5, 1.0, -5.5), Vector3(2.5, 2.0, 2.5), mat_glow_orange)
	_add_scifi_crate(Vector3(-19.2, 5.4, -9.5), Vector3(1.4, 2.0, 3.6), mat_glow_cyan)
	_add_scifi_crate(Vector3(19.2, 5.4, 9.5), Vector3(1.4, 2.0, 3.6), mat_glow_red)

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
	cm.radial_segments = 16
	base.mesh = cm
	base.material_override = mat_dark_steel
	pad.add_child(base)

	var ring = MeshInstance3D.new()
	var tm = TorusMesh.new()
	tm.inner_radius = 0.95
	tm.outer_radius = 1.35
	tm.rings = 16
	tm.ring_segments = 10
	ring.mesh = tm
	ring.material_override = mat_glow_cyan
	ring.position = Vector3(0, 0.14, 0)
	pad.add_child(ring)

	var core = MeshInstance3D.new()
	var c2 = CylinderMesh.new()
	c2.top_radius = 0.75
	c2.bottom_radius = 0.75
	c2.height = 0.08
	c2.radial_segments = 16
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
	bm.radial_segments = 14
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
		tm.rings = 14
		tm.ring_segments = 10
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

func _spawn_bots_roster() -> void:
	for b in bots:
		if is_instance_valid(b):
			b.queue_free()
	bots.clear()

	var names = ["Xan Kriegor", "Malcolm", "Brock", "Sapphire", "Gorge", "Lauren", "Tamika", "Othello"]
	var count = clamp(cfg_bot_count, 2, names.size())
	var red_target = (count + 1) / 2
	for i in range(count):
		var b = UTBot.new()
		b.arena = self
		b.bot_name = names[i]
		if cfg_mode == MODE_TDM:
			b.team = TEAM_RED if i < red_target else TEAM_BLUE
		else:
			b.team = 10 + i
		add_child(b)
		b.respawn()
		bots.append(b)

func get_spawn_point(team: int) -> Vector3:
	if cfg_mode != MODE_TDM:
		var all_sp = spawn_points_blue + spawn_points_red
		return all_sp[randi() % all_sp.size()]
	var list = spawn_points_blue if team == TEAM_BLUE else spawn_points_red
	return list[randi() % list.size()]

func _process(delta: float) -> void:
	if game_state == STATE_PAUSED:
		return

	if orbital_station != null:
		orbital_station.rotation.y += delta * 0.08

	if game_state == STATE_MENU or game_state == STATE_MATCH_OVER:
		menu_orbit_angle += delta * 0.22
		var rx = sin(menu_orbit_angle) * 16.5
		var rz = cos(menu_orbit_angle) * 18.5
		menu_cam.position = Vector3(rx, 9.2 + sin(menu_orbit_angle * 1.7) * 1.4, rz)
		menu_cam.look_at(Vector3(0, 2.2, 0), Vector3.UP)

	if game_state == STATE_PLAYING:
		match_time = max(0.0, match_time - delta)
		if match_time <= 0.0:
			if cfg_mode == MODE_TDM:
				var msg = "BLUE TEAM WINS!" if score_blue >= score_red else "RED TEAM WINS!"
				_finish_match(msg, Color(0.25, 0.9, 1.0) if score_blue >= score_red else Color(1.0, 0.3, 0.25))
			else:
				_finish_match("TIME UP — %d FRAGS!" % player_frags, Color(1.0, 0.82, 0.2))
			return

	var ticks = Time.get_ticks_msec() * 0.004
	for jp in jump_pads:
		var r: Node3D = jp["ring"]
		r.rotation.y += delta * 2.4
		r.position.y = 0.15 + sin(ticks * 1.5) * 0.05

	for p in pickups:
		var item: Node3D = p["node"]
		if not p["active"]:
			p["timer"] -= delta
			if p["timer"] <= 0.0:
				p["active"] = true
				item.visible = true
		else:
			item.rotation.y += delta * 2.6
			item.position.y = 0.88 + sin(ticks + p["pos"].x) * 0.14
			_check_pickup_collect(p)

	acid_damage_timer -= delta
	if acid_damage_timer <= 0.0:
		acid_damage_timer = 0.35
		_check_acid_damage()

	var keep_proj: Array = []
	for pr in projectiles:
		if is_instance_valid(pr):
			if pr.step_projectile(delta):
				keep_proj.append(pr)
			else:
				pr.queue_free()
	projectiles = keep_proj

	var keep_cores: Array = []
	for sc in shock_cores:
		if is_instance_valid(sc):
			if sc.step_core(delta):
				keep_cores.append(sc)
			else:
				sc.queue_free()
	shock_cores = keep_cores

	var keep_fx: Array = []
	for fx in effects:
		if is_instance_valid(fx):
			if fx.step_fx(delta):
				keep_fx.append(fx)
			else:
				fx.queue_free()
	effects = keep_fx

func _check_pickup_collect(p: Dictionary) -> void:
	if cfg_mode == MODE_INSTAGIB:
		return
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
				a.hp = min(150, a.hp + 40)
				used = true
			elif p["kind"] == "armor" and a.armor < 100:
				a.armor = min(100, a.armor + 50)
				used = true
			elif p["kind"] == "udamage":
				a.udamage_timer = 15.0
				used = true
				if a == player and game_state == STATE_PLAYING:
					hud.show_banner("DOUBLE DAMAGE!", Color(0.82, 0.32, 1.0))
					sfx.play_announcer("ann_udamage")
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
			a.apply_damage(18, null, "Acid Vat", Vector3(0, 6.5, 0))
			if a == player and game_state == STATE_PLAYING:
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
	if game_state != STATE_PLAYING:
		return

	if cfg_mode == MODE_TDM:
		if victim.team == TEAM_RED:
			score_blue += 1
		else:
			score_red += 1

	if killer == player:
		player_frags += 1
		player.register_player_kill(weapon_name)
	if victim == player:
		player_deaths += 1

	var kname = "Environment"
	if killer != null and is_instance_valid(killer):
		kname = "YOU" if killer == player else killer.bot_name
	var vname = "YOU" if victim == player else victim.bot_name
	hud.add_killfeed(kname, vname, weapon_name)

	if cfg_mode == MODE_TDM:
		if score_blue >= frag_limit:
			_finish_match("VICTORY — BLUE TEAM WINS!", Color(0.25, 0.92, 1.0))
		elif score_red >= frag_limit:
			_finish_match("DEFEAT — RED TEAM WINS!", Color(1.0, 0.32, 0.25))
	else:
		if player_frags >= frag_limit:
			_finish_match("DOMINATION — YOU WIN!", Color(1.0, 0.85, 0.2))

func spawn_beam(from_pos: Vector3, to_pos: Vector3, col: Color, radius: float, life: float) -> void:
	var fx = UTBeamFX.new()
	fx.setup(from_pos, to_pos, col, radius, life)
	add_child(fx)
	effects.append(fx)

func spawn_sparks(pos: Vector3, col: Color, count: int = 10) -> void:
	var fx = UTSparkBurstFX.new()
	fx.setup(pos, col, count)
	add_child(fx)
	effects.append(fx)

func spawn_explosion(pos: Vector3, radius: float, col: Color, damage: int, attacker, weapon_name: String, knockback: float) -> void:
	var is_combo = (weapon_name == "Shock Combo")
	var fx = UTExplosionFX.new()
	fx.setup(pos, radius, col, 0.42 if is_combo else 0.34, true)
	add_child(fx)
	effects.append(fx)
	spawn_sparks(pos, col, 18 if is_combo else 12)

	if game_state == STATE_PLAYING:
		sfx.play_sfx("shock_combo" if is_combo else "explosion")
		if is_instance_valid(player) and player.alive:
			var d_pl = player.global_position.distance_to(pos)
			if d_pl < 22.0:
				var shake_amt = clamp((1.0 - d_pl / 22.0) * (0.40 if is_combo else 0.24), 0.0, 0.42)
				player.add_shake(shake_amt)

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
				dmg = int(round(float(dmg) * 0.22))
				impulse *= 1.38
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
# AUDIO ENGINE
# ==============================================================================
class UTSoundBank extends Node:
	var bank: Dictionary = {}
	var announcer_bank: Dictionary = {}
	var players: Array = []
	var next_idx: int = 0
	var announcer_player: AudioStreamPlayer = null
	var bgm_player: AudioStreamPlayer = null
	var music_enabled: bool = true

	func _ready() -> void:
		for i in range(6):
			var p = AudioStreamPlayer.new()
			p.volume_db = -5.5
			add_child(p)
			players.append(p)

		announcer_player = AudioStreamPlayer.new()
		announcer_player.volume_db = -1.0
		add_child(announcer_player)

		bgm_player = AudioStreamPlayer.new()
		bgm_player.volume_db = -12.5
		bgm_player.finished.connect(_on_bgm_finished)
		add_child(bgm_player)

		var bgm_res = _load_wav("res://assets/audio/bgm_arena.wav")
		if bgm_res != null:
			bgm_player.stream = bgm_res

		var ann_keys = [
			"ann_play", "ann_firstblood", "ann_double", "ann_multi",
			"ann_monster", "ann_spree", "ann_unstoppable", "ann_combo",
			"ann_udamage", "ann_victory"
		]
		for k in ann_keys:
			var res = _load_wav("res://assets/audio/%s.wav" % k)
			if res != null:
				announcer_bank[k] = res

		bank["shock_fire"] = _load_or_gen("res://assets/audio/sfx_shock.wav", 0.22, 1100.0, 180.0, 0.25, 0.85)
		bank["shock_combo"] = _load_or_gen("res://assets/audio/sfx_combo.wav", 0.52, 420.0, 36.0, 0.65, 1.0)
		bank["flak_fire"] = _load_or_gen("res://assets/audio/sfx_flak.wav", 0.26, 280.0, 55.0, 0.86, 0.92)
		bank["rocket_fire"] = _load_or_gen("res://assets/audio/sfx_rocket.wav", 0.30, 210.0, 48.0, 0.72, 0.88)
		bank["link_fire"] = _load_or_gen("res://assets/audio/sfx_link.wav", 0.11, 780.0, 380.0, 0.15, 0.58)
		bank["explosion"] = _load_or_gen("res://assets/audio/sfx_boom.wav", 0.44, 150.0, 28.0, 0.92, 0.95)
		bank["hit"] = _gen_tone(0.055, 1680.0, 1240.0, 0.05, 0.78)
		bank["jump_pad"] = _gen_tone(0.28, 240.0, 1080.0, 0.10, 0.78)
		bank["dodge"] = _gen_tone(0.14, 330.0, 130.0, 0.45, 0.58)
		bank["pickup"] = _gen_tone(0.22, 560.0, 1140.0, 0.0, 0.72)
		bank["step"] = _gen_tone(0.045, 140.0, 75.0, 0.85, 0.22)

	func _load_wav(path: String) -> AudioStream:
		if ResourceLoader.exists(path):
			var r = ResourceLoader.load(path)
			if r is AudioStream:
				return r
		if FileAccess.file_exists(path):
			var f = FileAccess.open(path, FileAccess.READ)
			if f != null:
				var bytes = f.get_buffer(f.get_length())
				if bytes.size() > 44:
					var wav = AudioStreamWAV.new()
					wav.format = AudioStreamWAV.FORMAT_16_BITS
					wav.mix_rate = 22050
					wav.stereo = false
					wav.data = bytes.slice(44)
					return wav
		return null

	func _load_or_gen(path: String, dur: float, f0: float, f1: float, nz: float, amp: float) -> AudioStream:
		var loaded = _load_wav(path)
		if loaded != null:
			return loaded
		return _gen_tone(dur, f0, f1, nz, amp)

	func set_music_enabled(en: bool) -> void:
		music_enabled = en
		if bgm_player == null or bgm_player.stream == null:
			return
		if en:
			if not bgm_player.playing:
				bgm_player.play()
		else:
			bgm_player.stop()

	func _on_bgm_finished() -> void:
		if music_enabled and bgm_player != null and bgm_player.stream != null:
			bgm_player.play()

	func play_announcer(key: String) -> void:
		if announcer_bank.has(key):
			announcer_player.stream = announcer_bank[key]
			announcer_player.play()
		else:
			play_sfx("pickup")

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
			var env = pow(1.0 - t, 1.55)
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
# PLAYER CONTROLLER
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
	var anim_shock_core: Node3D = null
	var anim_flak_jaw_l: Node3D = null
	var anim_flak_jaw_r: Node3D = null
	var anim_rkt_barrels: Node3D = null
	var anim_link_ring: Node3D = null

	var muzzle_group: Node3D = null
	var muzzle_mat: StandardMaterial3D = null
	var muzzle_timer: float = 0.0

	var current_weapon: int = 0
	var fire_cd: float = 0.0
	var recoil_z: float = 0.0
	var recoil_pitch: float = 0.0
	var shake_intensity: float = 0.0
	var bob_t: float = 0.0
	var step_accum: float = 0.0

	var jumps_used: int = 0
	var dodge_cd: float = 0.0
	var kill_streak: int = 0
	var multi_kill: int = 0
	var multi_kill_timer: float = 0.0

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
		cam.far = 220.0
		add_child(cam)

		weapon_pivot = Node3D.new()
		weapon_pivot.position = Vector3(0.28, -0.25, -0.50)
		cam.add_child(weapon_pivot)

		muzzle_group = Node3D.new()
		muzzle_group.position = Vector3(0, 0.02, -0.66)
		muzzle_group.visible = false
		weapon_pivot.add_child(muzzle_group)

		muzzle_mat = StandardMaterial3D.new()
		muzzle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		muzzle_mat.albedo_color = Color(1.0, 0.8, 0.3)

		var cone_m = MeshInstance3D.new()
		var cm = CylinderMesh.new()
		cm.top_radius = 0.01
		cm.bottom_radius = 0.14
		cm.height = 0.36
		cm.radial_segments = 8
		cone_m.mesh = cm
		cone_m.material_override = muzzle_mat
		cone_m.rotation_degrees = Vector3(-90, 0, 0)
		cone_m.position = Vector3(0, 0, -0.14)
		muzzle_group.add_child(cone_m)

		var core_m = MeshInstance3D.new()
		var sm = SphereMesh.new()
		sm.radius = 0.10
		sm.height = 0.20
		sm.radial_segments = 8
		sm.rings = 6
		core_m.mesh = sm
		core_m.material_override = muzzle_mat
		muzzle_group.add_child(core_m)

		_build_sculpted_weapons()
		select_weapon(0)

	func _build_sculpted_weapons() -> void:
		weapon_models.clear()
		var gun_dark = StandardMaterial3D.new()
		gun_dark.albedo_color = Color(0.16, 0.19, 0.24)
		gun_dark.metallic = 0.85
		gun_dark.roughness = 0.30

		var gun_body = StandardMaterial3D.new()
		gun_body.albedo_color = Color(0.46, 0.52, 0.60)
		gun_body.metallic = 0.80
		gun_body.roughness = 0.26

		var gun_chrome = arena.mat_chrome

		var w0 = Node3D.new()
		_vm_box(w0, Vector3(0, -0.02, 0.06), Vector3(0.10, 0.12, 0.44), gun_dark)
		_vm_box(w0, Vector3(0, -0.09, 0.14), Vector3(0.065, 0.10, 0.11), gun_dark, Vector3(18, 0, 0))
		_vm_box(w0, Vector3(0, 0.055, -0.16), Vector3(0.075, 0.032, 0.62), gun_body)
		_vm_box(w0, Vector3(0, -0.065, -0.22), Vector3(0.07, 0.032, 0.52), gun_body)
		_vm_cyl(w0, Vector3(-0.038, 0.015, -0.34), 0.016, 0.48, gun_chrome)
		_vm_cyl(w0, Vector3(0.038, 0.015, -0.34), 0.016, 0.48, gun_chrome)
		_vm_cyl(w0, Vector3(0, -0.02, -0.36), 0.014, 0.44, gun_dark)
		for zf in [-0.12, -0.20, -0.28, -0.36, -0.44]:
			_vm_box(w0, Vector3(0, 0.01, zf), Vector3(0.115, 0.088, 0.020), gun_dark)
		anim_shock_core = Node3D.new()
		anim_shock_core.position = Vector3(0, 0.01, -0.26)
		w0.add_child(anim_shock_core)
		_vm_cyl(anim_shock_core, Vector3.ZERO, 0.032, 0.30, arena.mat_glow_purple)
		_vm_box(w0, Vector3(0, 0.10, -0.02), Vector3(0.048, 0.048, 0.18), gun_dark)
		_vm_box(w0, Vector3(0, 0.106, -0.02), Vector3(0.030, 0.026, 0.21), arena.mat_glow_purple)
		weapon_pivot.add_child(w0)
		weapon_models.append(w0)

		var w1 = Node3D.new()
		var flk_yellow = StandardMaterial3D.new()
		flk_yellow.albedo_color = Color(0.95, 0.68, 0.08)
		flk_yellow.metallic = 0.65
		flk_yellow.roughness = 0.32
		_vm_cyl(w1, Vector3(0, -0.01, 0.04), 0.095, 0.42, flk_yellow)
		_vm_box(w1, Vector3(0, 0.068, -0.04), Vector3(0.14, 0.036, 0.38), gun_dark)
		_vm_box(w1, Vector3(0, -0.085, -0.02), Vector3(0.12, 0.032, 0.34), gun_dark)
		_vm_cyl(w1, Vector3(-0.115, -0.02, 0.05), 0.072, 0.18, gun_dark, Vector3(0, 0, 90))
		_vm_cyl(w1, Vector3(-0.115, -0.02, 0.05), 0.042, 0.19, flk_yellow, Vector3(0, 0, 90))
		_vm_cyl(w1, Vector3(0.095, 0.04, -0.04), 0.016, 0.32, gun_chrome)
		_vm_cyl(w1, Vector3(0, 0.0, -0.24), 0.050, 0.24, arena.mat_glow_orange)
		anim_flak_jaw_l = Node3D.new()
		anim_flak_jaw_l.position = Vector3(-0.082, 0.0, -0.28)
		w1.add_child(anim_flak_jaw_l)
		_vm_box(anim_flak_jaw_l, Vector3(0, 0, 0), Vector3(0.046, 0.11, 0.34), gun_body)
		_vm_box(anim_flak_jaw_l, Vector3(-0.02, 0, -0.10), Vector3(0.024, 0.055, 0.20), flk_yellow)
		_vm_cyl(anim_flak_jaw_l, Vector3(0, 0.04, -0.14), 0.012, 0.18, gun_chrome)

		anim_flak_jaw_r = Node3D.new()
		anim_flak_jaw_r.position = Vector3(0.082, 0.0, -0.28)
		w1.add_child(anim_flak_jaw_r)
		_vm_box(anim_flak_jaw_r, Vector3(0, 0, 0), Vector3(0.046, 0.11, 0.34), gun_body)
		_vm_box(anim_flak_jaw_r, Vector3(0.02, 0, -0.10), Vector3(0.024, 0.055, 0.20), flk_yellow)
		_vm_cyl(anim_flak_jaw_r, Vector3(0, 0.04, -0.14), 0.012, 0.18, gun_chrome)
		weapon_pivot.add_child(w1)
		weapon_models.append(w1)

		var w2 = Node3D.new()
		var rkt_red = StandardMaterial3D.new()
		rkt_red.albedo_color = Color(0.68, 0.16, 0.14)
		rkt_red.metallic = 0.70
		rkt_red.roughness = 0.34
		_vm_cyl(w2, Vector3(0, 0.0, 0.08), 0.115, 0.40, rkt_red)
		_vm_box(w2, Vector3(0, 0.115, 0.04), Vector3(0.13, 0.036, 0.36), gun_dark)
		_vm_box(w2, Vector3(0, -0.11, 0.06), Vector3(0.11, 0.032, 0.30), gun_dark)
		_vm_cyl(w2, Vector3(0.11, 0.08, -0.04), 0.026, 0.22, gun_dark)
		_vm_cyl(w2, Vector3(0.11, 0.08, -0.155), 0.016, 0.02, arena.mat_glow_red)
		anim_rkt_barrels = Node3D.new()
		anim_rkt_barrels.position = Vector3(0, 0.0, -0.28)
		w2.add_child(anim_rkt_barrels)
		for bpos in [Vector3(-0.052, 0.042, 0), Vector3(0.052, 0.042, 0), Vector3(0.0, -0.052, 0)]:
			_vm_cyl(anim_rkt_barrels, bpos, 0.038, 0.46, gun_chrome)
			_vm_cyl(anim_rkt_barrels, bpos + Vector3(0, 0, -0.22), 0.044, 0.04, gun_dark)
		_vm_cyl(anim_rkt_barrels, Vector3(0, 0, -0.10), 0.108, 0.05, gun_dark)
		_vm_cyl(anim_rkt_barrels, Vector3(0, 0, 0.08), 0.108, 0.05, gun_dark)
		weapon_pivot.add_child(w2)
		weapon_models.append(w2)

		var w3 = Node3D.new()
		_vm_cyl(w3, Vector3(0, -0.01, 0.02), 0.072, 0.48, gun_dark)
		_vm_box(w3, Vector3(-0.062, 0.02, -0.32), Vector3(0.028, 0.058, 0.36), gun_body)
		_vm_box(w3, Vector3(0.062, 0.02, -0.32), Vector3(0.028, 0.058, 0.36), gun_body)
		_vm_box(w3, Vector3(-0.062, 0.02, -0.38), Vector3(0.016, 0.030, 0.28), arena.mat_glow_green)
		_vm_box(w3, Vector3(0.062, 0.02, -0.38), Vector3(0.016, 0.030, 0.28), arena.mat_glow_green)
		_vm_cyl(w3, Vector3(0, 0.068, -0.05), 0.034, 0.26, arena.mat_glow_green)
		anim_link_ring = Node3D.new()
		anim_link_ring.position = Vector3(0, 0.01, -0.32)
		w3.add_child(anim_link_ring)
		var tm = TorusMesh.new()
		tm.inner_radius = 0.048
		tm.outer_radius = 0.072
		tm.rings = 14
		tm.ring_segments = 8
		var rmi = MeshInstance3D.new()
		rmi.mesh = tm
		rmi.material_override = arena.mat_glow_green
		rmi.rotation_degrees = Vector3(90, 0, 0)
		anim_link_ring.add_child(rmi)
		weapon_pivot.add_child(w3)
		weapon_models.append(w3)

	func _vm_box(parent: Node3D, pos: Vector3, sz: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> void:
		var mi = MeshInstance3D.new()
		var bm = BoxMesh.new()
		bm.size = sz
		mi.mesh = bm
		mi.material_override = mat
		mi.position = pos
		mi.rotation_degrees = rot_deg
		parent.add_child(mi)

	func _vm_cyl(parent: Node3D, pos: Vector3, rad: float, h: float, mat: Material, rot_deg: Vector3 = Vector3(90, 0, 0)) -> void:
		var mi = MeshInstance3D.new()
		var cm = CylinderMesh.new()
		cm.top_radius = rad
		cm.bottom_radius = rad
		cm.height = h
		cm.radial_segments = 12
		mi.mesh = cm
		mi.material_override = mat
		mi.position = pos
		mi.rotation_degrees = rot_deg
		parent.add_child(mi)

	func select_weapon(idx: int) -> void:
		if arena.cfg_mode == 2:
			idx = 0
		current_weapon = clamp(idx, 0, 3)
		for i in range(weapon_models.size()):
			weapon_models[i].visible = (i == current_weapon)
		recoil_z = 0.16

	func add_shake(amount: float) -> void:
		shake_intensity = max(shake_intensity, amount)

	func respawn() -> void:
		alive = true
		hp = 100
		armor = 0 if arena.cfg_mode == 2 else 25
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
		if arena.game_state != 1:
			return
		yaw -= dx * arena.cfg_sensitivity
		pitch = clamp(pitch - dy * arena.cfg_sensitivity, -1.42, 1.42)
		rotation.y = yaw
		cam.rotation.x = pitch

	func trigger_jump() -> void:
		if not alive or arena.game_state != 1:
			return
		if is_on_floor():
			velocity.y = 9.4
			jumps_used = 1
			arena.sfx.play_sfx("step")
		elif jumps_used < 2:
			velocity.y = max(velocity.y * 0.35 + 8.8, 8.8)
			jumps_used = 2
			arena.sfx.play_sfx("dodge")

	func trigger_dodge() -> void:
		if not alive or dodge_cd > 0.0 or arena.game_state != 1:
			return
		var input_dir = _get_move_input_world()
		if is_on_wall() and not is_on_floor():
			var wn = get_wall_normal()
			var kick = (wn + input_dir * 0.45).normalized()
			velocity.x = kick.x * 18.5
			velocity.z = kick.z * 18.5
			velocity.y = 7.6
			dodge_cd = 0.68
			arena.sfx.play_sfx("dodge")
			return
		if is_on_floor():
			var dir = input_dir if input_dir.length() > 0.1 else -global_transform.basis.z
			dir.y = 0.0
			dir = dir.normalized()
			velocity.x = dir.x * 20.0
			velocity.z = dir.z * 20.0
			velocity.y = 5.4
			dodge_cd = 0.80
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
		if arena.game_state != 1:
			return
		if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			add_look(event.relative.x * 0.0028, event.relative.y * 0.0028)
		elif event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_SPACE:
				trigger_jump()
			elif event.keycode == KEY_SHIFT:
				trigger_dodge()
			elif event.keycode == KEY_ESCAPE:
				arena.pause_match()
			elif event.keycode == KEY_1:
				select_weapon(0)
			elif event.keycode == KEY_2:
				select_weapon(1)
			elif event.keycode == KEY_3:
				select_weapon(2)
			elif event.keycode == KEY_4:
				select_weapon(3)

	func _physics_process(delta: float) -> void:
		if arena.game_state != 1:
			return
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

		if not is_on_floor():
			velocity.y -= 23.0 * delta
		else:
			jumps_used = 0

		var wish = _get_move_input_world()
		var max_spd = 13.0 if arena.cfg_mode == 2 else 11.4
		var accel = 13.5 if is_on_floor() else 3.4
		var target_vx = wish.x * max_spd
		var target_vz = wish.z * max_spd
		var hspd = Vector2(velocity.x, velocity.z).length()
		if is_on_floor() or wish.length() > 0.05:
			if is_on_floor() and hspd > max_spd + 1.0:
				velocity.x = lerp(velocity.x, target_vx, delta * 5.0)
				velocity.z = lerp(velocity.z, target_vz, delta * 5.0)
			else:
				velocity.x = lerp(velocity.x, target_vx, clamp(delta * accel, 0.0, 1.0))
				velocity.z = lerp(velocity.z, target_vz, clamp(delta * accel, 0.0, 1.0))

		move_and_slide()
		arena.check_jump_pads(self)

		var mouse_captured = (Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED)
		var want_fire = touch_fire or (mouse_captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
		var want_alt = touch_alt or (mouse_captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))
		if fire_cd <= 0.0:
			if want_fire:
				_fire_weapon(false)
			elif want_alt:
				_fire_weapon(true)

		var move_ratio = clamp(Vector2(velocity.x, velocity.z).length() / max_spd, 0.0, 1.2)
		if is_on_floor() and move_ratio > 0.15:
			bob_t += delta * 11.5 * move_ratio
			step_accum += delta * move_ratio
			if step_accum >= 0.36:
				step_accum = 0.0
				arena.sfx.play_sfx("step")
		recoil_z = lerp(recoil_z, 0.0, clamp(delta * 11.0, 0.0, 1.0))
		recoil_pitch = lerp(recoil_pitch, 0.0, clamp(delta * 10.0, 0.0, 1.0))
		weapon_pivot.position = Vector3(
			0.28 + cos(bob_t * 0.5) * 0.014 * move_ratio,
			-0.25 + abs(sin(bob_t)) * 0.018 * move_ratio,
			-0.50 + recoil_z
		)
		weapon_pivot.rotation.x = recoil_pitch

		if anim_shock_core != null:
			anim_shock_core.rotation.z += delta * (6.5 if muzzle_timer > 0.0 else 1.8)
		if anim_flak_jaw_l != null and anim_flak_jaw_r != null:
			var spread_x = 0.082 + recoil_z * 0.25
			anim_flak_jaw_l.position.x = -spread_x
			anim_flak_jaw_r.position.x = spread_x
		if anim_rkt_barrels != null and recoil_z > 0.01:
			anim_rkt_barrels.rotation.z += delta * 9.0
		if anim_link_ring != null:
			anim_link_ring.rotation.z += delta * (14.0 if want_fire or want_alt else 3.2)

		var right_vel = velocity.dot(global_transform.basis.x)
		cam.rotation.z = lerp(cam.rotation.z, clamp(-right_vel * 0.004, -0.045, 0.045), delta * 8.0)

		if shake_intensity > 0.005:
			cam.h_offset = randf_range(-shake_intensity, shake_intensity)
			cam.v_offset = randf_range(-shake_intensity, shake_intensity)
			shake_intensity = max(0.0, shake_intensity - delta * 1.4)
		else:
			cam.h_offset = 0.0
			cam.v_offset = 0.0

		if muzzle_timer > 0.0:
			muzzle_timer -= delta
			muzzle_group.visible = true
			muzzle_group.rotation.z += delta * 24.0
		else:
			muzzle_group.visible = false

	func _fire_weapon(is_alt: bool) -> void:
		var is_insta = (arena.cfg_mode == 2)
		var mult = 2.0 if udamage_timer > 0.0 else 1.0
		var cam_pos = cam.global_position
		var cam_dir = -cam.global_transform.basis.z
		var muzzle_pos = weapon_pivot.global_position + cam_dir * 0.45

		if current_weapon == 0:
			if not is_alt:
				fire_cd = 0.46 if is_insta else 0.52
				recoil_z = 0.13
				recoil_pitch = 0.08
				add_shake(0.05)
				var beam_col = Color(1.0, 0.22, 0.45) if is_insta else Color(0.82, 0.35, 1.0)
				_flash_muzzle(beam_col)
				arena.sfx.play_sfx("shock_fire")
				var hit = _raycast(cam_pos, cam_pos + cam_dir * 120.0, 1 | 2 | 4, true)
				var end_p = cam_pos + cam_dir * 120.0
				if not hit.is_empty():
					end_p = hit["position"]
					var col_obj = hit["collider"]
					if col_obj is UTShockCore:
						col_obj.detonate_combo(self, mult)
					elif col_obj is UTBot and col_obj.team != team:
						var sdmg = 250 if is_insta else int(48 * mult)
						col_obj.apply_damage(sdmg, self, "InstaGib" if is_insta else "Shock Rifle", cam_dir * 9.5)
						arena.spawn_sparks(end_p, beam_col, 10)
						arena.hud.trigger_hitmarker()
					else:
						arena.spawn_sparks(end_p, beam_col, 8)
				arena.spawn_beam(muzzle_pos, end_p, beam_col, 0.08 if is_insta else 0.065, 0.18)
			else:
				fire_cd = 0.56
				recoil_z = 0.11
				recoil_pitch = 0.06
				_flash_muzzle(Color(0.75, 0.28, 1.0))
				arena.sfx.play_sfx("shock_fire")
				arena.spawn_shock_core(muzzle_pos + cam_dir * 0.4, cam_dir * 14.5, self)

		elif current_weapon == 1:
			if not is_alt:
				fire_cd = 0.68
				recoil_z = 0.18
				recoil_pitch = 0.12
				add_shake(0.08)
				_flash_muzzle(Color(1.0, 0.72, 0.18))
				arena.sfx.play_sfx("flak_fire")
				for i in range(8):
					var spread = Vector3(randf_range(-0.085, 0.085), randf_range(-0.065, 0.065), randf_range(-0.085, 0.085))
					var dir = (cam_dir + spread).normalized()
					arena.spawn_projectile(muzzle_pos, dir * 49.0, "flak", self, int(18 * mult), 0.0, 2)
			else:
				fire_cd = 0.82
				recoil_z = 0.20
				recoil_pitch = 0.14
				add_shake(0.09)
				_flash_muzzle(Color(1.0, 0.60, 0.12))
				arena.sfx.play_sfx("flak_fire")
				var launch = (cam_dir + Vector3(0, 0.18, 0)).normalized() * 30.0
				arena.spawn_projectile(muzzle_pos, launch, "flak_shell", self, int(88 * mult), 5.4, 0)

		elif current_weapon == 2:
			if not is_alt:
				fire_cd = 0.76
				recoil_z = 0.20
				recoil_pitch = 0.13
				add_shake(0.09)
				_flash_muzzle(Color(1.0, 0.42, 0.14))
				arena.sfx.play_sfx("rocket_fire")
				arena.spawn_projectile(muzzle_pos + cam_dir * 0.35, cam_dir * 35.0, "rocket", self, int(94 * mult), 5.8, 0)
			else:
				fire_cd = 1.25
				recoil_z = 0.24
				recoil_pitch = 0.16
				add_shake(0.14)
				_flash_muzzle(Color(1.0, 0.32, 0.10))
				arena.sfx.play_sfx("rocket_fire")
				for ang in [-0.08, 0.0, 0.08]:
					var rdir = cam_dir.rotated(Vector3.UP, ang)
					arena.spawn_projectile(muzzle_pos + rdir * 0.4, rdir * 33.0, "rocket", self, int(70 * mult), 5.0, 0)

		elif current_weapon == 3:
			if not is_alt:
				fire_cd = 0.115
				recoil_z = 0.045
				recoil_pitch = 0.03
				_flash_muzzle(Color(0.25, 1.0, 0.40))
				arena.sfx.play_sfx("link_fire")
				arena.spawn_projectile(muzzle_pos, cam_dir * 54.0, "plasma", self, int(23 * mult), 0.0, 0)
			else:
				fire_cd = 0.09
				recoil_z = 0.025
				_flash_muzzle(Color(0.25, 1.0, 0.45))
				arena.sfx.play_sfx("link_fire")
				var hit2 = _raycast(cam_pos, cam_pos + cam_dir * 27.0, 1 | 2, false)
				var end2 = cam_pos + cam_dir * 27.0
				if not hit2.is_empty():
					end2 = hit2["position"]
					var co = hit2["collider"]
					if co is UTBot and co.team != team:
						co.apply_damage(int(19 * mult), self, "Link Beam", cam_dir * 2.5)
						arena.hud.trigger_hitmarker()
				arena.spawn_beam(muzzle_pos, end2, Color(0.25, 1.0, 0.42), 0.052, 0.10)

	func _flash_muzzle(col: Color) -> void:
		muzzle_mat.albedo_color = col
		muzzle_timer = 0.06

	func _raycast(from_pos: Vector3, to_pos: Vector3, mask: int, check_areas: bool) -> Dictionary:
		var space = get_world_3d().direct_space_state
		var q = PhysicsRayQueryParameters3D.create(from_pos, to_pos, mask)
		q.exclude = [get_rid()]
		q.collide_with_areas = check_areas
		return space.intersect_ray(q)

	func apply_damage(dmg: int, attacker, weapon_name: String, impulse: Vector3) -> void:
		if not alive or arena.game_state != 1:
			return
		velocity += impulse
		var absorb = min(armor, int(round(float(dmg) * 0.6)))
		armor -= absorb
		hp -= (dmg - absorb)
		add_shake(0.14)
		arena.hud.flash_screen(Color(1.0, 0.12, 0.08, 0.36))
		if hp <= 0:
			hp = 0
			alive = false
			respawn_timer = 2.4
			arena.register_kill(attacker, self, weapon_name)
			arena.hud.show_banner("FRAGGED! RESPAWNING...", Color(1.0, 0.25, 0.2))

	func register_player_kill(weapon_name: String) -> void:
		kill_streak += 1
		multi_kill += 1
		multi_kill_timer = 4.5
		if not arena.first_blood_done:
			arena.first_blood_done = true
			arena.hud.show_banner("FIRST BLOOD!", Color(1.0, 0.25, 0.18))
			arena.sfx.play_announcer("ann_firstblood")
		elif weapon_name == "Shock Combo":
			arena.hud.show_banner("SHOCK COMBO!", Color(0.85, 0.35, 1.0))
			arena.sfx.play_announcer("ann_combo")
		elif multi_kill == 2:
			arena.hud.show_banner("DOUBLE KILL!", Color(1.0, 0.72, 0.18))
			arena.sfx.play_announcer("ann_double")
		elif multi_kill == 3:
			arena.hud.show_banner("MULTI KILL!", Color(1.0, 0.45, 0.15))
			arena.sfx.play_announcer("ann_multi")
		elif multi_kill >= 4:
			arena.hud.show_banner("MONSTER KILL!", Color(1.0, 0.18, 0.35))
			arena.sfx.play_announcer("ann_monster")
		elif kill_streak == 5:
			arena.hud.show_banner("KILLING SPREE!", Color(0.25, 0.92, 1.0))
			arena.sfx.play_announcer("ann_spree")
		elif kill_streak == 10:
			arena.hud.show_banner("UNSTOPPABLE!", Color(1.0, 0.85, 0.15))
			arena.sfx.play_announcer("ann_unstoppable")

# ==============================================================================
# SKELETAL 3D SOLDIER BOT (Clean Strafing + Proper Death Pose + Map Roaming)
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
	var death_anim_done: bool = false

	var visual_root: Node3D = null
	var body_rig: Node3D = null
	var gun_pivot: Node3D = null
	var muzzle_marker: Node3D = null
	var gun_glow_mat: StandardMaterial3D = null
	var anim_player: AnimationPlayer = null
	var anim_idle: String = ""
	var anim_run: String = ""
	var current_anim: String = ""

	var active_weapon: int = 3
	var strafe_dir: float = 1.0
	var strafe_timer: float = 1.2
	var fire_cd: float = 0.65
	var jump_cd: float = 1.0
	var dodge_cd: float = 1.5
	var waypoint: Vector3 = Vector3.ZERO
	var waypoint_timer: float = 0.0
	var stuck_timer: float = 0.0
	var last_pos: Vector3 = Vector3.ZERO

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
		body_rig = Node3D.new()
		visual_root.add_child(body_rig)
		_build_visual()

	func _build_visual() -> void:
		var is_blue = (team == 0)
		var glow_mat = arena.mat_glow_cyan if is_blue else arena.mat_glow_red
		var team_mat = arena.mat_team_blue if is_blue else arena.mat_team_red
		if team >= 10:
			glow_mat = arena.mat_glow_orange if (team % 2 == 0) else arena.mat_glow_red
			team_mat = arena.mat_glow_orange if (team % 2 == 0) else arena.mat_team_red
		var armor_tint = Color(0.28, 0.72, 1.0) if is_blue else Color(1.0, 0.26, 0.22)

		gun_glow_mat = StandardMaterial3D.new()
		gun_glow_mat.albedo_color = glow_mat.albedo_color
		gun_glow_mat.emission_enabled = true
		gun_glow_mat.emission = glow_mat.albedo_color
		gun_glow_mat.emission_energy_multiplier = 2.8

		if arena.soldier_scene != null:
			var model = arena.soldier_scene.instantiate()
			model.scale = Vector3(1.08, 1.08, 1.08)
			model.rotation.y = PI
			body_rig.add_child(model)
			_tint_meshes(model, armor_tint)

			var skel = _find_skeleton(model)
			if skel != null:
				_attach_bone_gear(skel, glow_mat, team_mat)

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
					elif low.find("idle") != -1:
						anim_idle = n
				if anim_run == "" and names.size() > 0:
					anim_run = names[0]
				if anim_idle == "":
					anim_idle = anim_run
		else:
			_part(body_rig, Vector3(0, 1.15, 0), Vector3(0.56, 0.68, 0.34), team_mat)
			_part(body_rig, Vector3(0, 1.66, 0), Vector3(0.32, 0.34, 0.34), team_mat)
			_part(body_rig, Vector3(-0.16, 0.45, 0), Vector3(0.20, 0.85, 0.22), arena.mat_dark_steel)
			_part(body_rig, Vector3(0.16, 0.45, 0), Vector3(0.20, 0.85, 0.22), arena.mat_dark_steel)
			_part(body_rig, Vector3(-0.38, 1.15, 0), Vector3(0.18, 0.68, 0.20), team_mat)
			_part(body_rig, Vector3(0.38, 1.15, -0.15), Vector3(0.18, 0.62, 0.20), team_mat)
			_part(body_rig, Vector3(0, 1.68, -0.18), Vector3(0.26, 0.09, 0.06), glow_mat)

		# Clear bright team shoulder pauldrons & crest so allies vs enemies pop immediately
		_part(body_rig, Vector3(-0.36, 1.46, 0.0), Vector3(0.18, 0.14, 0.24), team_mat)
		_part(body_rig, Vector3(0.36, 1.46, 0.0), Vector3(0.18, 0.14, 0.24), team_mat)
		_part(body_rig, Vector3(0.0, 1.76, -0.02), Vector3(0.08, 0.10, 0.26), glow_mat)

		gun_pivot = Node3D.new()
		gun_pivot.position = Vector3(0.30, 1.32, 0.0)
		body_rig.add_child(gun_pivot)

		_part(gun_pivot, Vector3(0.0, 0.0, -0.24), Vector3(0.11, 0.13, 0.64), arena.mat_dark_steel)
		_part(gun_pivot, Vector3(0.0, 0.05, -0.28), Vector3(0.06, 0.04, 0.48), gun_glow_mat)
		_part(gun_pivot, Vector3(0.0, -0.05, -0.12), Vector3(0.05, 0.08, 0.10), arena.mat_chrome)

		muzzle_marker = Node3D.new()
		muzzle_marker.position = Vector3(0.0, 0.02, -0.62)
		gun_pivot.add_child(muzzle_marker)

	func _set_bot_weapon(wep_idx: int) -> void:
		active_weapon = wep_idx
		if gun_glow_mat == null:
			return
		var col = Color(0.82, 0.32, 1.0)
		if wep_idx == 1:
			col = Color(1.0, 0.62, 0.14)
		elif wep_idx == 2:
			col = Color(1.0, 0.26, 0.18)
		elif wep_idx == 3:
			col = Color(0.22, 1.0, 0.42)
		gun_glow_mat.albedo_color = col
		gun_glow_mat.emission = col

	func _attach_bone_gear(skel: Skeleton3D, glow_mat: Material, team_mat: Material) -> void:
		var chest_idx = -1
		var head_idx = -1
		for i in range(skel.get_bone_count()):
			var bname = skel.get_bone_name(i).to_lower()
			if bname.find("spine2") != -1 and chest_idx == -1:
				chest_idx = i
			elif bname.find("head") != -1 and head_idx == -1:
				head_idx = i

		if chest_idx != -1:
			var ba_c = BoneAttachment3D.new()
			ba_c.bone_name = skel.get_bone_name(chest_idx)
			skel.add_child(ba_c)
			_part(ba_c, Vector3(0, 0.08, -0.14), Vector3(0.24, 0.26, 0.10), team_mat)

		if head_idx != -1:
			var ba_h = BoneAttachment3D.new()
			ba_h.bone_name = skel.get_bone_name(head_idx)
			skel.add_child(ba_h)
			_part(ba_h, Vector3(0, 0.10, 0.11), Vector3(0.18, 0.06, 0.06), glow_mat)

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
						dup.metallic = 0.45
						dup.roughness = 0.38
						mi.set_surface_override_material(s, dup)
		for c in node.get_children():
			_tint_meshes(c, tint)

	func _find_skeleton(node: Node) -> Skeleton3D:
		if node is Skeleton3D:
			return node
		for c in node.get_children():
			var found = _find_skeleton(c)
			if found != null:
				return found
		return null

	func _find_anim_player(node: Node) -> AnimationPlayer:
		if node is AnimationPlayer:
			return node
		for c in node.get_children():
			var found = _find_anim_player(c)
			if found != null:
				return found
		return null

	func _play_anim(name: String, spd: float = 1.0) -> void:
		if anim_player == null or name == "":
			return
		if current_anim != name:
			current_anim = name
			anim_player.play(name, 0.15)
		anim_player.speed_scale = spd

	func _freeze_death_anim() -> void:
		if anim_player != null:
			if anim_idle != "":
				anim_player.play(anim_idle, 0.05)
			anim_player.speed_scale = 0.0

	func respawn() -> void:
		alive = true
		death_anim_done = false
		hp = 100
		armor = 0 if arena.cfg_mode == 2 else 20
		udamage_timer = 0.0
		velocity = Vector3.ZERO
		global_position = arena.get_spawn_point(team) + Vector3(randf_range(-2.4, 2.4), 0.1, randf_range(-2.4, 2.4))
		last_pos = global_position
		stuck_timer = 0.0
		current_anim = ""
		visual_root.visible = true
		body_rig.rotation = Vector3.ZERO
		body_rig.position = Vector3.ZERO
		collision_layer = 2
		_pick_map_waypoint()

	func _pick_map_waypoint() -> void:
		if arena.cfg_mode != 2:
			var best_p = Vector3.ZERO
			var found_p = false
			var best_score = 999.0
			for p in arena.pickups:
				if not p["active"]:
					continue
				var d = global_position.distance_to(p["pos"])
				if hp < 55 and p["kind"] == "health" and d < best_score:
					best_score = d
					best_p = p["pos"]
					found_p = true
				elif not found_p and (p["kind"] == "udamage" or (armor < 40 and p["kind"] == "armor")) and d < 22.0:
					best_score = d
					best_p = p["pos"]
					found_p = true
			if found_p:
				waypoint = best_p
				waypoint_timer = 3.5
				return

		# Wide spread across all sectors of DM-Deck17
		var spots = [
			Vector3(-19.5, 4.6, -16.0), # NW upper balcony
			Vector3(19.5, 4.6, -16.0),  # NE upper balcony
			Vector3(-19.5, 4.6, 16.0),  # SW upper balcony
			Vector3(19.5, 4.6, 16.0),   # SE upper balcony
			Vector3(0.0, 4.6, -23.5),   # North upper catwalk
			Vector3(0.0, 4.6, 23.5),    # South upper catwalk
			Vector3(0.0, 4.6, 0.0),     # Central bridge
			Vector3(-12.5, 0.2, -13.0), # NW ramp base
			Vector3(12.5, 0.2, 13.0),   # SE ramp base
			Vector3(13.5, 0.2, -14.5),  # NE jump pad
			Vector3(-13.5, 0.2, 14.5),  # SW jump pad
			Vector3(-18.0, 0.2, 0.0),   # West lower lane
			Vector3(18.0, 0.2, 0.0),    # East lower lane
			Vector3(0.0, 0.2, -21.0),   # North lower hall
			Vector3(0.0, 0.2, 21.0)     # South lower hall
		]
		var next_w = spots[randi() % spots.size()]
		if next_w.distance_to(global_position) < 4.5:
			next_w = spots[(randi() + 5) % spots.size()]
		waypoint = next_w
		waypoint_timer = randf_range(2.8, 4.8)

	func _find_target():
		var best = null
		var best_dist = 999.0
		var candidates: Array = []
		if arena.game_state == 1:
			candidates.append(arena.player)
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
		if arena.game_state == 2:
			return
		if not alive:
			respawn_timer -= delta
			# Fall back cleanly onto ground without running legs
			body_rig.rotation.x = lerp(body_rig.rotation.x, -1.48, clamp(delta * 9.0, 0.0, 1.0))
			body_rig.position.y = lerp(body_rig.position.y, -0.55, clamp(delta * 8.0, 0.0, 1.0))
			if body_rig.rotation.x <= -1.25 and not death_anim_done:
				death_anim_done = true
				_freeze_death_anim()
			if respawn_timer <= 0.0:
				respawn()
			return

		if udamage_timer > 0.0:
			udamage_timer = max(0.0, udamage_timer - delta)
		if fire_cd > 0.0:
			fire_cd -= delta
		if jump_cd > 0.0:
			jump_cd -= delta
		if dodge_cd > 0.0:
			dodge_cd -= delta
		strafe_timer -= delta
		if strafe_timer <= 0.0:
			strafe_timer = randf_range(0.65, 1.45)
			strafe_dir = -strafe_dir

		if not is_on_floor():
			velocity.y -= 23.0 * delta

		var target = _find_target()
		var see_target = false
		var move_dir = Vector3.ZERO

		if target != null:
			see_target = _has_los(target)

		if target != null and see_target and (hp >= 30 or arena.cfg_mode == 2):
			var to_t = target.global_position - global_position
			var flat_t = Vector3(to_t.x, 0.0, to_t.z)
			var dist = flat_t.length()
			var fwd = flat_t.normalized() if dist > 0.05 else -global_transform.basis.z
			var right = Vector3(-fwd.z, 0.0, fwd.x)

			var desired_yaw = atan2(-fwd.x, -fwd.z)
			rotation.y = lerp_angle(rotation.y, desired_yaw, clamp(delta * 12.0, 0.0, 1.0))
			var aim_pt = target.global_position + Vector3(0, 1.22, 0)
			var up_v = Vector3.UP if abs(gun_pivot.global_position.direction_to(aim_pt).dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
			gun_pivot.look_at(aim_pt, up_v)

			if arena.cfg_mode == 2:
				_set_bot_weapon(0)
			elif dist < 9.5:
				_set_bot_weapon(1)
			elif dist > 22.0:
				_set_bot_weapon(2 if randf() < 0.65 else 0)
			else:
				_set_bot_weapon(3 if randf() < 0.6 else 0)

			# Combine strafe + forward/back in world space, then align body_rig naturally to velocity direction
			move_dir = right * strafe_dir * 0.90
			if dist > 16.0:
				move_dir += fwd * 0.75
			elif dist < 6.0:
				move_dir -= fwd * 0.60

			if is_on_floor() and jump_cd <= 0.0 and randf() < 0.03:
				velocity.y = 8.9
				jump_cd = randf_range(1.4, 2.8)

			if fire_cd <= 0.0 and dist < 48.0:
				_fire_at(aim_pt, dist)
		else:
			waypoint_timer -= delta
			if waypoint_timer <= 0.0 or global_position.distance_to(waypoint) < 2.4:
				_pick_map_waypoint()
			var to_w = waypoint - global_position
			to_w.y = 0.0
			if to_w.length() > 0.2:
				move_dir = to_w.normalized()
				var wyaw = atan2(-move_dir.x, -move_dir.z)
				rotation.y = lerp_angle(rotation.y, wyaw, clamp(delta * 8.5, 0.0, 1.0))
				gun_pivot.rotation = Vector3.ZERO

		# Light anti-clumping nudge so bots spread across the arena instead of stacking on one spot
		for other in arena.bots:
			if other != self and is_instance_valid(other) and other.alive:
				var diff = global_position - other.global_position
				diff.y = 0.0
				var d_o = diff.length()
				if d_o > 0.01 and d_o < 2.2:
					move_dir += (diff / d_o) * ((2.2 - d_o) * 0.65)

		# Acid pit avoidance steering
		if global_position.y < 2.2:
			var next_p = global_position + move_dir * 2.4
			if abs(next_p.x) < 7.8 and abs(next_p.z) < 9.8:
				var away = Vector3(global_position.x, 0.0, global_position.z).normalized()
				var tang = Vector3(-away.z, 0.0, away.x) * strafe_dir
				move_dir = (away * 0.8 + tang * 0.85).normalized()

		# Anti-stuck guard
		if global_position.distance_to(last_pos) < 0.25:
			stuck_timer += delta
			if stuck_timer > 0.75:
				stuck_timer = 0.0
				strafe_dir = -strafe_dir
				if is_on_floor():
					velocity.y = 8.6
				_pick_map_waypoint()
				var escape = (waypoint - global_position)
				escape.y = 0.0
				if escape.length() > 0.1:
					move_dir = (escape.normalized() + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))).normalized()
		else:
			stuck_timer = 0.0
			last_pos = global_position

		var bot_spd = 9.4 if arena.cfg_mode == 2 else (8.2 + float(arena.cfg_difficulty) * 0.8)
		if move_dir.length() > 0.05:
			move_dir = move_dir.normalized()
			var hlen = Vector2(velocity.x, velocity.z).length()
			var smooth = 4.0 if hlen > bot_spd + 1.5 else 9.0
			velocity.x = lerp(velocity.x, move_dir.x * bot_spd, clamp(delta * smooth, 0.0, 1.0))
			velocity.z = lerp(velocity.z, move_dir.z * bot_spd, clamp(delta * smooth, 0.0, 1.0))

			# Turn body_rig toward movement vector when roaming; angle slightly when strafing in combat
			var vel_flat = Vector3(velocity.x, 0.0, velocity.z)
			if vel_flat.length() > 0.6:
				var move_yaw = atan2(-vel_flat.x, -vel_flat.z)
				var rel_yaw = wrapf(move_yaw - rotation.y, -PI, PI)
				body_rig.rotation.y = lerp_angle(body_rig.rotation.y, rel_yaw * 0.65, clamp(delta * 10.0, 0.0, 1.0))
				body_rig.rotation.z = lerp(body_rig.rotation.z, clamp(-sin(rel_yaw) * 0.14, -0.16, 0.16), clamp(delta * 8.0, 0.0, 1.0))

			var anim_spd = clamp(vel_flat.length() / 7.5, 0.75, 1.35)
			_play_anim(anim_run, anim_spd)
		else:
			body_rig.rotation.y = lerp_angle(body_rig.rotation.y, 0.0, clamp(delta * 8.0, 0.0, 1.0))
			body_rig.rotation.z = lerp(body_rig.rotation.z, 0.0, clamp(delta * 8.0, 0.0, 1.0))
			_pick_map_waypoint()
			_play_anim(anim_idle, 1.0)

		move_and_slide()
		arena.check_jump_pads(self)

	func _fire_at(aim_pt: Vector3, dist: float) -> void:
		var diff = arena.cfg_difficulty
		var cd_mult = 1.30 if diff == 0 else (0.95 if diff == 1 else 0.70)
		var spread = 0.085 if diff == 0 else (0.045 if diff == 1 else 0.020)

		var origin = muzzle_marker.global_position
		var dir = (aim_pt - origin).normalized()
		dir += Vector3(randf_range(-spread, spread), randf_range(-spread * 0.6, spread * 0.6), randf_range(-spread, spread))
		dir = dir.normalized()
		var mult = 2.0 if udamage_timer > 0.0 else 1.0

		if arena.cfg_mode == 2:
			fire_cd = randf_range(0.75, 1.20) * cd_mult
			var space = get_world_3d().direct_space_state
			var q = PhysicsRayQueryParameters3D.create(origin, origin + dir * 95.0, 1 | 2)
			q.exclude = [get_rid()]
			var hit = space.intersect_ray(q)
			var end_p = origin + dir * 95.0
			if not hit.is_empty():
				end_p = hit["position"]
				var co = hit["collider"]
				if (co is UTBot or co is UTPlayer) and co.team != team:
					co.apply_damage(250, self, "InstaGib", dir * 9.0)
			arena.spawn_beam(origin, end_p, Color(1.0, 0.25, 0.45), 0.06, 0.16)
			return

		if active_weapon == 1:
			fire_cd = randf_range(0.58, 0.92) * cd_mult
			for i in range(5):
				var fdir = (dir + Vector3(randf_range(-0.075, 0.075), randf_range(-0.045, 0.045), randf_range(-0.075, 0.075))).normalized()
				arena.spawn_projectile(origin, fdir * 44.0, "flak", self, int(10 * mult), 0.0, 1)
		elif active_weapon == 2 and dist > 18.0:
			fire_cd = randf_range(0.78, 1.22) * cd_mult
			arena.spawn_projectile(origin, dir * 32.0, "rocket", self, int(36 * mult), 4.4, 0)
		elif active_weapon == 0:
			fire_cd = randf_range(0.68, 1.05) * cd_mult
			var space = get_world_3d().direct_space_state
			var q = PhysicsRayQueryParameters3D.create(origin, origin + dir * 95.0, 1 | 2)
			q.exclude = [get_rid()]
			var hit = space.intersect_ray(q)
			var end_p = origin + dir * 95.0
			if not hit.is_empty():
				end_p = hit["position"]
				var co = hit["collider"]
				if (co is UTBot or co is UTPlayer) and co.team != team:
					co.apply_damage(int(24 * mult), self, "Shock Rifle", dir * 5.5)
					arena.spawn_sparks(end_p, Color(0.82, 0.35, 1.0), 8)
			arena.spawn_beam(origin, end_p, Color(0.82, 0.35, 1.0), 0.045, 0.14)
		else:
			fire_cd = randf_range(0.32, 0.55) * cd_mult
			arena.spawn_projectile(origin, dir * 45.0, "plasma", self, int(13 * mult), 0.0, 0)

	func apply_damage(dmg: int, attacker, weapon_name: String, impulse: Vector3) -> void:
		if not alive:
			return
		velocity += impulse
		var absorb = min(armor, int(round(float(dmg) * 0.5)))
		armor -= absorb
		hp -= (dmg - absorb)

		if is_on_floor() and dodge_cd <= 0.0 and arena.cfg_difficulty >= 1 and randf() < (0.35 if arena.cfg_difficulty == 1 else 0.65):
			var side = global_transform.basis.x * (1.0 if randf() < 0.5 else -1.0)
			velocity.x = side.x * 16.5
			velocity.z = side.z * 16.5
			velocity.y = 4.6
			dodge_cd = 2.0

		if hp <= 0:
			hp = 0
			alive = false
			death_anim_done = false
			respawn_timer = 2.8
			collision_layer = 0
			velocity = Vector3(impulse.x * 0.35, max(velocity.y, 2.2), impulse.z * 0.35)
			_freeze_death_anim()
			arena.register_kill(attacker, self, weapon_name)
			var col = Color(0.2, 0.85, 1.0) if team == 0 else Color(1.0, 0.25, 0.18)
			var fx = UTExplosionFX.new()
			fx.setup(global_position + Vector3(0, 1.0, 0), 1.8, col, 0.28, false)
			arena.add_child(fx)
			arena.effects.append(fx)
			arena.spawn_sparks(global_position + Vector3(0, 1.0, 0), col, 12)

# ==============================================================================
# PROJECTILES, SHOCK CORE & PARTICLE VFX
# ==============================================================================
class UTProjectile extends Node3D:
	var arena: Node3D = null
	var vel: Vector3 = Vector3.ZERO
	var kind: String = "plasma"
	var attacker = null
	var dmg: int = 20
	var splash: float = 0.0
	var bounces: int = 0
	var life: float = 3.6
	var trail_timer: float = 0.0

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
			cm.top_radius = 0.05
			cm.bottom_radius = 0.09
			cm.height = 0.62
			cm.radial_segments = 8
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
			sm.radial_segments = 10
			sm.rings = 6
			mi.mesh = sm
			mi.material_override = arena.mat_glow_orange
		else:
			var sm2 = SphereMesh.new()
			sm2.radius = 0.13
			sm2.height = 0.26
			sm2.radial_segments = 8
			sm2.rings = 6
			mi.mesh = sm2
			mi.material_override = arena.mat_glow_green if (attacker == arena.player or attacker.team == 0) else arena.mat_glow_red
		add_child(mi)

	func step_projectile(delta: float) -> bool:
		life -= delta
		if life <= 0.0:
			return false
		if kind == "flak" or kind == "flak_shell":
			vel.y -= 16.0 * delta

		if kind == "rocket":
			trail_timer -= delta
			if trail_timer <= 0.0:
				trail_timer = 0.035
				var puff = UTExplosionFX.new()
				puff.setup(global_position, 0.32, Color(1.0, 0.62, 0.22), 0.16, false)
				arena.add_child(puff)
				arena.effects.append(puff)

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
					arena.spawn_explosion(hp_pos, splash, Color(1.0, 0.5, 0.12), dmg, attacker, _wep_label(), 12.5)
				else:
					if is_instance_valid(attacker) and col_obj.team != attacker.team:
						col_obj.apply_damage(dmg, attacker, _wep_label(), vel.normalized() * 4.5)
						arena.spawn_sparks(hp_pos, Color(1.0, 0.72, 0.2), 8)
						if attacker == arena.player:
							arena.hud.trigger_hitmarker()
				return false
			else:
				if bounces > 0:
					bounces -= 1
					vel = vel.bounce(hn) * 0.85
					global_position = hp_pos + hn * 0.1
					arena.spawn_sparks(hp_pos, Color(1.0, 0.7, 0.2), 5)
					return true
				if splash > 0.0:
					arena.spawn_explosion(hp_pos + hn * 0.15, splash, Color(1.0, 0.52, 0.12), dmg, attacker, _wep_label(), 13.8)
				else:
					arena.spawn_sparks(hp_pos, Color(0.35, 1.0, 0.45) if kind == "plasma" else Color(1.0, 0.65, 0.2), 7)
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
		sp.radius = 0.78
		cs.shape = sp
		add_child(cs)

		var mi = MeshInstance3D.new()
		var sm = SphereMesh.new()
		sm.radius = 0.34
		sm.height = 0.68
		sm.radial_segments = 12
		sm.rings = 8
		mi.mesh = sm
		mi.material_override = arena.mat_glow_purple
		add_child(mi)

		var ring = MeshInstance3D.new()
		var tm = TorusMesh.new()
		tm.inner_radius = 0.38
		tm.outer_radius = 0.48
		tm.rings = 14
		tm.ring_segments = 8
		ring.mesh = tm
		ring.material_override = arena.mat_glow_cyan
		add_child(ring)

	func detonate_combo(detonator, mult: float) -> void:
		arena.spawn_explosion(global_position, 8.6, Color(0.78, 0.25, 1.0), int(145 * mult), detonator, "Shock Combo", 17.5)
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
			arena.spawn_explosion(hit["position"], 3.6, Color(0.75, 0.25, 1.0), 48, attacker, "Shock Core", 8.0)
			return false
		global_position = to_p
		rotation.y += delta * 5.5
		rotation.x += delta * 3.2
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
		cm.radial_segments = 8
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
	var life: float = 0.34
	var max_life: float = 0.34
	var target_r: float = 3.0
	var mat: StandardMaterial3D = null
	var mesh_node: MeshInstance3D = null
	var ring_node: MeshInstance3D = null

	func setup(p: Vector3, rad: float, col: Color, dur: float, with_ring: bool) -> void:
		position = p
		target_r = rad
		life = dur
		max_life = dur
		mesh_node = MeshInstance3D.new()
		var sm = SphereMesh.new()
		sm.radius = 0.45
		sm.height = 0.9
		sm.radial_segments = 12
		sm.rings = 8
		mesh_node.mesh = sm
		mat = StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(col.r, col.g, col.b, 0.85)
		mesh_node.material_override = mat
		add_child(mesh_node)

		if with_ring:
			ring_node = MeshInstance3D.new()
			var tm = TorusMesh.new()
			tm.inner_radius = 0.45
			tm.outer_radius = 0.68
			tm.rings = 16
			tm.ring_segments = 8
			ring_node.mesh = tm
			ring_node.material_override = mat
			add_child(ring_node)

	func step_fx(delta: float) -> bool:
		life -= delta
		if life <= 0.0:
			return false
		var prog = 1.0 - (life / max_life)
		var sc = lerp(0.35, target_r * 1.4, prog)
		mesh_node.scale = Vector3(sc, sc, sc)
		if ring_node != null:
			var rsc = lerp(0.5, target_r * 2.2, prog)
			ring_node.scale = Vector3(rsc, rsc * 0.4, rsc)
			ring_node.rotation.y += delta * 6.0
		mat.albedo_color.a = clamp((1.0 - prog) * 0.82, 0.0, 1.0)
		return true

class UTSparkBurstFX extends Node3D:
	var life: float = 0.42

	func setup(p: Vector3, col: Color, count: int) -> void:
		position = p
		var cp = CPUParticles3D.new()
		var bm = BoxMesh.new()
		bm.size = Vector3(0.08, 0.08, 0.18)
		var m = StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = col
		cp.mesh = bm
		cp.material_override = m
		cp.amount = count
		cp.lifetime = 0.36
		cp.one_shot = true
		cp.explosiveness = 0.94
		cp.direction = Vector3(0, 1, 0)
		cp.spread = 180.0
		cp.initial_velocity_min = 4.5
		cp.initial_velocity_max = 12.0
		cp.gravity = Vector3(0, -16.0, 0)
		cp.emitting = true
		add_child(cp)

	func step_fx(delta: float) -> bool:
		life -= delta
		return life > 0.0

# ==============================================================================
# NEXT-GEN MOBILE HUD + DYNAMIC HITMARKER + MULTI-TOUCH
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

	var last_vs: Vector2 = Vector2.ZERO
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
		layer = 5
		root = Control.new()
		root.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.draw.connect(_on_draw_hud)
		add_child(root)

		flash_rect = ColorRect.new()
		flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		flash_rect.color = Color(1, 0, 0, 0)
		flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(flash_rect)

		score_lbl = _make_label(22, Color(0.95, 0.98, 1.0))
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

		killfeed_lbl = _make_label(15, Color(0.92, 0.95, 1.0))
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

		status_lbl = _make_label(18, Color(0.96, 0.98, 1.0))
		status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status_lbl.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		status_lbl.offset_top = -44
		root.add_child(status_lbl)

		hp_bar = _make_bar(Color(0.15, 0.85, 0.98))
		armor_bar = _make_bar(Color(1.0, 0.72, 0.15))
		root.add_child(hp_bar)
		root.add_child(armor_bar)

		_layout_controls(true)

	func set_hud_visible(v: bool) -> void:
		root.visible = v
		if not v:
			move_finger = -1
			look_finger = -1
			fire_finger = -1
			alt_finger = -1
			joy_knob = Vector2.ZERO

	func clear_killfeed() -> void:
		killfeed_lines.clear()
		killfeed_lbl.text = ""

	func _make_label(sz: int, col: Color) -> Label:
		var l = Label.new()
		l.add_theme_font_size_override("font_size", sz)
		l.add_theme_color_override("font_color", col)
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.90))
		l.add_theme_constant_override("shadow_offset_x", 2)
		l.add_theme_constant_override("shadow_offset_y", 2)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return l

	func _make_bar(fill_col: Color) -> ProgressBar:
		var pb = ProgressBar.new()
		pb.show_percentage = false
		pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bg = StyleBoxFlat.new()
		bg.bg_color = Color(0.04, 0.06, 0.10, 0.88)
		bg.border_color = Color(0.45, 0.60, 0.75, 0.85)
		bg.set_border_width_all(2)
		bg.set_corner_radius_all(5)
		var fg = StyleBoxFlat.new()
		fg.bg_color = fill_col
		fg.set_corner_radius_all(3)
		pb.add_theme_stylebox_override("background", bg)
		pb.add_theme_stylebox_override("fill", fg)
		return pb

	func _layout_controls(force: bool = false) -> void:
		var vs = get_viewport().get_visible_rect().size
		if not force and vs == last_vs:
			return
		last_vs = vs
		var w = vs.x
		var h = vs.y
		joy_center = Vector2(w * 0.13, h * 0.75)
		joy_radius = clamp(h * 0.135, 72.0, 110.0)

		hp_bar.position = Vector2(w * 0.5 - 175, h - 76)
		hp_bar.size = Vector2(165, 20)
		armor_bar.position = Vector2(w * 0.5 + 10, h - 76)
		armor_bar.size = Vector2(165, 20)

		btn_rects["pause"] = Rect2(18.0, 14.0, 56.0, 44.0)

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
		hitmarker_timer = 0.22
		arena.sfx.play_sfx("hit")

	func show_banner(txt: String, col: Color) -> void:
		banner_lbl.text = txt
		banner_lbl.add_theme_color_override("font_color", col)
		banner_timer = 2.2

	func flash_screen(col: Color) -> void:
		flash_color = col
		flash_alpha = col.a

	func add_killfeed(kname: String, vname: String, wep: String) -> void:
		killfeed_lines.append("%s  [%s]  %s" % [kname, wep, vname])
		if killfeed_lines.size() > 4:
			killfeed_lines.pop_front()
		killfeed_lbl.text = "\n".join(killfeed_lines)

	func _input(event: InputEvent) -> void:
		if not root.visible or arena.game_state != 1:
			return
		var vs = get_viewport().get_visible_rect().size
		if event is InputEventScreenTouch:
			var idx = event.index
			var pos = event.position
			if event.pressed:
				if btn_rects["pause"].has_point(pos):
					arena.pause_match()
					return
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
				if arena.cfg_mode != 2:
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
		if not root.visible:
			return
		_layout_controls(false)
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
		if arena.cfg_mode == 0:
			score_lbl.text = "BLUE %d  |  DECK17 %02d:%02d  |  %d RED" % [arena.score_blue, mins, secs, arena.score_red]
		elif arena.cfg_mode == 1:
			score_lbl.text = "FRAGS %d / %d  |  FFA %02d:%02d" % [arena.player_frags, arena.frag_limit, mins, secs]
		else:
			score_lbl.text = "FRAGS %d / %d  |  INSTAGIB %02d:%02d" % [arena.player_frags, arena.frag_limit, mins, secs]

		fps_lbl.text = "FPS: %d" % Engine.get_frames_per_second()

		var p = arena.player
		if p != null:
			hp_bar.value = clamp(p.hp, 0, 100)
			armor_bar.value = clamp(p.armor, 0, 100)
			var wnames = ["INSTAGIB SHOCK" if arena.cfg_mode == 2 else "SHOCK RIFLE", "FLAK CANNON", "ROCKET LAUNCHER", "LINK GUN"]
			var ud = "  |  2X DMG %.0fs" % p.udamage_timer if p.udamage_timer > 0.0 else ""
			status_lbl.text = "HP %d   |   ARMOR %d   |   %s%s" % [p.hp, p.armor, wnames[p.current_weapon], ud]

		root.queue_redraw()

	func _on_draw_hud() -> void:
		if not root.visible:
			return
		var vs = get_viewport().get_visible_rect().size
		var c = vs * 0.5
		var font = ThemeDB.fallback_font

		var plate = Rect2(vs.x * 0.5 - 190, vs.y - 84, 380, 68)
		root.draw_rect(plate, Color(0.03, 0.05, 0.09, 0.72), true)
		root.draw_rect(plate, Color(0.25, 0.75, 0.95, 0.45), false, 1.5)

		var c_col = Color(1.0, 0.25, 0.45) if arena.cfg_mode == 2 else Color(0.78, 0.35, 1.0)
		if arena.player.current_weapon == 1:
			c_col = Color(1.0, 0.72, 0.15)
		elif arena.player.current_weapon == 2:
			c_col = Color(1.0, 0.32, 0.22)
		elif arena.player.current_weapon == 3:
			c_col = Color(0.22, 1.0, 0.42)
		var ring_r = 11.0 + (hitmarker_timer * 22.0)
		root.draw_arc(c, ring_r, 0.0, TAU, 24, Color(c_col.r, c_col.g, c_col.b, 0.80), 1.8)
		root.draw_line(c + Vector2(-17, 0), c + Vector2(-6, 0), c_col, 2.0)
		root.draw_line(c + Vector2(6, 0), c + Vector2(17, 0), c_col, 2.0)
		root.draw_line(c + Vector2(0, -17), c + Vector2(0, -6), c_col, 2.0)
		root.draw_line(c + Vector2(0, 6), c + Vector2(0, 17), c_col, 2.0)
		root.draw_circle(c, 2.2, Color.WHITE)

		if hitmarker_timer > 0.0:
			var hc = Color(1.0, 0.20, 0.14, clamp(hitmarker_timer * 5.0, 0.0, 1.0))
			root.draw_line(c + Vector2(-15, -15), c + Vector2(-5, -5), hc, 3.2)
			root.draw_line(c + Vector2(15, -15), c + Vector2(5, -5), hc, 3.2)
			root.draw_line(c + Vector2(-15, 15), c + Vector2(-5, 5), hc, 3.2)
			root.draw_line(c + Vector2(15, 15), c + Vector2(5, 5), hc, 3.2)

		root.draw_circle(joy_center, joy_radius, Color(0.06, 0.09, 0.14, 0.36))
		root.draw_arc(joy_center, joy_radius, 0.0, TAU, 36, Color(0.25, 0.85, 1.0, 0.58), 2.2)
		root.draw_circle(joy_center + joy_knob, joy_radius * 0.36, Color(0.25, 0.85, 1.0, 0.62))
		root.draw_arc(joy_center + joy_knob, joy_radius * 0.36, 0.0, TAU, 24, Color(0.9, 0.98, 1.0, 0.85), 2.0)

		_draw_btn(btn_rects["pause"], "||", Color(0.75, 0.85, 1.0), false, font)
		_draw_btn(btn_rects["fire"], "FIRE", Color(0.95, 0.22, 0.18), arena.player.touch_fire, font)
		_draw_btn(btn_rects["alt"], "ALT", Color(0.72, 0.25, 0.98), arena.player.touch_alt, font)
		_draw_btn(btn_rects["jump"], "JUMP", Color(0.18, 0.78, 0.96), false, font)
		_draw_btn(btn_rects["dodge"], "DODGE", Color(0.98, 0.65, 0.14), false, font)

		if arena.cfg_mode != 2:
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

# ==============================================================================
# SLEEK SCI-FI MAIN MENU, PAUSE & MATCH SUMMARY UI
# ==============================================================================
class UTMenuUI extends CanvasLayer:
	var arena: Node3D = null
	var backdrop: ColorRect = null
	var panel: PanelContainer = null
	var title_lbl: Label = null
	var sub_lbl: Label = null
	var sens_lbl: Label = null
	var sens_slider: HSlider = null

	var mode_btn: Button = null
	var bots_btn: Button = null
	var diff_btn: Button = null
	var gfx_btn: Button = null
	var music_btn: Button = null

	var play_btn: Button = null
	var resume_btn: Button = null
	var main_btn: Button = null

	func _ready() -> void:
		layer = 10
		backdrop = ColorRect.new()
		backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
		backdrop.color = Color(0.02, 0.04, 0.08, 0.56)
		add_child(backdrop)

		var center = CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		backdrop.add_child(center)

		panel = PanelContainer.new()
		panel.custom_minimum_size = Vector2(560, 0)
		var psb = StyleBoxFlat.new()
		psb.bg_color = Color(0.05, 0.08, 0.14, 0.90)
		psb.border_color = Color(0.22, 0.82, 1.0, 0.85)
		psb.set_border_width_all(2)
		psb.set_corner_radius_all(10)
		psb.content_margin_left = 28
		psb.content_margin_right = 28
		psb.content_margin_top = 24
		psb.content_margin_bottom = 24
		panel.add_theme_stylebox_override("panel", psb)
		center.add_child(panel)

		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 12)
		panel.add_child(vbox)

		title_lbl = Label.new()
		title_lbl.text = "UNREAL ARENA: DECK 17"
		title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title_lbl.add_theme_font_size_override("font_size", 30)
		title_lbl.add_theme_color_override("font_color", Color(0.25, 0.92, 1.0))
		vbox.add_child(title_lbl)

		sub_lbl = Label.new()
		sub_lbl.text = "NEXT-GEN 3D ARENA SHOOTER  •  MSAA + ORBITAL VIEW"
		sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub_lbl.add_theme_font_size_override("font_size", 14)
		sub_lbl.add_theme_color_override("font_color", Color(0.75, 0.82, 0.92))
		vbox.add_child(sub_lbl)

		var row1 = HBoxContainer.new()
		row1.add_theme_constant_override("separation", 10)
		vbox.add_child(row1)
		mode_btn = _make_btn("MODE: TEAM DM", Color(0.18, 0.62, 0.92), _cycle_mode)
		bots_btn = _make_btn("BOTS: 6", Color(0.18, 0.62, 0.92), _cycle_bots)
		row1.add_child(mode_btn)
		row1.add_child(bots_btn)

		var row2 = HBoxContainer.new()
		row2.add_theme_constant_override("separation", 10)
		vbox.add_child(row2)
		diff_btn = _make_btn("AI: SKILLED", Color(0.85, 0.55, 0.16), _cycle_diff)
		gfx_btn = _make_btn("GFX: 60 FPS MSAA", Color(0.68, 0.30, 0.92), _toggle_gfx)
		row2.add_child(diff_btn)
		row2.add_child(gfx_btn)

		var row3 = HBoxContainer.new()
		row3.add_theme_constant_override("separation", 10)
		vbox.add_child(row3)
		music_btn = _make_btn("MUSIC: ON", Color(0.20, 0.78, 0.45), _toggle_music)
		row3.add_child(music_btn)

		var sens_box = VBoxContainer.new()
		sens_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sens_lbl = Label.new()
		sens_lbl.text = "AIM SENSITIVITY: 1.0x"
		sens_lbl.add_theme_font_size_override("font_size", 14)
		sens_lbl.add_theme_color_override("font_color", Color(0.90, 0.94, 1.0))
		sens_box.add_child(sens_lbl)

		sens_slider = HSlider.new()
		sens_slider.min_value = 0.5
		sens_slider.max_value = 2.0
		sens_slider.step = 0.1
		sens_slider.value = 1.0
		sens_slider.custom_minimum_size = Vector2(200, 28)
		sens_slider.value_changed.connect(_on_sens_changed)
		sens_box.add_child(sens_slider)
		row3.add_child(sens_box)

		resume_btn = _make_btn("RESUME MATCH", Color(0.18, 0.85, 0.42), func(): arena.resume_match())
		resume_btn.custom_minimum_size.y = 54
		vbox.add_child(resume_btn)

		play_btn = _make_btn("PLAY MATCH", Color(0.95, 0.42, 0.14), func(): arena.start_new_match())
		play_btn.custom_minimum_size.y = 58
		vbox.add_child(play_btn)

		main_btn = _make_btn("MAIN MENU", Color(0.42, 0.48, 0.58), func(): arena.return_to_main_menu())
		vbox.add_child(main_btn)

		_refresh_labels()

	func _make_btn(txt: String, col: Color, cb: Callable) -> Button:
		var b = Button.new()
		b.text = txt
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 48)
		b.add_theme_font_size_override("font_size", 17)
		b.add_theme_color_override("font_color", Color(0.98, 0.99, 1.0))
		var normal = StyleBoxFlat.new()
		normal.bg_color = Color(col.r * 0.35, col.g * 0.35, col.b * 0.35, 0.88)
		normal.border_color = Color(col.r, col.g, col.b, 0.95)
		normal.set_border_width_all(2)
		normal.set_corner_radius_all(6)
		var hover = normal.duplicate()
		hover.bg_color = Color(col.r * 0.55, col.g * 0.55, col.b * 0.55, 0.95)
		b.add_theme_stylebox_override("normal", normal)
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_stylebox_override("pressed", hover)
		b.pressed.connect(cb)
		return b

	func _refresh_labels() -> void:
		var m_names = ["TEAM DM", "FREE FOR ALL", "INSTAGIB"]
		var d_names = ["NOVICE", "SKILLED", "GODLIKE"]
		mode_btn.text = "MODE: " + m_names[arena.cfg_mode]
		bots_btn.text = "BOTS: %d" % arena.cfg_bot_count
		diff_btn.text = "AI: " + d_names[arena.cfg_difficulty]
		gfx_btn.text = "GFX: ULTRA + BLOOM" if arena.cfg_high_gfx else "GFX: 60 FPS MSAA"
		music_btn.text = "MUSIC: ON" if arena.cfg_music_on else "MUSIC: OFF"
		sens_lbl.text = "AIM SENSITIVITY: %.1fx" % arena.cfg_sensitivity

	func _cycle_mode() -> void:
		arena.cfg_mode = (arena.cfg_mode + 1) % 3
		_refresh_labels()

	func _cycle_bots() -> void:
		if arena.cfg_bot_count == 4:
			arena.cfg_bot_count = 6
		elif arena.cfg_bot_count == 6:
			arena.cfg_bot_count = 8
		else:
			arena.cfg_bot_count = 4
		_refresh_labels()

	func _cycle_diff() -> void:
		arena.cfg_difficulty = (arena.cfg_difficulty + 1) % 3
		_refresh_labels()

	func _toggle_gfx() -> void:
		arena.cfg_high_gfx = not arena.cfg_high_gfx
		arena._apply_graphics_settings()
		_refresh_labels()

	func _toggle_music() -> void:
		arena.cfg_music_on = not arena.cfg_music_on
		arena.sfx.set_music_enabled(arena.cfg_music_on)
		_refresh_labels()

	func _on_sens_changed(val: float) -> void:
		arena.cfg_sensitivity = val
		_refresh_labels()

	func open_main_menu() -> void:
		backdrop.visible = true
		title_lbl.text = "UNREAL ARENA: DECK 17"
		title_lbl.add_theme_color_override("font_color", Color(0.25, 0.92, 1.0))
		sub_lbl.text = "NEXT-GEN 3D ARENA SHOOTER  •  MSAA + ORBITAL VIEW"
		play_btn.text = "PLAY MATCH"
		resume_btn.visible = false
		main_btn.visible = false
		_refresh_labels()

	func open_pause_menu() -> void:
		backdrop.visible = true
		title_lbl.text = "MATCH PAUSED"
		title_lbl.add_theme_color_override("font_color", Color(1.0, 0.78, 0.22))
		sub_lbl.text = "FRAGS: %d   •   DEATHS: %d" % [arena.player_frags, arena.player_deaths]
		play_btn.text = "RESTART WITH NEW SETTINGS"
		resume_btn.visible = true
		main_btn.visible = true
		_refresh_labels()

	func open_match_over(winner_text: String, col: Color) -> void:
		backdrop.visible = true
		title_lbl.text = winner_text
		title_lbl.add_theme_color_override("font_color", col)
		sub_lbl.text = "YOUR STATS — FRAGS: %d  |  DEATHS: %d" % [arena.player_frags, arena.player_deaths]
		play_btn.text = "PLAY AGAIN"
		resume_btn.visible = false
		main_btn.visible = true
		_refresh_labels()

	func close_menu() -> void:
		backdrop.visible = false
