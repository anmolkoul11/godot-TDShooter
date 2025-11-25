extends Node
class_name Metrics

var csv_path := "user://metrics.csv"

# ========== PLAYER METRICS ==========
var time_alive := 0.0
var time_alive_stage1 := 0.0
var time_alive_stage2 := 0.0
var stage2_started := false

var player_died := false
var killer_type := "none"
var stage_of_death := 0

var total_damage_taken := 0
var num_hits_taken := 0
var time_low_health := 0.0

var bullets_fired_by_player := 0
var bullets_hit_enemy := 0

var kills_fsm := 0
var kills_bt := 0
var kills_extbt := 0

var dash_count := 0
var last_dash_time := 0.0
var sum_dash_intervals := 0.0

var time_to_pick_turtle := -1.0
var time_to_deliver_turtle := -1.0
var time_turtle_carried := 0.0
var turtle_is_carried := false

# ========== ENEMY METRICS ==========
var bullets_fired_fsm := 0
var bullets_fired_bt := 0
var bullets_fired_extbt := 0

var bullets_hit_player_fsm := 0
var bullets_hit_player_bt := 0
var bullets_hit_player_extbt := 0

var enemy_state_time := {
	"FSM_IDLE":0, "FSM_CHASE":0, "FSM_STOP":0, "FSM_RETREAT":0,
	"BT_IDLE":0, "BT_CHASE":0,
	"EXT_WANDER":0, "EXT_ENGAGE":0, "EXT_COVER":0, "EXT_RETREAT":0,
}

var flank_attempts := 0
var cover_entries := 0
var retreats := 0
var dodge_attempts := 0

# ========== INTERACTION METRICS ==========
var player_distance_check_timer := 0.0
var time_enemy_within_300 := 0.0

# ========== INTERNAL ==========
var _alive := true

func _process(delta):
	set_process(true)
	
	_process_time(delta)

	if turtle_is_carried and not player_died:
		time_turtle_carried += delta

	player_distance_check_timer += delta
	if player_distance_check_timer >= 0.1:
		player_distance_check_timer = 0
		_track_distances()
		
func _process_time(delta):
	if not _alive:
		return

	time_alive += delta

	if not stage2_started:
		time_alive_stage1 += delta
	else:
		time_alive_stage2 += delta


# Check enemy proximity for risk index
func _track_distances():
	var enemies = get_tree().get_nodes_in_group("enemy")
	for e in enemies:
		if e and e.is_inside_tree():
			var p = get_tree().get_first_node_in_group("player")
			if p:
				if p.global_position.distance_to(e.global_position) <= 300:
					time_enemy_within_300 += 0.1

# ========== EVENT HOOKS EXPOSED TO GAME ==========
func on_player_damaged(amount):
	total_damage_taken += amount
	num_hits_taken += 1

func on_player_low_health(dt):
	time_low_health += dt

func on_player_fired():
	bullets_fired_by_player += 1

func on_player_bullet_hit_enemy():
	bullets_hit_enemy += 1

func on_enemy_killed(t):
	match t:
		"FSM": kills_fsm += 1
		"BT": kills_bt += 1
		"EXT": kills_extbt += 1

func on_enemy_bullet_fired(type):
	match type:
		"FSM": bullets_fired_fsm += 1
		"BT": bullets_fired_bt += 1
		"EXT": bullets_fired_extbt += 1

func on_enemy_bullet_hit_player(type):
	match type:
		"FSM": bullets_hit_player_fsm += 1
		"BT": bullets_hit_player_bt += 1
		"EXT": bullets_hit_player_extbt += 1

func on_flank_attempt():
	flank_attempts += 1

func on_cover_entered():
	cover_entries += 1

func on_retreat():
	retreats += 1

func on_dodge():
	dodge_attempts += 1

func on_dash_used():
	if time_alive > 0:
		sum_dash_intervals += (time_alive - last_dash_time)
	last_dash_time = time_alive
	dash_count += 1

func on_stage2_started():
	stage2_started = true

func on_turtle_picked():
	if player_died:
		return    # Ignore — dead runs must not record this
	time_to_pick_turtle = time_alive
	turtle_is_carried = true

func on_turtle_delivered():
	if player_died:
		return  # Prevent delivery timestamps on death runs
	time_to_deliver_turtle = time_alive
	turtle_is_carried = false


func on_player_died_event(killer, stage):
	# DO NOT disable time yet — allow last frame to tick
	player_died = true
	killer_type = killer
	stage_of_death = stage

	_write_csv()

	# Only stop timing AFTER reset
	_alive = true


# ========== CSV WRITING ==========
func _write_csv():
	var file_exists := FileAccess.file_exists(csv_path)
	var f: FileAccess
	
	# CASE 1: file exists → open without deleting content
	if file_exists:
		f = FileAccess.open(csv_path, FileAccess.READ_WRITE)
		if f == null:
			push_error("Could not open existing CSV file for writing: " + csv_path)
			return

		f.seek_end()   # append to end
		f.store_line(_csv_row())
		f.flush()
		return
	
	# CASE 2: file does NOT exist → create file & write header
	f = FileAccess.open(csv_path, FileAccess.WRITE_READ)
	if f == null:
		push_error("Could not create CSV file: " + csv_path)
		return

	f.store_line(_csv_header())
	f.store_line(_csv_row())
	f.flush()
	
	if time_alive <= 0.05:
	# Run was too short to be real → ignore this run
	# DO NOT write row
		reset()
		return



func _csv_header():
	return (
"run,time_alive,time_alive_stage1,time_alive_stage2,player_died,killer_type,stage_of_death,"+
"total_damage_taken,num_hits_taken,bullets_fired_by_player,bullets_hit_enemy,kills_fsm,kills_bt,kills_extbt,"+
"bullets_fired_fsm,bullets_fired_bt,bullets_fired_extbt,bullets_hit_player_fsm,bullets_hit_player_bt,bullets_hit_player_extbt,"+
"dash_count,sum_dash_intervals,time_enemy_within_300,time_low_health,time_to_pick_turtle,time_to_deliver_turtle,time_turtle_carried,"+
"flank_attempts,cover_entries,retreats,dodge_attempts"
)

func _csv_row():
	return "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s" % [
	str(Time.get_ticks_msec()),
	time_alive, time_alive_stage1, time_alive_stage2,
	player_died, killer_type, stage_of_death,
	total_damage_taken, num_hits_taken, bullets_fired_by_player, bullets_hit_enemy,
	kills_fsm, kills_bt, kills_extbt,
	bullets_fired_fsm, bullets_fired_bt, bullets_fired_extbt,
	bullets_hit_player_fsm, bullets_hit_player_bt, bullets_hit_player_extbt,
	dash_count, sum_dash_intervals, time_enemy_within_300, time_low_health,
	time_to_pick_turtle, time_to_deliver_turtle, time_turtle_carried,
	flank_attempts, cover_entries, retreats, dodge_attempts
]

func reset():
	time_alive = 0.0
	time_alive_stage1 = 0.0
	time_alive_stage2 = 0.0
	stage2_started = false

	player_died = false
	killer_type = "none"
	stage_of_death = 0

	total_damage_taken = 0
	num_hits_taken = 0
	time_low_health = 0.0

	bullets_fired_by_player = 0
	bullets_hit_enemy = 0

	kills_fsm = 0
	kills_bt = 0
	kills_extbt = 0

	bullets_fired_fsm = 0
	bullets_fired_bt = 0
	bullets_fired_extbt = 0

	bullets_hit_player_fsm = 0
	bullets_hit_player_bt = 0
	bullets_hit_player_extbt = 0

	dash_count = 0
	sum_dash_intervals = 0.0
	last_dash_time = 0.0

	time_enemy_within_300 = 0.0

	time_to_pick_turtle = -1.0
	time_to_deliver_turtle = -1.0
	time_turtle_carried = 0.0
	turtle_is_carried = false

	flank_attempts = 0
	cover_entries = 0
	retreats = 0
	dodge_attempts = 0
