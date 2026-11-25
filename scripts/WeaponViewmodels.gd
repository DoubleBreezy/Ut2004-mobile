extends Node3D

# Детализированные 3D-модели 4 культовых пушек Unreal Tournament 2004 от первого лица
# 0: Bio Rifle (GES-24) | 1: Shock Rifle (ASMD) | 2: Flak Cannon | 3: Rocket Launcher

var _models: Array[Node3D] = []
var _current_id: int = 2

var _recoil: float = 0.0
var _switch_anim: float = 0.0
var _bob_time: float = 0.0
var _flash_timer: float = 0.0

var _flak_bolt: MeshInstance3D
var _rocket_cluster: Node3D
var _rocket_spin_target: float = 0.0
var _bio_vials: Array[MeshInstance3D] = []
var _rocket_leds: Array[MeshInstance3D] = []
var _muzzle_flash: MeshInstance3D
var _muzzle_mat: StandardMaterial3D

func _ready() -> void:
	_build_models()
	_build_muzzle_flash()
	set_weapon(_current_id)

func _mat(col: Color, metallic: float = 0.35, rough: float = 0.45, unshaded: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	else:
		m.metallic = metallic
		m.roughness = rough
	return m

func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi

func _add_cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = 10
	mi.mesh = c
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi

func _build_models() -> void:
	var m_dark := _mat(Color(0.14, 0.16, 0.20), 0.5, 0.4)
	var m_steel := _mat(Color(0.45, 0.50, 0.56), 0.7, 0.35)
	var m_yellow := _mat(Color(0.92, 0.72, 0.08), 0.25, 0.45)
	var m_olive := _mat(Color(0.24, 0.27, 0.22), 0.4, 0.5)
	var m_blue_metal := _mat(Color(0.22, 0.30, 0.46), 0.65, 0.32)
	var m_bio_glow := _mat(Color(0.18, 1.0, 0.24), 0.0, 1.0, true)
	var m_shock_glow := _mat(Color(0.76, 0.28, 1.0), 0.0, 1.0, true)
	var m_red_glow := _mat(Color(1.0, 0.22, 0.15), 0.0, 1.0, true)
	var m_amber_glow := _mat(Color(1.0, 0.68, 0.12), 0.0, 1.0, true)

	# --- [0] BIO RIFLE (GES-24) ---
	var bio := Node3D.new()
	_add_box(bio, Vector3(0.15, 0.17, 0.52), Vector3(0.25, -0.23, -0.44), m_dark)
	_add_box(bio, Vector3(0.11, 0.09, 0.28), Vector3(0.25, -0.20, -0.74), m_steel) # нагнетатель
	_add_cyl(bio, 0.075, 0.075, 0.14, Vector3(0.15, -0.25, -0.42), m_steel, Vector3(0, 0, 90)) # боковой барабан
	_add_box(bio, Vector3(0.025, 0.045, 0.025), Vector3(0.25, -0.12, -0.82), m_bio_glow) # мушка
	for i in range(3):
		var vial := _add_cyl(bio, 0.026, 0.026, 0.13, Vector3(0.25, -0.11, -0.32 - i * 0.11), m_bio_glow, Vector3(0, 0, -14))
		_bio_vials.append(vial)
	add_child(bio)
	_models.append(bio)

	# --- [1] SHOCK RIFLE (ASMD) ---
	var shock := Node3D.new()
	_add_box(shock, Vector3(0.13, 0.15, 0.58), Vector3(0.24, -0.22, -0.46), m_blue_metal)
	# Две рельсы ускорителя ствола
	_add_box(shock, Vector3(0.035, 0.04, 0.44), Vector3(0.19, -0.19, -0.74), m_steel)
	_add_box(shock, Vector3(0.035, 0.04, 0.44), Vector3(0.29, -0.19, -0.74), m_steel)
	# Фиолетовое плазменное ядро между рельсами
	_add_cyl(shock, 0.022, 0.022, 0.42, Vector3(0.24, -0.19, -0.72), m_shock_glow, Vector3(90, 0, 0))
	# Нижний энергомагазин
	_add_box(shock, Vector3(0.07, 0.15, 0.11), Vector3(0.24, -0.34, -0.42), m_shock_glow)
	# Рамка голографического прицела
	_add_box(shock, Vector3(0.08, 0.012, 0.015), Vector3(0.24, -0.10, -0.38), m_steel)
	_add_box(shock, Vector3(0.012, 0.05, 0.015), Vector3(0.20, -0.125, -0.38), m_steel)
	_add_box(shock, Vector3(0.012, 0.05, 0.015), Vector3(0.28, -0.125, -0.38), m_steel)
	_add_box(shock, Vector3(0.015, 0.015, 0.015), Vector3(0.24, -0.125, -0.38), m_shock_glow)
	add_child(shock)
	_models.append(shock)

	# --- [2] FLAK CANNON (Зенитная шрапнельная пушка UT2004) ---
	var flak := Node3D.new()
	_add_box(flak, Vector3(0.20, 0.19, 0.52), Vector3(0.26, -0.24, -0.43), m_yellow) # жёлтый индустриальный кожух
	_add_box(flak, Vector3(0.22, 0.06, 0.24), Vector3(0.26, -0.24, -0.66), m_dark)   # широкий раструб дула
	_add_box(flak, Vector3(0.08, 0.17, 0.16), Vector3(0.13, -0.25, -0.42), m_dark, Vector3(0, 0, -18)) # боковой магазин
	_flak_bolt = _add_box(flak, Vector3(0.13, 0.06, 0.25), Vector3(0.26, -0.13, -0.40), m_steel) # подвижный верхний затвор
	_add_box(flak, Vector3(0.06, 0.025, 0.02), Vector3(0.26, -0.11, -0.68), m_red_glow) # прицельная планка
	_add_box(flak, Vector3(0.18, 0.02, 0.12), Vector3(0.26, -0.24, -0.74), m_amber_glow) # горящее нутро ствола
	add_child(flak)
	_models.append(flak)

	# --- [3] ROCKET LAUNCHER (Трёхствольный вращающийся гранатомёт UT2004) ---
	var rkt := Node3D.new()
	_add_box(rkt, Vector3(0.21, 0.22, 0.44), Vector3(0.27, -0.24, -0.38), m_olive) # задний бронекожух
	_add_box(rkt, Vector3(0.07, 0.09, 0.16), Vector3(0.15, -0.18, -0.44), m_dark)  # блок целеуказания
	# 3 индикатора зарядки залпа
	for i in range(3):
		var led := _add_box(rkt, Vector3(0.018, 0.018, 0.018), Vector3(0.11, -0.16 - i * 0.025, -0.40), m_dark)
		_rocket_leds.append(led)
	# Вращающийся блок из 3 стволов треугольником
	_rocket_cluster = Node3D.new()
	_rocket_cluster.position = Vector3(0.27, -0.22, -0.66)
	var offsets := [Vector3(0, 0.058, 0), Vector3(-0.052, -0.034, 0), Vector3(0.052, -0.034, 0)]
	for off in offsets:
		_add_cyl(_rocket_cluster, 0.042, 0.042, 0.42, off, m_steel, Vector3(90, 0, 0))
	rkt.add_child(_rocket_cluster)
	add_child(rkt)
	_models.append(rkt)

func _build_muzzle_flash() -> void:
	_muzzle_flash = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.12
	sph.height = 0.24
	sph.radial_segments = 8
	sph.rings = 4
	_muzzle_flash.mesh = sph
	_muzzle_mat = _mat(Color(1.0, 0.85, 0.2), 0.0, 1.0, true)
	_muzzle_flash.material_override = _muzzle_mat
	_muzzle_flash.position = Vector3(0.25, -0.20, -0.92)
	_muzzle_flash.visible = false
	add_child(_muzzle_flash)

func set_weapon(id: int) -> void:
	_current_id = clampi(id, 0, _models.size() - 1)
	for i in range(_models.size()):
		_models[i].visible = (i == _current_id)
	_switch_anim = 1.0

func trigger_recoil(strength: float, flash_color: Color) -> void:
	_recoil = clampf(strength, 0.4, 1.5)
	_muzzle_mat.albedo_color = flash_color
	_muzzle_flash.visible = true
	_muzzle_flash.scale = Vector3(1.2, 1.2, 1.2)
	_flash_timer = 0.06
	if _current_id == 3:
		_rocket_spin_target += TAU / 3.0

func set_charge_level(weapon_id: int, level: int) -> void:
	if weapon_id == 0:
		var sc := 1.0 + level * 0.08
		for v in _bio_vials:
			v.scale = Vector3(sc, 1.0, sc)
	elif weapon_id == 3:
		var m_on := _mat(Color(1.0, 0.2, 0.1), 0.0, 1.0, true)
		var m_off := _mat(Color(0.18, 0.18, 0.20), 0.2, 0.6)
		for i in range(_rocket_leds.size()):
			_rocket_leds[i].material_override = m_on if i < level else m_off

func update_motion(delta: float, move_speed_ratio: float, grounded: bool) -> void:
	_recoil = maxf(0.0, _recoil - delta * 6.5)
	_switch_anim = maxf(0.0, _switch_anim - delta * 5.0)

	if move_speed_ratio > 0.1 and grounded:
		_bob_time += delta * 11.5
	else:
		_bob_time = lerpf(_bob_time, 0.0, delta * 6.0)

	var bob_x := cos(_bob_time * 0.5) * 0.018 * move_speed_ratio
	var bob_y := absf(sin(_bob_time * 0.5)) * -0.022 * move_speed_ratio

	position = Vector3(bob_x, bob_y - _switch_anim * 0.24, _recoil * 0.14)
	rotation_degrees.x = _recoil * 7.5 - _switch_anim * 18.0

	# Анимация затвора Flak Cannon
	if _flak_bolt:
		_flak_bolt.position.z = -0.40 + _recoil * 0.12

	# Плавный поворот тройного блока стволов Rocket Launcher
	if _rocket_cluster:
		_rocket_cluster.rotation.z = lerpf(_rocket_cluster.rotation.z, _rocket_spin_target, delta * 14.0)

	# Затухание дульной вспышки
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_muzzle_flash.visible = false
