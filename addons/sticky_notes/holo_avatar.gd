class_name HoloAvatar
extends Node3D
## Full-body ghost for holonotes, driven only by what a headset records: the head and two hands.
##
##   head  -> the head bone turns with the recorded head and the neck takes part of that turn; the
##            body follows the head's yaw only once you look more than a little to the side
##   body  -> always stands upright on the floor under the recorded head, STAND_HEIGHT tall, however
##            high the headset was (a seated or crouching author still plays back standing). The
##            recorded head only gives where the body is and where it looks; everything the headset
##            recorded is lifted or lowered by the same amount (see lift())
##   legs  -> TwoBoneIK3D keeps both feet on the floor, and a foot takes a step when the body has
##            moved or turned away from it (no sliding feet)
##   arms  -> TwoBoneIK3D bends each arm (shoulder -> elbow -> wrist) to reach the controller, with
##            the elbow pulled down and out; then the hand bone takes the controller's rotation
##   hands -> fingers curled as if holding a controller, index finger out (pointing)
##   no hand tracking for a side -> that arm hangs at the side
##
## Model: assets/models/avatar/male_base_mesh.glb (CC0, Rigify-style bone names). It faces +X and
## is 1.94 m tall, so it is turned to face -Z and scaled to STAND_HEIGHT.

const MODEL := "res://assets/models/avatar/male_base_mesh.glb"
const MODEL_SCALE := 0.9
const MODEL_TURN := PI * 0.5            # +X facing -> Godot's -Z forward
const STAND_HEIGHT := 1.6               # m from the floor to the top of the head
const HEAD_BONE := "spine.005"
const NECK_BONE := "spine.004"
const HIPS_BONE := "spine"
const ARMS := {
	"left": ["upper_arm.L", "forearm.L", "hand.L"],
	"right": ["upper_arm.R", "forearm.R", "hand.R"],
}
const LEGS := {
	"left": ["thigh.L", "shin.L", "foot.L"],
	"right": ["thigh.R", "shin.R", "foot.R"],
}
## Finger curl per joint (radians): holding a controller, index finger out.
const FINGER_CURL := {"f_index": 0.16, "f_middle": 0.8, "f_ring": 0.9, "f_pinky": 0.95, "thumb": 0.25}
## Neck relative to the eyes, in head-local space (below and behind).
const NECK_FROM_EYES := Vector3(0.0, -0.15, 0.02)
## Wrist relative to the controller's aim pose (behind the grip, slightly below the pointing ray).
const WRIST_FROM_AIM := Vector3(0.0, -0.03, 0.11)
## Hand bone axes in the controller's aim frame: fingers (bone +Y) along the ray (-Z), thumb (bone +Z) up.
const HAND_FROM_AIM := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
const YAW_FOLLOW := 5.0                 # 1/s, how fast the body turns after the head
const YAW_DEAD := 0.3                   # rad the head may turn before the body follows
const NECK_SHARE := 0.45                # part of the head's turn taken by the neck
const FLOOR_REACH := 2.2                # m below the recorded neck a floor is looked for
const STEP_DIST := 0.2                  # m a foot may be away from where it should stand
const STEP_YAW := 0.65                  # rad a foot may be turned away from the body
const STEP_TIME := 0.24                 # s one step takes
const STEP_LIFT := 0.07                 # m the foot lifts in mid step
const STEP_LEAD := 0.14                 # s of body movement a step lands ahead by

var ok: bool = false
var skeleton: Skeleton3D
var mesh: MeshInstance3D

var _model: Node3D
var _pre: _BonePoser                  # neck and head (before IK)
var _post: _BonePoser                 # hands and feet (after IK)
var _targets: Dictionary = {}         # "arm_left" ... "leg_right" -> Node3D the IK reaches for
var _poles: Dictionary = {}           # same keys -> Node3D the elbow / knee bends toward
var _head_bone: int = -1
var _neck_bone: int = -1
var _hand_bones: Dictionary = {}      # side -> bone index
var _foot_bones: Dictionary = {}      # side -> bone index
# Rest pose in body space (avatar-local: -Z forward, +Y up, metres, at height factor 1).
var _neck_b: Vector3
var _hips_b: Vector3
var _shoulder_b: Dictionary = {}      # side -> Vector3
var _thigh_b: Dictionary = {}         # side -> Vector3
var _foot_b: Dictionary = {}          # side -> Vector3 (ankle)
var _arm_len: Dictionary = {}         # side -> float
var _head_rest: Basis                 # head bone's basis when looking straight down -Z
var _neck_rest: Basis
var _foot_rest: Dictionary = {}       # side -> Basis
var _ground_b: float = 0.0            # sole height in body space
var _stand_neck: float = 1.4          # neck above the sole when standing
var _u: float = 1.0                   # scale that makes the body STAND_HEIGHT tall
var _lift: float = 0.0                # how far the body's head is above the recorded head
var _yaw: float = 0.0
var _yaw_set: bool = false
var _floor: float = 0.0
var _floor_set: bool = false
var _feet: Dictionary = {}            # side -> {pos, yaw, from, from_yaw, u, stepping}
var _com_prev: Vector3
var _com_set: bool = false
var _vel: Vector3


## Builds the body with the given material. False if the model or its bones are missing
## (the caller keeps the simple ghost then).
func setup(material: Material) -> bool:
	var scene: PackedScene = load(MODEL) if ResourceLoader.exists(MODEL) else null
	if scene == null:
		push_warning("HoloAvatar: %s not found, using the simple ghost" % MODEL)
		return false
	_model = scene.instantiate()
	_model.transform = _model_transform(1.0)
	add_child(_model)
	var sks := _model.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return false
	skeleton = sks[0]
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		mesh = mi
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The body is posed far from its rest pose; never let the rest-pose bounds cull it.
		mesh.extra_cull_margin = 1.5
	_head_bone = skeleton.find_bone(HEAD_BONE)
	_neck_bone = skeleton.find_bone(NECK_BONE)
	var hips := skeleton.find_bone(HIPS_BONE)
	if _head_bone < 0 or _neck_bone < 0 or hips < 0 or mesh == null:
		return false
	for group in [ARMS, LEGS]:
		for side in group:
			for b in group[side]:
				if skeleton.find_bone(b) < 0:
					push_warning("HoloAvatar: bone %s missing" % b)
					return false

	# Rest pose measured in body space.
	var to_body := _model.transform * _relative_to_model(skeleton)
	var rest := func(bone: int) -> Transform3D: return to_body * skeleton.get_bone_global_rest(bone)
	var rest_basis := func(bone: int) -> Basis: return (to_body.basis * skeleton.get_bone_global_rest(bone).basis).orthonormalized()
	_neck_b = rest.call(_neck_bone).origin
	_hips_b = rest.call(hips).origin
	_head_rest = rest_basis.call(_head_bone)
	_neck_rest = rest_basis.call(_neck_bone)
	var mesh_to_body := _model.transform * _relative_to_model(mesh)
	_ground_b = INF
	var top_b := -INF
	var box := mesh.get_aabb()
	for i in 8:
		var y := (mesh_to_body * box.get_endpoint(i)).y
		_ground_b = minf(_ground_b, y)
		top_b = maxf(top_b, y)
	_stand_neck = _neck_b.y - _ground_b
	_u = STAND_HEIGHT / maxf(top_b - _ground_b, 0.1)
	_model.transform = _model_transform(_u)
	for side in ARMS:
		var a: Array = ARMS[side]
		var s := skeleton.find_bone(a[0])
		var e := skeleton.find_bone(a[1])
		var w := skeleton.find_bone(a[2])
		_hand_bones[side] = w
		_shoulder_b[side] = rest.call(s).origin
		_arm_len[side] = rest.call(s).origin.distance_to(rest.call(e).origin) + rest.call(e).origin.distance_to(rest.call(w).origin)
		var l: Array = LEGS[side]
		var foot := skeleton.find_bone(l[2])
		_foot_bones[side] = foot
		_thigh_b[side] = rest.call(skeleton.find_bone(l[0])).origin
		_foot_b[side] = rest.call(foot).origin
		_foot_rest[side] = rest_basis.call(foot)
		_curl_fingers(side)

	# Modifiers run in child order: neck and head -> arm and leg IK -> hands and feet.
	_pre = _BonePoser.new()
	_pre.name = "HoloHeadPose"
	skeleton.add_child(_pre)

	var ik := TwoBoneIK3D.new()
	ik.name = "HoloLimbIK"
	skeleton.add_child(ik)
	ik.set_setting_count(ARMS.size() + LEGS.size())
	var i := 0
	for limb in [["arm", ARMS], ["leg", LEGS]]:
		for side in limb[1]:
			var bones: Array = limb[1][side]
			var key: String = "%s_%s" % [limb[0], side]
			var target := Node3D.new()
			target.name = "Target_" + key
			add_child(target)
			var pole := Node3D.new()
			pole.name = "Pole_" + key
			add_child(pole)
			_targets[key] = target
			_poles[key] = pole
			ik.set_root_bone_name(i, bones[0])
			ik.set_middle_bone_name(i, bones[1])
			ik.set_end_bone_name(i, bones[2])
			ik.set_target_node(i, ik.get_path_to(target))
			ik.set_pole_node(i, ik.get_path_to(pole))
			i += 1

	_post = _BonePoser.new()
	_post.name = "HoloHandPose"
	skeleton.add_child(_post)
	ok = true
	return true


## How far the standing body's head is above the recorded head (negative: below), valid after
## drive(). The player moves the headset, the hand rays and the name by this much, so they stay on
## the body.
func lift() -> float:
	return _lift


## World height of the floor the ghost stands on (valid after drive()).
func floor_height() -> float:
	return _floor


## Point on the floor under the body (valid after drive()).
func ground_point() -> Vector3:
	var p := global_transform * (_hips_b * _u)
	return Vector3(p.x, _floor, p.z)


## Floor under a recorded neck position: the deck the author stood (or sat) on, or the ground outside.
func find_floor(neck: Vector3) -> float:
	var stand := _stand_neck * _u
	var deck := NAN
	for f in (NoteManager.space.get("floors", []) as Array):
		var y := float((f as Dictionary).get("y", 0.0))
		var d := neck.y - y
		if d > 0.45 and d < FLOOR_REACH and (is_nan(deck) or y > deck):
			deck = y
	var hit := NAN
	if is_inside_tree():
		var q := PhysicsRayQueryParameters3D.create(neck, neck + Vector3.DOWN * (FLOOR_REACH + 0.3))
		var res := get_world_3d().direct_space_state.intersect_ray(q)
		if not res.is_empty() and neck.y - (res["position"] as Vector3).y > 0.45:
			hit = (res["position"] as Vector3).y
	if not is_nan(deck) and not is_nan(hit):
		# Above the deck: a table or a rack under the head. Below it: outside, over lower ground.
		return hit if hit < deck + 0.3 else deck
	if not is_nan(deck):
		return deck
	if not is_nan(hit):
		return hit
	return neck.y - stand


## head: world transform of the eyes. hands: side -> world aim-pose Transform3D, or null if untracked.
## snap = true jumps straight to the pose (first frame, seeking).
func drive(head: Transform3D, hands: Dictionary, delta: float, snap: bool = false) -> void:
	if not ok:
		return
	var hb := head.basis.orthonormalized()
	# Body yaw follows the head's yaw once the head has turned past the dead zone.
	var fwd := -hb.z
	fwd.y = 0.0
	var head_yaw := atan2(-fwd.x, -fwd.z) if fwd.length() > 0.05 else _yaw
	if snap or not _yaw_set:
		_yaw = head_yaw
		_yaw_set = true
	else:
		var diff := angle_difference(_yaw, head_yaw)
		var past := signf(diff) * maxf(absf(diff) - YAW_DEAD, 0.0)
		_yaw += past * (1.0 - exp(-YAW_FOLLOW * delta))
	var yaw_b := Basis(Vector3.UP, _yaw)
	var neck_rec := head.origin + hb * NECK_FROM_EYES

	var fl := find_floor(neck_rec)
	if snap or not _floor_set or absf(fl - _floor) > 0.3:
		_floor = fl
		_floor_set = true
	else:
		_floor = lerpf(_floor, fl, 1.0 - exp(-8.0 * delta))

	# Always standing: the neck is at standing height above the floor, under the recorded head.
	var neck_world := Vector3(neck_rec.x, _floor + _stand_neck * _u, neck_rec.z)
	_lift = neck_world.y - neck_rec.y
	var up := Vector3.UP * _lift
	var body := yaw_b
	global_transform = Transform3D(body, neck_world - body * (_neck_b * _u))

	var to_skel := skeleton.global_transform.basis.orthonormalized().inverse()
	# Neck takes part of the head's turn, the head bone takes the recorded rotation.
	var head_turn := hb * body.inverse()
	var neck_turn := Basis(Quaternion.IDENTITY.slerp(head_turn.get_rotation_quaternion(), NECK_SHARE))
	_pre.poses = {
		_neck_bone: to_skel * neck_turn * body * _neck_rest,
		_head_bone: to_skel * hb * _head_rest,
	}

	# Feet: planted on the floor under the body, stepping when the body leaves them behind.
	var hips_world := global_transform * (_hips_b * _u)
	var com := hips_world.lerp(neck_world, 0.3)
	com.y = _floor
	_update_feet(com, yaw_b, delta, snap)
	var post := {}
	for side in LEGS:
		var f: Dictionary = _feet[side]
		var out := yaw_b * (Vector3.LEFT if side == "left" else Vector3.RIGHT)
		(_targets["leg_" + side] as Node3D).global_position = (f["pos"] as Vector3) + Vector3.UP * ((_foot_b[side] as Vector3).y - _ground_b) * _u
		var thigh := global_transform * ((_thigh_b[side] as Vector3) * _u)
		(_poles["leg_" + side] as Node3D).global_position = thigh + yaw_b * Vector3.FORWARD * 0.8 + out * 0.12 + Vector3.DOWN * 0.25
		post[_foot_bones[side]] = to_skel * Basis(Vector3.UP, float(f["yaw"])) * (_foot_rest[side] as Basis)

	# Arms: reach for the wrist; elbows down, back and out. Untracked arm: hangs at the side.
	for side in ARMS:
		var target: Node3D = _targets["arm_" + side]
		var pole: Node3D = _poles["arm_" + side]
		var out := yaw_b * (Vector3.LEFT if side == "left" else Vector3.RIGHT)
		var shoulder := global_transform * ((_shoulder_b[side] as Vector3) * _u)
		pole.global_position = shoulder + Vector3.DOWN * 0.45 + yaw_b * Vector3.BACK * 0.25 + out * 0.3
		var aim: Variant = hands.get(side)
		if aim is Transform3D:
			var a := aim as Transform3D
			target.global_position = a.origin + up + a.basis.orthonormalized() * WRIST_FROM_AIM
			post[_hand_bones[side]] = to_skel * a.basis.orthonormalized() * HAND_FROM_AIM
		else:
			var reach: float = float(_arm_len[side]) * _u * 0.96
			target.global_position = shoulder + (Vector3.DOWN * 0.96 + out * 0.16 + yaw_b * Vector3.FORWARD * 0.12).normalized() * reach
	_post.poses = post


func _update_feet(com: Vector3, yaw_b: Basis, delta: float, snap: bool) -> void:
	var vel := Vector3.ZERO
	if _com_set and delta > 0.0 and not snap:
		vel = (com - _com_prev) / delta
		vel.y = 0.0
	_vel = Vector3.ZERO if snap else _vel.lerp(vel, 1.0 - exp(-10.0 * delta))
	_com_prev = com
	_com_set = true
	var lead := (_vel * STEP_LEAD).limit_length(0.18 * _u)
	var homes := {}
	var jump := snap or _feet.is_empty()
	for side in LEGS:
		homes[side] = com + yaw_b * Vector3((_foot_b[side] as Vector3).x * _u, 0.0, 0.0)
		if not jump and ((_feet[side] as Dictionary)["pos"] as Vector3).distance_to(homes[side]) > 0.7:
			jump = true                                   # teleported: no step is that long
	if jump:
		for side in LEGS:
			_feet[side] = {"pos": homes[side], "yaw": _yaw, "from": homes[side], "from_yaw": _yaw, "u": 1.0, "stepping": false}
		return
	var busy := false
	for side in LEGS:
		var f: Dictionary = _feet[side]
		if f["stepping"]:
			f["u"] = float(f["u"]) + delta / STEP_TIME
			var u := clampf(float(f["u"]), 0.0, 1.0)
			var e := smoothstep(0.0, 1.0, u)
			var p := (f["from"] as Vector3).lerp((homes[side] as Vector3) + lead * (1.0 - u), e)
			p.y = _floor + sin(u * PI) * STEP_LIFT * _u
			f["pos"] = p
			f["yaw"] = lerp_angle(float(f["from_yaw"]), _yaw, e)
			if u >= 1.0:
				f["stepping"] = false
			else:
				busy = true
		else:
			var p2: Vector3 = f["pos"]
			p2.y = _floor
			f["pos"] = p2
	if busy:
		return
	# Start one step: the foot that is furthest from where it should be.
	var worst := ""
	var worst_score := 1.0
	for side in LEGS:
		var f: Dictionary = _feet[side]
		var score := ((f["pos"] as Vector3).distance_to((homes[side] as Vector3) + lead)) / (STEP_DIST * _u) + absf(angle_difference(float(f["yaw"]), _yaw)) / STEP_YAW
		if score > worst_score:
			worst_score = score
			worst = side
	if worst != "":
		var f: Dictionary = _feet[worst]
		f["from"] = f["pos"]
		f["from_yaw"] = f["yaw"]
		f["u"] = 0.0
		f["stepping"] = true


## Curls the fingers of one hand toward the palm (a fixed pose, set once).
func _curl_fingers(side: String) -> void:
	var sfx := ".L" if side == "left" else ".R"
	var index := skeleton.find_bone("f_index.01" + sfx)
	var pinky := skeleton.find_bone("f_pinky.01" + sfx)
	var index2 := skeleton.find_bone("f_index.02" + sfx)
	if index < 0 or pinky < 0 or index2 < 0:
		return
	# Skeleton space, rest pose: finger direction, across the knuckles, and from those the palm side.
	var dir := (skeleton.get_bone_global_rest(index2).origin - skeleton.get_bone_global_rest(index).origin).normalized()
	var across := (skeleton.get_bone_global_rest(pinky).origin - skeleton.get_bone_global_rest(index).origin).normalized()
	var palm := dir.cross(across).normalized() * (1.0 if side == "right" else -1.0)
	for finger in FINGER_CURL:
		var angle: float = FINGER_CURL[finger]
		for joint in ["01", "02", "03"]:
			var b := skeleton.find_bone("%s.%s%s" % [finger, joint, sfx])
			if b < 0:
				continue
			var g := skeleton.get_bone_global_rest(b).basis.orthonormalized()
			var along := g.y.normalized()                           # Rigify bones run along +Y
			var axis := along.cross(palm)
			if axis.length() < 0.05:
				continue
			var local_axis := (g.inverse() * axis.normalized()).normalized()
			var a := angle * (0.6 if joint == "01" and finger != "thumb" else 1.0)
			skeleton.set_bone_pose_rotation(b, skeleton.get_bone_rest(b).basis.get_rotation_quaternion() * Quaternion(local_axis, a))


func _model_transform(height: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, MODEL_TURN).scaled(Vector3.ONE * MODEL_SCALE * height), Vector3.ZERO)


## Transform of a node relative to the model root, from local transforms (works outside the tree).
func _relative_to_model(node: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != _model and n != null:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## Sets bone rotations in skeleton space while keeping where each bone already is.
class _BonePoser extends SkeletonModifier3D:
	var poses: Dictionary = {}          # bone index -> Basis (skeleton space), parents before children

	func _process_modification_with_delta(_delta: float) -> void:
		var sk := get_skeleton()
		if sk == null:
			return
		for b in poses:
			var g := sk.get_bone_global_pose(b)
			g.basis = (poses[b] as Basis).orthonormalized()
			sk.set_bone_global_pose(b, g)
