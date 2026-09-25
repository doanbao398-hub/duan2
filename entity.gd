class_name Entity
extends CharacterBody2D

signal health_changed(current_health, max_health)
signal died

@export var max_health: int = 100
var current_health: int

@onready var health_bar: ProgressBar = $HealthBar

func _ready() -> void:
	current_health = max_health
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = current_health

func take_damage(amount: int) -> void:
	if current_health <= 0:
		return

	current_health -= amount
	current_health = clamp(current_health, 0, max_health)
	
	if health_bar:
		health_bar.value = current_health

	health_changed.emit(current_health, max_health)

	if current_health <= 0:
		die()

func heal(amount: int) -> void:
	if current_health <= 0:
		return
		
	current_health += amount
	current_health = clamp(current_health, 0, max_health)
	
	if health_bar:
		health_bar.value = current_health

	health_changed.emit(current_health, max_health)

func die() -> void:
	died.emit()
	set_physics_process(false)
	if has_node("CollisionShape2D"):
		$CollisionShape2D.set_deferred("disabled", true)
	if health_bar:
		health_bar.hide()
	queue_free()
