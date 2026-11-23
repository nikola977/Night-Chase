class_name FallingPole
extends Node3D
## Ein Pfosten im City Block (Straßenlaterne, Ampelpfosten), der beim Anfahren umfällt
## und sich nach ein paar Sekunden von selbst wieder aufstellt.
##
## Der Pfosten steht nicht in den gemergten Stadtflächen, sondern als eigener Knoten:
## Gedreht wird um den Fußpunkt, in die Richtung weg vom Auto. Solange er steht, hat er
## eine Kollision (dünner Zylinder); beim Umfallen schaltet sie sich ab, damit das Auto
## nicht an einem liegenden Pfosten hängen bleibt.

## Ab diesem Abstand (Mitte Auto zu Pfosten, Meter) zählt der Stoß
@export var hit_distance: float = 2.6
## Ab dieser Geschwindigkeit des Autos fällt der Pfosten (m/s, 1,4 = 5 km/h)
@export var hit_speed: float = 1.4
## Winkelbeschleunigung beim Umfallen (rad/s²): größer = schneller unten
@export var fall_acceleration: float = 3.2
## Größter Winkel beim Umfallen (Grad); 88 liegt fast am Boden
@export var fall_angle: float = 88.0
## So lange bleibt der Pfosten liegen, bevor er wieder aufsteht (Sekunden)
@export var rest_time: float = 5.0
## So lange dauert das Aufstehen (Sekunden)
@export var rise_time: float = 0.9

var car: VehicleBody3D
## Fußpunkt (Welt), Höhe und Dicke des Pfostens
var foot := Vector3.ZERO
var shaft_height: float = 10.0
var shaft_radius: float = 0.12

## Um diese Achse kippt der Pfosten (waagerecht, senkrecht zur Fallrichtung)
var _axis := Vector3.BACK
var _angle: float = 0.0
var _speed: float = 0.0
var _rest: float = 0.0
var _rising: bool = false
var _rise: float = 0.0
var _body: StaticBody3D


## Vor dem Einfügen in den Baum aufrufen: Fußpunkt, Maße und das Auto, das ihn umfährt
func setup(base: Vector3, height: float, radius: float, vehicle: VehicleBody3D) -> void:
	foot = base
	shaft_height = height
	shaft_radius = radius
	car = vehicle
	position = base


func _ready() -> void:
	_body = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = shaft_radius + 0.06
	cylinder.height = shaft_height
	shape.shape = cylinder
	shape.position.y = shaft_height * 0.5
	_body.add_child(shape)
	add_child(_body)


## Aktueller Neigungswinkel in Grad (0 = steht)
func angle_degrees() -> float:
	return rad_to_deg(_angle)


func _physics_process(delta: float) -> void:
	if car == null:
		return
	if _rising:
		_rise = minf(_rise + delta / maxf(rise_time, 0.01), 1.0)
		# Weich aufstehen: langsam aus der Schräglage, sanft oben ankommen
		var t := _rise * _rise * (3.0 - 2.0 * _rise)
		_angle = deg_to_rad(fall_angle) * (1.0 - t)
		_apply()
		if _rise >= 1.0:
			_stand_up()
		return
	if _rest > 0.0:
		_rest -= delta
		if _rest <= 0.0:
			_rising = true
			_rise = 0.0
		return
	# Steht er noch? Dann nur nachsehen, ob das Auto dagegen fährt
	if _angle == 0.0 and not _check_hit():
		return
	_speed += fall_acceleration * delta
	_angle = minf(_angle + _speed * delta, deg_to_rad(fall_angle))
	_apply()
	if _angle >= deg_to_rad(fall_angle):
		_rest = rest_time


## Neigen, und dabei etwas absinken: liegend liegt der Pfosten am Asphalt und nicht 40 cm
## darüber, weil der Fußpunkt im Modell über dem Boden sitzt (die Hälfte reicht, sonst
## versinkt er im Boden)
func _apply() -> void:
	transform.basis = Basis(_axis, _angle)
	position.y = foot.y * (1.0 - 0.5 * _angle / deg_to_rad(fall_angle))


## Steht das Auto dicht genug und fährt es? Dann kippt der Pfosten weg von ihm
func _check_hit() -> bool:
	var offset := car.global_position - global_position
	var flat := Vector2(offset.x, offset.z)
	if flat.length() > hit_distance:
		return false
	var velocity := car.linear_velocity
	if Vector2(velocity.x, velocity.z).length() < hit_speed:
		return false
	var away := Vector3(-flat.x, 0.0, -flat.y).normalized() if flat.length() > 0.01 else Vector3.FORWARD
	_axis = Vector3.UP.cross(away).normalized()
	_speed = 0.5
	# Liegend nicht mehr im Weg stehen
	_body.collision_layer = 0
	_body.collision_mask = 0
	return true


func _stand_up() -> void:
	_rising = false
	_angle = 0.0
	_speed = 0.0
	transform.basis = Basis()
	position = foot
	_body.collision_layer = 1
	_body.collision_mask = 1
