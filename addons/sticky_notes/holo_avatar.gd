class_name HoloAvatar
extends Node3D
## Full-body ghost for holonotes, driven only by what a headset records: the head and two hands.
##
##   head  -> the head bone turns with the recorded head; the body hangs from the neck and turns
##            with the head's yaw (smoothed), so leaning and looking around read naturally
##   hands -> TwoBoneIK3D bends each arm (shoulder -> elbow -> wrist) to reach the controller, with
##            the elbow pulled down and out like a real one; then the hand bone takes the
##            controller's rotation so the hand points where the author pointed
##   no hand tracking for a side -> that arm hangs at rest
##
## Model: assets/models/avatar/male_base_mesh.glb (CC0, Rigify-style bone names). It faces +X and
## is 1.94 m tall, so it is turned to face -Z and scaled to about 1.75 m.

const MODEL := "res://assets/models/avatar/male_base_mesh.glb"
const MODEL_SCALE := 0.9
const MODEL_TURN := PI * 0.5            # +X facing -> Godot's -Z forward
const HEAD_BONE := "spine.005"
const NECK_BONE := "spine.004"
const ARMS := {
	"left": ["upper_arm.L", "forearm.L", "hand.L"],
	"right": ["upper_arm.R", "forearm.R", "hand.R"],
}
## Neck relative to the eyes, in head-local space (below and behind).
const NECK_FROM_EYES := Vector3(0.0, -0.15, 0.02)
## Wrist relative to the controller's aim pose (behind the grip, slightly below the pointing ray).
const WRIST_FROM_AIM := Vector3(0.0, -0.03, 0.11)
## Hand bone axes in the controller's aim frame: fingers (bone +Y) along the ray (-Z), thumb (bone +Z) up.
const HAND_FROM_AIM := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
const YAW_FOLLOW := 6.0                 # 1/s, how fast the body turns after the head

var ok: bool = false
var skeleton: Skeleton3D
var mesh: MeshInstance3D

var _model: Node3D
var _ik: SkeletonModifier3D
var _pre: _BonePoser                  # head (before IK)
var _post: _BonePoser                 # hands (after IK)
var _targets: Dictionary = {}         # side -> Node3D the IK reaches for
var _poles: Dictionary = {}           # side -> Node3D the elbow bends toward
var _head_bone: int = -1
var _neck_model: Vector3              # neck position in model space (unscaled, unturned)
var _head_rest: Basis                 # head bone's world basis when looking straight down -Z
var _hand_bones: Dictionary = {}      # side -> bone index
var _shoulder_bones: Dictionary = {}  # side -> bone index
var _yaw: float = 0.0
var _yaw_set: bool = false


## Builds the body with the given material. False if the model or its bones are missing
## (the caller keeps the simple ghost then).
func setup(material: Material) -> bool:
	var scene: PackedScene = load(MODEL) if ResourceLoader.exists(MODEL) else null
	if scene == null:
		push_warning("HoloAvatar: %s not found, using the simple ghost" % MODEL)
		return false
	_model = scene.instantiate()
	_model.transform = Transform3D(Basis(Vector3.UP, MODEL_TURN).scaled(Vector3.ONE * MODEL_SCALE), Vector3.ZERO)
	add_child(_model)
	var sks := _model.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return false
	skeleton = sks[0]
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		mesh = mi
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_head_bone = skeleton.find_bone(HEAD_BONE)
	var neck := skeleton.find_bone(NECK_BONE)
	if _head_bone < 0 or neck < 0:
		return false
	var model_xf := _model.transform               # avatar-local, with the turn and scale
	var skel_in_model := Transform3D.IDENTITY     # skeleton relative to the model root, from local transforms
	var n: Node = skeleton
	while n != _model and n != null:
		if n is Node3D:
			skel_in_model = (n as Node3D).transform * skel_in_model
		n = n.get_parent()
	_neck_model = (skel_in_model * skeleton.get_bone_global_rest(neck)).origin
	_head_rest = (model_xf.basis * skel_in_model.basis * skeleton.get_bone_global_rest(_head_bone).basis).orthonormalized()

	# Modifiers run in child order: head pose -> arm IK -> hand rotation.
	_pre = _BonePoser.new()
	_pre.name = "HoloHeadPose"
	skeleton.add_child(_pre)

	var ik := TwoBoneIK3D.new()
	ik.name = "HoloArmIK"
	skeleton.add_child(ik)
	ik.set_setting_count(ARMS.size())
	var i := 0
	for side in ARMS:
		var bones: Array = ARMS[side]
		for b in bones:
			if skeleton.find_bone(b) < 0:
				push_warning("HoloAvatar: bone %s missing" % b)
				return false
		var target := Node3D.new()
		target.name = "Target_" + side
		add_child(target)
		var pole := Node3D.new()
		pole.name = "Pole_" + side
		add_child(pole)
		_targets[side] = target
		_poles[side] = pole
		ik.set_root_bone_name(i, bones[0])
		ik.set_middle_bone_name(i, bones[1])
		ik.set_end_bone_name(i, bones[2])
		ik.set_target_node(i, ik.get_path_to(target))
		ik.set_pole_node(i, ik.get_path_to(pole))
		_hand_bones[side] = skeleton.find_bone(bones[2])
		_shoulder_bones[side] = skeleton.find_bone(bones[0])
		i += 1
	_ik = ik

	_post = _BonePoser.new()
	_post.name = "HoloHandPose"
	skeleton.add_child(_post)
	ok = true
	return true


## head: world transform of the eyes. hands: side -> world aim-pose Transform3D, or null if untracked.
## snap = true jumps straight to the head's yaw (first frame, seeking).
func drive(head: Transform3D, hands: Dictionary, delta: float, snap: bool = false) -> void:
	if not ok:
		return
	# Body yaw follows the head's yaw, smoothed.
	var fwd := -head.basis.z
	fwd.y = 0.0
	var head_yaw := atan2(-fwd.x, -fwd.z) if fwd.length() > 0.05 else _yaw
	if snap or not _yaw_set:
		_yaw = head_yaw
		_yaw_set = true
	else:
		_yaw = lerp_angle(_yaw, head_yaw, 1.0 - exp(-YAW_FOLLOW * delta))
	var body := Basis(Vector3.UP, _yaw)
	# Hang the body from the neck, which sits just below and behind the eyes.
	var neck_world := head.origin + head.basis.orthonormalized() * NECK_FROM_EYES
	var neck_local := _model.transform * _neck_model          # avatar-local before the yaw
	global_transform = Transform3D(body, neck_world - body * neck_local)

	var to_skel := skeleton.global_transform.basis.orthonormalized().inverse()
	# Head bone: the recorded head rotation applied to the rest pose.
	_pre.poses = {_head_bone: to_skel * head.basis.orthonormalized() * _head_rest}

	# Arms: reach for the wrist; elbows down, back and out. Untracked arm: reach for its rest wrist.
	var hand_poses := {}
	for side in ARMS:
		var target: Node3D = _targets[side]
		var pole: Node3D = _poles[side]
		var out := body * (Vector3.LEFT if side == "left" else Vector3.RIGHT)
		var shoulder := (skeleton.global_transform * skeleton.get_bone_global_pose(_shoulder_bones[side])).origin
		pole.global_position = shoulder + Vector3.DOWN * 0.45 + body * Vector3.BACK * 0.25 + out * 0.3
		var aim: Variant = hands.get(side)
		if aim is Transform3D:
			var a := aim as Transform3D
			target.global_position = a.origin + a.basis.orthonormalized() * WRIST_FROM_AIM
			hand_poses[_hand_bones[side]] = to_skel * a.basis.orthonormalized() * HAND_FROM_AIM
		else:
			target.global_position = (skeleton.global_transform * skeleton.get_bone_global_rest(_hand_bones[side])).origin
	_post.poses = hand_poses


## Sets bone rotations in skeleton space while keeping where each bone already is.
class _BonePoser extends SkeletonModifier3D:
	var poses: Dictionary = {}          # bone index -> Basis (skeleton space)

	func _process_modification_with_delta(_delta: float) -> void:
		var sk := get_skeleton()
		if sk == null:
			return
		for b in poses:
			var g := sk.get_bone_global_pose(b)
			g.basis = (poses[b] as Basis).orthonormalized()
			sk.set_bone_global_pose(b, g)
