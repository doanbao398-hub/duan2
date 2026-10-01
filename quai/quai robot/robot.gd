extends Entity

# --- ENUMS & PHÂN LUỒNG TRẠNG THÁI ---
enum State { SLEEP, SPAWNING, PATROL, CHASE, ATTACK, DEFENDING, RECOVERY, DEAD }
var current_state: State = State.SLEEP

# --- NODE REFERENCES ---
@onready var robot_anim: AnimatedSprite2D = $chuyendongrobbot
@onready var chuong_1: AnimatedSprite2D = $chuong1
@onready var chuong_2: AnimatedSprite2D = $chuong2
@onready var chuong_3: AnimatedSprite2D = $chuong3

@onready var chuong_range: Area2D = $"ChưởngRange"
@onready var melee_range: Area2D = $MeleeRange
@onready var def_range: Area2D = $chuyendongrobbot/DefRange
@onready var patrol_area: Area2D = $PatrolArea
@onready var wall_detector: RayCast2D = $WallDetector

# References cho các loại đạn ngực
@onready var dan_1: Area2D = $Dan1
@onready var dan_2: Area2D = $Dan2

# --- CONFIGURATION (EXPORT VARIABLES) ---
@export_group("Movement Settings")
@export var patrol_speed: float = 40.0
@export var chase_speed: float = 110.0
@export var jump_velocity: float = -350.0

@export_group("Combat Settings")
@export var skill_cooldown_time: float = 3.0
@export var decision_interval: float = 0.8
@export var recovery_time: float = 0.5
@export var attack_damage: int = 10

@export_group("Defend Settings")
@export var def_duration: float = 1.5             # Thời gian giữ khiên đỡ (giây)
@export var def_cooldown_time: float = 0.5        # Đã giảm cooldown xuống 0.5s để đỡ liên tục hơn
@export var def_chance: float = 0.2            # Đã tăng tỉ lệ đỡ lên 100% (1.0) để test chắc chắn chạy

# --- INTERNAL VARIABLES ---
var direction: int = 1:
	set(value):
		if direction != value and value != 0:
			direction = value
			_update_facing_direction()

var can_use_skill: bool = true
var can_defend: bool = true                        
var has_fired_chest_muzzle: bool = false
var has_hit_melee: bool = false
var target_player: Node2D = null

# Timers quản lý nhịp đấu
var skill_cooldown_timer: Timer
var decision_timer: Timer
var recovery_timer: Timer
var def_hold_timer: Timer                          
var def_cooldown_timer: Timer                      

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

# --- LIFECYCLE METHODS ---
func _ready() -> void:
	super._ready()
	_setup_nodes()
	_setup_signals()
	_update_facing_direction()
	_setup_sleep_state()

func _physics_process(delta: float) -> void:
	if current_state == State.DEAD:
		return

	_apply_gravity(delta)
	
	if current_state == State.SLEEP:
		velocity.x = 0
		move_and_slide()
		_check_player_entered_patrol_to_spawn()
		return

	_update_target_player()
	
	match current_state:
		State.PATROL:
			_handle_patrol_state()
		State.CHASE:
			_handle_chase_state()
		State.SPAWNING, State.ATTACK, State.DEFENDING, State.RECOVERY:
			_handle_stopped_state()
			
	move_and_slide()

# --- CƠ CHẾ XUẤT HIỆN ---
func _setup_sleep_state() -> void:
	current_state = State.SLEEP
	visible = false
	if health_bar:
		health_bar.hide()

func _check_player_entered_patrol_to_spawn() -> void:
	var detected_player = _scan_for_player()
	if detected_player:
		_trigger_spawn(detected_player)

func _trigger_spawn(player_node: Node2D) -> void:
	current_state = State.SPAWNING
	target_player = player_node
	visible = true
	_face_target(target_player.global_position)
	
	if robot_anim and robot_anim.sprite_frames.has_animation("xuathien"):
		robot_anim.play("xuathien")
	else:
		_finish_spawning()

func _finish_spawning() -> void:
	if current_state == State.DEAD:
		return
	if health_bar:
		health_bar.show()
	current_state = State.CHASE

# --- LẮNG NGHE SỰ KIỆN TẤN CÔNG TỪ EVENTBUS (ĐÃ SỬA LẠI ĐIỀU KIỆN DEF) ---
func _on_entity_attacked(attacker: Node2D) -> void:
	# Không đỡ khi đang Ngủ, Spawn, Đã Chết, hoặc Đang trong thời gian Cooldown khiên
	if current_state in [State.DEAD, State.SLEEP, State.SPAWNING, State.DEFENDING] or not can_defend:
		return
		
	# Kiểm tra nếu đối tượng tấn công là Player HOẶC Player đang ở trong vùng DefRange
	if _is_body_player(attacker) or _is_player_in_range(def_range):
		if randf() <= def_chance:
			print("Robot: Phản xạ bật khiên DEFEND!") # Thêm print để bạn dễ debug trên console
			_use_defend_skill()

# --- HÀM NHẬN SÁT THƯƠNG ---
func take_damage(amount: int) -> void:
	if current_state in [State.SLEEP, State.SPAWNING]:
		return
		
	# Nếu đang bật khiên -> Block hoàn toàn đòn đánh
	if current_state == State.DEFENDING or (robot_anim and robot_anim.animation == "def"):
		if _is_player_in_range(def_range):
			return
		
	if super.has_method("take_damage"):
		super.take_damage(amount)

# --- TARGET SCANNING ---
func _update_target_player() -> void:
	var detected_player = _scan_for_player()
	if detected_player:
		target_player = detected_player
	elif current_state == State.PATROL:
		target_player = null

func _scan_for_player() -> Node2D:
	if patrol_area:
		for body in patrol_area.get_overlapping_bodies():
			if _is_body_player(body):
				return body
				
	var players = get_tree().get_nodes_in_group("Player")
	if players.size() == 0:
		players = get_tree().get_nodes_in_group("player")
		
	for p in players:
		if p is Node2D and _patrol_area_contains_point(p.global_position):
			return p
			
	return null

# --- STATE HANDLERS ---
func _handle_patrol_state() -> void:
	if is_instance_valid(target_player):
		current_state = State.CHASE
		return

	_check_patrol_boundaries()
	velocity.x = direction * patrol_speed
	robot_anim.play("walk")
	_check_and_jump()

func _handle_chase_state() -> void:
	if not is_instance_valid(target_player):
		current_state = State.PATROL
		return

	add_collision_exception_with(target_player)

	if _is_player_in_range(melee_range):
		_use_arm_fire_skill()
		return

	_face_target(target_player.global_position)
	velocity.x = direction * chase_speed
	robot_anim.play("walk")
	_check_and_jump()

func _handle_stopped_state() -> void:
	velocity.x = 0

# --- THUẬT TOÁN CHỌN SKILL TẦM XA ---
func _on_decision_timer_timeout() -> void:
	if current_state != State.CHASE or not can_use_skill or not is_instance_valid(target_player):
		return

	if _is_player_in_range(melee_range):
		return

	var rand_val = randf()
	if _is_player_in_range(chuong_range):
		if rand_val < 0.5:
			_use_beam_skill()
		else:
			_use_chest_muzzle_skill()
	else:
		if rand_val < 0.4:
			_use_chest_muzzle_skill()

# --- COMBAT LOGIC ---
func _use_defend_skill() -> void:
	current_state = State.DEFENDING
	can_defend = false
	_hide_all_skills()
	
	if is_instance_valid(target_player):
		_face_target(target_player.global_position)
		
	robot_anim.play("def")
	def_hold_timer.start()

func _on_def_hold_timeout() -> void:
	def_cooldown_timer.start()
	_enter_recovery_phase()

func _on_def_cooldown_timeout() -> void:
	can_defend = true

func _use_arm_fire_skill() -> void:
	current_state = State.ATTACK
	has_hit_melee = false
	_hide_all_skills()
	
	if is_instance_valid(target_player):
		_face_target(target_player.global_position)
		
	robot_anim.play("arm_fire")

func _use_beam_skill() -> void:
	current_state = State.ATTACK
	can_use_skill = false
	_hide_all_skills()
	
	if is_instance_valid(target_player):
		_face_target(target_player.global_position)
		
	robot_anim.play("attack")
	if chuong_1:
		chuong_1.show()
		chuong_1.play("default")

func _use_chest_muzzle_skill() -> void:
	current_state = State.ATTACK
	can_use_skill = false
	has_fired_chest_muzzle = false
	_hide_all_skills()
	
	if is_instance_valid(target_player):
		_face_target(target_player.global_position)
		
	robot_anim.play("ChestMuzzle")

func _hide_all_skills() -> void:
	for skill in [chuong_1, chuong_2, chuong_3]:
		if skill:
			skill.hide()
			skill.stop()

# --- RECOVERY & COOLDOWN MANAGEMENT ---
func _enter_recovery_phase() -> void:
	current_state = State.RECOVERY
	if robot_anim.sprite_frames.has_animation("idle"):
		robot_anim.play("idle")
	else:
		robot_anim.stop()
		
	recovery_timer.start()
	_start_skill_cooldown()

func _on_recovery_timeout() -> void:
	if current_state in [State.RECOVERY, State.DEFENDING]:
		current_state = State.CHASE

func _start_skill_cooldown() -> void:
	if skill_cooldown_timer.is_stopped():
		skill_cooldown_timer.start()

func _on_skill_cooldown_timeout() -> void:
	can_use_skill = true

# --- HELPER FUNCTIONS ---
func _face_target(target_pos: Vector2) -> void:
	var dist_x: float = target_pos.x - global_position.x
	if abs(dist_x) > 25.0:
		direction = 1 if dist_x > 0 else -1

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta

func _check_and_jump() -> void:
	if wall_detector and wall_detector.is_colliding() and is_on_floor():
		var collider = wall_detector.get_collider()
		if collider and not _is_body_player(collider):
			velocity.y = jump_velocity

func _check_patrol_boundaries() -> void:
	if patrol_area and not _patrol_area_contains_point(global_position):
		var area_center_x = patrol_area.global_position.x
		direction = 1 if global_position.x < area_center_x else -1

func _update_facing_direction() -> void:
	var is_facing_left: bool = (direction < 0)
	var mult: float = -1.0 if is_facing_left else 1.0
	
	if robot_anim:
		robot_anim.flip_h = is_facing_left
	
	for ch in [chuong_1, chuong_2, chuong_3]:
		if ch:
			ch.flip_h = is_facing_left
			ch.position.x = abs(ch.position.x) * mult

	for dan in [dan_1, dan_2]:
		if dan:
			dan.position.x = abs(dan.position.x) * mult

	if chuong_range:
		chuong_range.scale.x = mult
	if melee_range:
		melee_range.scale.x = mult
	if wall_detector:
		wall_detector.target_position.x = abs(wall_detector.target_position.x) * mult

func _patrol_area_contains_point(point: Vector2) -> bool:
	if not patrol_area:
		return false
	for child in patrol_area.get_children():
		if child is CollisionShape2D and child.shape:
			var rect = child.shape.get_rect()
			var global_rect = Rect2(child.global_position - rect.size / 2.0, rect.size)
			return global_rect.has_point(point)
	return false

func _is_player_in_range(area: Area2D) -> bool:
	if not area:
		return false
	for body in area.get_overlapping_bodies():
		if _is_body_player(body):
			return true
	return false

func _is_body_player(body: Node) -> bool:
	if body == null or body == self or not is_instance_valid(body):
		return false
	if body.is_in_group("player") or body.is_in_group("Player"):
		return true
	var name_lower = body.name.to_lower()
	if "player" in name_lower or "ngoaihinh" in name_lower:
		return true
	if body.get_parent() and ("player" in body.get_parent().name.to_lower() or body.get_parent().is_in_group("player")):
		return true
	return false

# --- XỬ LÝ KHI ROBOT CHẾT ---
func die() -> void:
	if current_state == State.DEAD:
		return
		
	current_state = State.DEAD
	velocity = Vector2.ZERO
	_hide_all_skills()
	
	set_physics_process(false)
	if has_node("CollisionShape2D"):
		$CollisionShape2D.set_deferred("disabled", true)
	if health_bar:
		health_bar.hide()
		
	if robot_anim and robot_anim.sprite_frames.has_animation("die"):
		robot_anim.play("die")
		await robot_anim.animation_finished

	super.die()

# --- INITIALIZATION HELPER METHODS ---
func _setup_nodes() -> void:
	_hide_all_skills()
	
	if patrol_area and patrol_area.get_parent() == self:
		var map_node = get_parent()
		patrol_area.reparent.call_deferred(map_node)
	
	skill_cooldown_timer = Timer.new()
	skill_cooldown_timer.wait_time = skill_cooldown_time
	skill_cooldown_timer.one_shot = true
	add_child(skill_cooldown_timer)

	decision_timer = Timer.new()
	decision_timer.wait_time = decision_interval
	decision_timer.autostart = true
	add_child(decision_timer)

	recovery_timer = Timer.new()
	recovery_timer.wait_time = recovery_time
	recovery_timer.one_shot = true
	add_child(recovery_timer)

	def_hold_timer = Timer.new()
	def_hold_timer.wait_time = def_duration
	def_hold_timer.one_shot = true
	add_child(def_hold_timer)

	def_cooldown_timer = Timer.new()
	def_cooldown_timer.wait_time = def_cooldown_time
	def_cooldown_timer.one_shot = true
	add_child(def_cooldown_timer)

func _setup_signals() -> void:
	if EventBus.has_signal("entity_attacked"):
		EventBus.entity_attacked.connect(_on_entity_attacked)

	skill_cooldown_timer.timeout.connect(_on_skill_cooldown_timeout)
	decision_timer.timeout.connect(_on_decision_timer_timeout)
	recovery_timer.timeout.connect(_on_recovery_timeout)
	
	def_hold_timer.timeout.connect(_on_def_hold_timeout)
	def_cooldown_timer.timeout.connect(_on_def_cooldown_timeout)
	
	robot_anim.animation_finished.connect(_on_robot_anim_finished)
	robot_anim.frame_changed.connect(_on_robot_anim_frame_changed)
	
	if chuong_1:
		chuong_1.frame_changed.connect(_on_chuong1_frame_changed)
	if chuong_2:
		chuong_2.animation_finished.connect(_on_skill_finished)

# --- SIGNAL CALLBACKS ---
func _on_robot_anim_frame_changed() -> void:
	if robot_anim.animation == "ChestMuzzle" and robot_anim.frame == 4:
		if not has_fired_chest_muzzle:
			has_fired_chest_muzzle = true
			var valid_player: Node2D = target_player if is_instance_valid(target_player) else null
			if dan_1 and dan_1.has_method("fire"):
				dan_1.fire(valid_player, direction)
			if dan_2 and dan_2.has_method("fire"):
				dan_2.fire(valid_player, direction)

	elif robot_anim.animation == "arm_fire" and robot_anim.frame == 3:
		if not has_hit_melee:
			has_hit_melee = true
			if _is_player_in_range(melee_range):
				if is_instance_valid(target_player) and target_player.has_method("take_damage"):
					target_player.take_damage(attack_damage)

func _on_robot_anim_finished() -> void:
	if current_state == State.DEAD:
		return
		
	if robot_anim.animation == "xuathien":
		_finish_spawning()
		return
		
	if robot_anim.animation in ["ChestMuzzle", "arm_fire"]:
		_enter_recovery_phase()

func _on_chuong1_frame_changed() -> void:
	if chuong_1.frame == 5:
		if chuong_2:
			chuong_2.show()
			chuong_2.play("default")
		if chuong_3:
			chuong_3.show()
			chuong_3.play("default")

func _on_skill_finished() -> void:
	if current_state == State.DEAD:
		return
		
	if _is_player_in_range(chuong_range):
		if is_instance_valid(target_player) and target_player.has_method("take_damage"):
			target_player.take_damage(attack_damage * 2)

	_hide_all_skills()
	_enter_recovery_phase()
