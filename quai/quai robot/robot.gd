extends CharacterBody2D

# --- ENUMS & PHÂN LUỒNG TRẠNG THÁI ---
enum State { PATROL, CHASE, ATTACK }
var current_state: State = State.PATROL

# --- NODE REFERENCES ---
@onready var robot_anim: AnimatedSprite2D = $chuyendongrobbot
@onready var chuong_1: AnimatedSprite2D = $chuong1
@onready var chuong_2: AnimatedSprite2D = $chuong2
@onready var chuong_3: AnimatedSprite2D = $chuong3

@onready var chuong_range: Area2D = $"ChưởngRange"
@onready var melee_range: Area2D = $MeleeRange
@onready var patrol_area: Area2D = $PatrolArea
@onready var wall_detector: RayCast2D = $WallDetector

# --- CONFIGURATION (EXPORT VARIABLES) ---
@export_group("Movement Settings")
@export var patrol_speed: float = 40.0
@export var chase_speed: float = 110.0
@export var jump_velocity: float = -350.0

@export_group("Combat Settings")
@export var skill_cooldown_time: float = 6.0

# --- INTERNAL VARIABLES ---
var direction: int = 1:
	set(value):
		if direction != value and value != 0:
			direction = value
			_update_facing_direction()

var can_use_skill: bool = true
var target_player: Node2D = null
var skill_cooldown_timer: Timer

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

# --- LIFECYCLE METHODS ---
func _ready() -> void:
	_setup_nodes()
	_setup_signals()
	_update_facing_direction()

func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	
	# Luôn quét tìm Player trong vùng PatrolArea
	target_player = _scan_for_player_in_patrol()
	
	# Xử lý các trạng thái hoạt động của Robot
	match current_state:
		State.PATROL:
			_handle_patrol_state()
		State.CHASE:
			_handle_chase_state()
		State.ATTACK:
			_handle_attack_state()
			
	move_and_slide()

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

	# Bỏ qua va chạm vật lý với Player để không bị kẹt khi đuổi theo
	add_collision_exception_with(target_player)

	# Kiểm tra điều kiện tung kỹ năng
	if can_use_skill and _is_player_in_range(chuong_range):
		_use_beam_skill()
		return
	elif _is_player_in_range(melee_range):
		_use_melee_skill()
		return

	# Xử lý di chuyển dí theo Player
	var dist_x: float = target_player.global_position.x - global_position.x
	if abs(dist_x) > 8.0:
		direction = 1 if dist_x > 0 else -1

	velocity.x = direction * chase_speed
	robot_anim.play("walk")
	_check_and_jump()

func _handle_attack_state() -> void:
	velocity.x = 0

# --- MOVEMENT & SENSORS ---
func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta

func _check_and_jump() -> void:
	if wall_detector.is_colliding() and is_on_floor():
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

	if chuong_range:
		chuong_range.position.x = abs(chuong_range.position.x) * mult
	if melee_range:
		melee_range.position.x = abs(melee_range.position.x) * mult
	if wall_detector:
		wall_detector.target_position.x = abs(wall_detector.target_position.x) * mult

# --- TARGET SCANNING & DETECTION ---
func _scan_for_player_in_patrol() -> Node2D:
	if not patrol_area:
		return null
		
	for body in patrol_area.get_overlapping_bodies():
		if _is_body_player(body):
			return body
			
	var players = get_tree().get_nodes_in_group("player")
	for p in players:
		if p is Node2D and _patrol_area_contains_point(p.global_position):
			return p
			
	return null

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
	if body == null or body == self:
		return false
	if body.is_in_group("player"):
		return true
	var name_lower = body.name.to_lower()
	if "player" in name_lower or "ngoaihinh" in name_lower:
		return true
	if body.get_parent() and ("player" in body.get_parent().name.to_lower() or body.get_parent().is_in_group("player")):
		return true
	return false

# --- COMBAT LOGIC ---
func _use_melee_skill() -> void:
	current_state = State.ATTACK
	_hide_all_skills()
	robot_anim.play("def")

func _use_beam_skill() -> void:
	current_state = State.ATTACK
	can_use_skill = false
	_hide_all_skills()
	robot_anim.play("attack")

func _hide_all_skills() -> void:
	for skill in [chuong_1, chuong_2, chuong_3]:
		if skill:
			skill.hide()
			skill.stop()

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

func _setup_signals() -> void:
	skill_cooldown_timer.timeout.connect(_on_skill_cooldown_timeout)
	robot_anim.animation_finished.connect(_on_robot_anim_finished)
	chuong_1.frame_changed.connect(_on_chuong1_frame_changed)
	chuong_2.animation_finished.connect(_on_skill_finished)

# --- SIGNAL CALLBACKS ---
func _on_robot_anim_finished() -> void:
	if robot_anim.animation == "attack":
		chuong_1.show()
		chuong_1.play("default")
	elif robot_anim.animation == "def":
		current_state = State.PATROL

func _on_chuong1_frame_changed() -> void:
	if chuong_1.frame == 5:
		chuong_2.show()
		chuong_2.play("default")
		chuong_3.show()
		chuong_3.play("default")

func _on_skill_finished() -> void:
	_hide_all_skills()
	current_state = State.PATROL
	skill_cooldown_timer.start()

func _on_skill_cooldown_timeout() -> void:
	can_use_skill = true
