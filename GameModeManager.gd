extends Node

enum Mode { TEAM_DEATHMATCH, DEATHMATCH, CAPTURE_THE_FLAG }

signal score_updated(red_score: int, blue_score: int)
signal announcement(text: String)
signal match_ended(winner: String)

var current_mode: Mode = Mode.TEAM_DEATHMATCH
var score_limit: int = 35
var red_score: int = 0
var blue_score: int = 0
var first_blood_taken: bool = false
var match_active: bool = true

var kill_streaks: Dictionary = {}
var multi_kill_count: Dictionary = {}
var last_kill_time: Dictionary = {}

const STREAK_TITLES := {
	5: "KILLING SPREE!",
	10: "RAMPAGE!",
	15: "DOMINATING!",
	20: "UNSTOPPABLE!",
	25: "GODLIKE!"
}

const MULTI_TITLES := {
	2: "DOUBLE KILL!",
	3: "MULTI KILL!",
	4: "MEGA KILL!",
	5: "ULTRA KILL!",
	6: "M-M-MONSTER KILL!"
}

func start_match(mode: Mode = Mode.TEAM_DEATHMATCH, limit: int = 35) -> void:
	current_mode = mode
	score_limit = limit
	red_score = 0
	blue_score = 0
	first_blood_taken = false
	match_active = true
	kill_streaks.clear()
	multi_kill_count.clear()
	last_kill_time.clear()
	score_updated.emit(red_score, blue_score)
	announcement.emit("PLAY!")
	SoundFX.play("announce_kill", -4.0, 0.02)

func register_kill(killer: Node, victim: Node) -> void:
	if not match_active:
		return

	var victim_id := victim.get_instance_id()
	kill_streaks[victim_id] = 0

	if killer == null or killer == victim:
		if current_mode == Mode.TEAM_DEATHMATCH:
			_add_team_score(victim.team, -1)
		return

	if current_mode == Mode.TEAM_DEATHMATCH and killer.team == victim.team:
		_add_team_score(killer.team, -1)
		return

	var killer_id := killer.get_instance_id()
	var now := Time.get_ticks_msec() / 1000.0

	if not first_blood_taken:
		first_blood_taken = true
		announcement.emit("FIRST BLOOD!")
		SoundFX.play("announce_kill", -2.0, 0.02)

	if now - last_kill_time.get(killer_id, -10.0) <= 4.0:
		multi_kill_count[killer_id] = multi_kill_count.get(killer_id, 1) + 1
	else:
		multi_kill_count[killer_id] = 1
	last_kill_time[killer_id] = now

	var mk: int = multi_kill_count[killer_id]
	if mk >= 2:
		announcement.emit(MULTI_TITLES.get(mini(mk, 6), "M-M-MONSTER KILL!"))
		SoundFX.play("announce_kill", -1.5, 0.04)

	var streak: int = kill_streaks.get(killer_id, 0) + 1
	kill_streaks[killer_id] = streak
	if STREAK_TITLES.has(streak):
		announcement.emit(STREAK_TITLES[streak])
		SoundFX.play("announce_kill", -1.0, 0.02)

	if current_mode == Mode.TEAM_DEATHMATCH:
		_add_team_score(killer.team, 1)

func _add_team_score(team: String, delta: int) -> void:
	if team == "RED":
		red_score = maxi(0, red_score + delta)
	else:
		blue_score = maxi(0, blue_score + delta)
	score_updated.emit(red_score, blue_score)

	if red_score >= score_limit:
		match_active = false
		match_ended.emit("RED TEAM WINS!")
		SoundFX.play("announce_kill", 0.0, 0.0)
	elif blue_score >= score_limit:
		match_active = false
		match_ended.emit("BLUE TEAM WINS!")
		SoundFX.play("announce_kill", 0.0, 0.0)
