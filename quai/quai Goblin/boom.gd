extends Area2D

# --- CÁC THAM SỐ LỰC NÉM VẬT LÝ ---
@export var speed_x: float = 200.0
@export var jump_force_y: float = -250.0
@export var bomb_gravity: float = 600.0
@export var damage: int = 15

# --- ONREADY NODES ---
@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var explosion_area: Area2D = $ExplosionArea
@onready var explosion_collision: CollisionShape2D = $ExplosionArea/CollisionShape2D

# --- BIẾN QUẢN LÝ TRẠNG THÁI ---
var velocity: Vector2 = Vector2.ZERO
var is_exploding: bool = false
var has_touched: bool = false
var is_active: bool = false
var direction: int = 1

# Lưu lại Goblin gốc để trả quả bom về sau khi nổ xong
var original_parent: Node = null

func _ready() -> void:
	original_parent = get_parent()
	hide()
	set_physics_process(false)
	
	if collision_shape:
		collision_shape.disabled = true
	if explosion_collision:
		explosion_collision.disabled = true
	
	body_entered.connect(_on_boom_body_entered)
	area_entered.connect(_on_boom_area_entered)

func activate_bomb(dir: int, spawn_global_pos: Vector2) -> void:
	if is_active: return
	
	is_active = true
	direction = dir
	has_touched = false
	is_exploding = false
	
	# 1. LẤY ROOT SAFE CHỐNG LỖI NULL KHI F6
	var target_parent = get_tree().current_scene
	if not target_parent:
		target_parent = get_tree().root
		
	# Tách quả bom ra khỏi Goblin và đưa vào Root Scene
	if get_parent() != target_parent:
		get_parent().remove_child(self)
		target_parent.add_child(self)
	
	# 2. ĐẶT VỊ TRÍ XUẤT PHÁT ĐỘC LẬP
	var spawn_offset = Vector2(15 * direction, -10)
	global_position = spawn_global_pos + spawn_offset
	rotation = 0
	
	# Tính lực ném
	velocity.x = speed_x * direction
	velocity.y = jump_force_y
	
	# Hiện quả bom và bật Physics
	show()
	set_physics_process(true)
	if collision_shape:
		collision_shape.disabled = false
		
	if anim_sprite:
		anim_sprite.play("boom")
		anim_sprite.frame = 0
		if not anim_sprite.frame_changed.is_connected(_on_frame_changed):
			anim_sprite.frame_changed.connect(_on_frame_changed)

func _physics_process(delta: float) -> void:
	if not is_active or is_exploding:
		return

	if not has_touched:
		velocity.y += bomb_gravity * delta
		global_position += velocity * delta
		rotation += 6.0 * delta * direction

func _on_frame_changed() -> void:
	if not is_active or not anim_sprite or anim_sprite.animation != "boom":
		return
		
	var frame = anim_sprite.frame

	if not has_touched:
		if frame > 8:
			anim_sprite.frame = 3
	else:
		if frame == 8 and not is_exploding:
			_start_explosion()
		elif frame >= 18:
			_reset_bomb()

func _on_boom_body_entered(body: Node) -> void:
	_trigger_hit(body)

func _on_boom_area_entered(area: Area2D) -> void:
	_trigger_hit(area)

func _trigger_hit(node: Node) -> void:
	if not is_active or node.is_in_group("Enemy") or node.name in ["Gobbin", "Goblin"]:
		return
		
	if has_touched:
		return

	has_touched = true
	velocity = Vector2.ZERO
	rotation = 0

func _start_explosion() -> void:
	is_exploding = true
	anim_sprite.frame = 9
	
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
		
	if explosion_collision:
		explosion_collision.set_deferred("disabled", false)
		
	await get_tree().create_timer(0.05).timeout
	_apply_explosion_damage()

func _apply_explosion_damage() -> void:
	if not explosion_area:
		return
		
	var bodies = explosion_area.get_overlapping_bodies()
	for body in bodies:
		if _is_player(body) and body.has_method("take_damage"):
			body.take_damage(damage)

func _reset_bomb() -> void:
	is_active = false
	is_exploding = false
	set_physics_process(false)
	
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	if explosion_collision:
		explosion_collision.set_deferred("disabled", true)
		
	hide()
	
	# TRẢ QUẢ BOM VỀ LẠI CHO GOBBIN ĐỂ CHỜ LẦN NÉM KẾ TIẾP
	if is_instance_valid(original_parent) and get_parent() != original_parent:
		get_parent().remove_child(self)
		original_parent.add_child(self)

func _is_player(body: Node) -> bool:
	return body.is_in_group("Player") or body.name in ["ngoaihinh", "player", "Player"]
