extends CanvasLayer

var player: CharacterBody3D = null

var _joy_index: int = -1
var _look_index: int = -1
var _joy_center := Vector2(125, 575)
var _joy_radius := 72.0

var _fire_held := false
var _alt_held := false
var _alt_charge_timer := 0.0

var _lbl_score: Label
var _lbl_fps: Label
var _lbl_announce: Label
var _lbl_stats: Label
var _joy_knob: ColorRect
var _charge_bg: ColorRect
var _charge_fill: ColorRect
var _announce_timer := 0.0

const WPN_NAMES := ["BIO RIFLE", "SHOCK RIFLE", "FLAK CANNON", "ROCKET LAUNCHER"]

func bind_player(p: CharacterBody3D) -> void:
	player = p

func _ready() -> void:
	_build_ui()
	GameMode.score_updated.connect(_on_score_updated)
	GameMode.announcement.connect(_on_announcement)
	GameMode.match_ended.connect(_on_match_ended)

func _build_ui() -> void:
	_lbl_score = Label.new()
	_lbl_score.text = "RED 0  |  TEAM DEATHMATCH  |  0 BLUE"
	_lbl_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_score.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_lbl_score.position.y = 10
	_lbl_score.add_theme_font_size_override("font_size", 24)
	add_child(_lbl_score)

	_lbl_fps = Label.new()
	_lbl_fps.text = "FPS: 60"
	_lbl_fps.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_lbl_fps.offset_left = -130
	_lbl_fps.offset_top = 12
	_lbl_fps.add_theme_font_size_override("font_size", 20)
	_lbl_fps.modulate = Color(0.3, 1.0, 0.45)
	add_child(_lbl_fps)

	_lbl_announce = Label.new()
	_lbl_announce.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_announce.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_lbl_announce.position.y = 62
	_lbl_announce.add_theme_font_size_override("font_size", 36)
	_lbl_announce.modulate = Color(1.0, 0.85, 0.15)
	add_child(_lbl_announce)

	var cross_h := ColorRect.new()
	cross_h.size = Vector2(20, 2)
	cross_h.color = Color(0.25, 1.0, 0.45, 0.9)
	cross_h.set_anchors_preset(Control.PRESET_CENTER)
	cross_h.offset_left = -10
	cross_h.offset_top = -1
	add_child(cross_h)

	var cross_v := ColorRect.new()
	cross_v.size = Vector2(2, 20)
	cross_v.color = Color(0.25, 1.0, 0.45, 0.9)
	cross_v.set_anchors_preset(Control.PRESET_CENTER)
	cross_v.offset_left = -1
	cross_v.offset_top = -10
	add_child(cross_v)

	# Шкала зарядки ALT-огня (Bio Rifle / Rocket Launcher)
	_charge_bg = ColorRect.new()
	_charge_bg.size = Vector2(140, 10)
	_charge_bg.color = Color(0.08, 0.1, 0.15, 0.75)
	_charge_bg.set_anchors_preset(Control.PRESET_CENTER)
	_charge_bg.offset_left = -70
	_charge_bg.offset_top = 28
	_charge_bg.visible = false
	add_child(_charge_bg)

	_charge_fill = ColorRect.new()
	_charge_fill.size = Vector2(0, 10)
	_charge_fill.color = Color(0.2, 1.0, 0.35, 0.95)
	_charge_bg.add_child(_charge_fill)

	_lbl_stats = Label.new()
	_lbl_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_stats.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_lbl_stats.offset_top = -54
	_lbl_stats.add_theme_font_size_override("font_size", 24)
	add_child(_lbl_stats)

	var joy_bg := ColorRect.new()
	joy_bg.size = Vector2(150, 150)
	joy_bg.position = _joy_center - Vector2(75, 75)
	joy_bg.color = Color(0.1, 0.15, 0.25, 0.35)
	joy_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(joy_bg)

	_joy_knob = ColorRect.new()
	_joy_knob.size = Vector2(52, 52)
	_joy_knob.position = _joy_center - Vector2(26, 26)
	_joy_knob.color = Color(0.65, 0.35, 1.0, 0.78)
	_joy_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_joy_knob)

	_make_touch_btn("FIRE", Rect2(1110, 520, 140, 125), Color(0.85, 0.15, 0.15, 0.78),
		func(): _fire_held = true,
		func(): _fire_held = false)

	_make_touch_btn("ALT\nFIRE", Rect2(960, 540, 130, 105), Color(0.55, 0.2, 0.9, 0.78),
		func():
			_alt_held = true
			_alt_charge_timer = 0.0
			if player: player.weapons.fire_alt_pressed(),
		func():
			_alt_held = false
			if player: player.weapons.fire_alt_released())

	_make_touch_btn("JUMP", Rect2(1130, 415, 120, 88), Color(0.15, 0.65, 0.85, 0.75),
		func(): if player: player.trigger_jump(), func(): pass)

	_make_touch_btn("DODGE", Rect2(990, 415, 120, 88), Color(0.95, 0.65, 0.1, 0.78),
		func(): if player: player.trigger_dodge(), func(): pass)

	var wpn_labels := ["1:BIO", "2:SHK", "3:FLK", "4:RKT"]
	for i in range(4):
		var idx := i
		_make_touch_btn(wpn_labels[i], Rect2(860 + i * 100, 330, 92, 62), Color(0.18, 0.22, 0.3, 0.8),
			func(): if player: player.weapons.switch_weapon(idx), func(): pass)

func _make_touch_btn(title: String, rect: Rect2, col: Color, on_down: Callable, on_up: Callable) -> void:
	var panel := ColorRect.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.color = col

	var lbl := Label.new()
	lbl.text = title
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lbl)

	panel.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventScreenTouch:
			if ev.pressed: on_down.call()
			else: on_up.call()
			get_viewport().set_input_as_handled()
		elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed: on_down.call()
			else: on_up.call()
			get_viewport().set_input_as_handled()
	)
	add_child(panel)

func _unhandled_input(event: InputEvent) -> void:
	if not player:
		return

	if event is InputEventScreenTouch:
		var half_w := get_viewport().get_visible_rect().size.x * 0.45
		if event.pressed:
			if event.position.x < half_w and _joy_index == -1:
				_joy_index = event.index
				_update_joy(event.position)
			elif event.position.x >= half_w and _look_index == -1:
				_look_index = event.index
		else:
			if event.index == _joy_index:
				_joy_index = -1
				player.touch_move_vec = Vector2.ZERO
				_joy_knob.position = _joy_center - Vector2(26, 26)
			elif event.index == _look_index:
				_look_index = -1

	elif event is InputEventScreenDrag:
		if event.index == _joy_index:
			_update_joy(event.position)
		elif event.index == _look_index:
			player.apply_look_delta(event.relative, 0.0055)

func _update_joy(pos: Vector2) -> void:
	var delta := pos - _joy_center
	if delta.length() > _joy_radius:
		delta = delta.normalized() * _joy_radius
	_joy_knob.position = _joy_center + delta - Vector2(26, 26)
	player.touch_move_vec = delta / _joy_radius

func _process(delta: float) -> void:
	_lbl_fps.text = "FPS: %d" % Engine.get_frames_per_second()

	if _announce_timer > 0.0:
		_announce_timer -= delta
		if _announce_timer <= 0.0:
			_lbl_announce.text = ""

	if not player:
		return

	if _fire_held:
		player.weapons.fire_primary()

	if _alt_held:
		_alt_charge_timer += delta
		if _alt_charge_timer >= 0.26:
			_alt_charge_timer = 0.0
			player.weapons.fire_alt_pressed()

	var charge_r: float = player.weapons.get_charge_ratio()
	_charge_bg.visible = charge_r > 0.01
	_charge_fill.size.x = 140.0 * charge_r

	var wid: int = player.weapons.current_weapon
	var ammo_val: int = player.weapons.ammo[wid]
	_lbl_stats.text = "HP: %d  |  ARMOR: %d  |  %s [%d]" % [player.hp, player.armor, WPN_NAMES[wid], ammo_val]

func _on_score_updated(red_s: int, blue_s: int) -> void:
	_lbl_score.text = "RED %d  |  TEAM DEATHMATCH  |  %d BLUE" % [red_s, blue_s]

func _on_announcement(text: String) -> void:
	_lbl_announce.text = text
	_announce_timer = 2.4

func _on_match_ended(winner: String) -> void:
	_lbl_announce.text = winner + " — РЕСТАРТ ЧЕРЕЗ 4 СЕК..."
	_announce_timer = 4.0
	await get_tree().create_timer(4.0).timeout
	GameMode.start_match(GameMode.Mode.TEAM_DEATHMATCH, 35)
