class_name NoteData
extends RefCounted
## 스티키 노트 한 장의 순수 데이터.
## 화면에 보이는 3D 오브젝트(StickyNote)와 분리해 두어서
## JSON으로 저장·불러오기·전송이 쉽다.

enum Type { CONSTRAINT, REQUIREMENT, PROPOSAL, QUESTION, OBSERVATION }
enum Role { ENGINEER, ARCHITECT, INHABITANT }

const TYPE_NAMES: Array[String] = ["Constraint", "Requirement", "Proposal", "Question", "Observation"]
const TYPE_INITIALS: Array[String] = ["C", "R", "P", "Q", "O"]
const ROLE_NAMES: Array[String] = ["Engineer", "Architect", "Inhabitant"]
const ROLE_INITIALS: Array[String] = ["E", "A", "I"]
const TYPE_COLORS: Array[Color] = [
	Color("e05a4e"), # Constraint   빨강  (엔지니어링 제약, 바꿀 수 없는 것)
	Color("f2a541"), # Requirement  주황  (반드시 필요한 것)
	Color("4ea6e0"), # Proposal     파랑  (이렇게 바꾸면 어떨까)
	Color("a26be0"), # Question     보라  (모르겠다, 확인 필요)
	Color("6fcf7a"), # Observation  초록  (살아 보니 이렇더라)
]

# ---- 누가 ----
var id: String = ""
var parent_id: String = ""           # 답글이면 원 노트의 id. 비어 있으면 원 노트
var author: String = ""
var role: int = Role.ARCHITECT

# ---- 무엇 ----
var type: int = Type.OBSERVATION
var text: String = ""
var resolved: bool = false

# ---- 어디 ----
var position: Vector3 = Vector3.ZERO        # 노트가 붙은 월드 좌표
var normal: Vector3 = Vector3.UP            # 붙은 표면의 법선 (노트가 서는 방향)
var anchor_name: String = ""                # 붙은 오브젝트 이름 (예: Hatch, Rack_A)
var camera_position: Vector3 = Vector3.ZERO # 작성 당시 눈 위치 (텔레포트용)
var camera_rotation: Vector3 = Vector3.ZERO # 작성 당시 시선 (오일러, 라디안)

# ---- 어떻게 (미디어는 media 폴더 안의 파일 이름만 저장) ----
var screenshot_file: String = ""   # 썸네일 png (클립이 있으면 첫 프레임)
var audio_file: String = ""        # 음성 wav (클립이 있으면 클립 폴더 안의 것)
var clip_file: String = ""         # 화면+음성 클립. "clip_<id>/clip.json"

var created_at: String = ""                 # "YYYY-MM-DD HH:MM:SS"


static func make_new() -> NoteData:
	var n := NoteData.new()
	n.id = "%d_%04d" % [int(Time.get_unix_time_from_system()), randi() % 10000]
	n.created_at = Time.get_datetime_string_from_system(false, true)
	return n


## 역할별로 가장 자주 쓰는 유형. 새 노트의 기본값.
static func default_type_for_role(r: int) -> int:
	match r:
		Role.ENGINEER:
			return Type.CONSTRAINT
		Role.INHABITANT:
			return Type.OBSERVATION
		_:
			return Type.PROPOSAL


static func type_color(t: int) -> Color:
	return TYPE_COLORS[clampi(t, 0, TYPE_COLORS.size() - 1)]


func color() -> Color:
	return type_color(type)


func type_name() -> String:
	return TYPE_NAMES[clampi(type, 0, TYPE_NAMES.size() - 1)]


func role_name() -> String:
	return ROLE_NAMES[clampi(role, 0, ROLE_NAMES.size() - 1)]


func role_initial() -> String:
	return ROLE_INITIALS[clampi(role, 0, ROLE_INITIALS.size() - 1)]


func has_clip() -> bool:
	return clip_file != ""


func has_media() -> bool:
	return clip_file != "" or audio_file != ""


func is_reply() -> bool:
	return parent_id != ""


func short_text(max_chars: int) -> String:
	var t := text.replace("\n", " ").strip_edges()
	if t.length() > max_chars:
		return t.substr(0, max_chars - 1) + "…"
	return t


## "2026-10-24 17:30:00" -> "10-24 17:30"
func short_time() -> String:
	if created_at.length() >= 16:
		return created_at.substr(5, 11)
	return created_at


# ---------------- 직렬화 ----------------

static func _v3_to_arr(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func _arr_to_v3(a: Variant, fallback: Vector3) -> Vector3:
	if a is Array and a.size() == 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return fallback


func to_dict() -> Dictionary:
	return {
		"id": id,
		"parent_id": parent_id,
		"author": author,
		"role": role,
		"type": type,
		"text": text,
		"resolved": resolved,
		"position": _v3_to_arr(position),
		"normal": _v3_to_arr(normal),
		"anchor_name": anchor_name,
		"camera_position": _v3_to_arr(camera_position),
		"camera_rotation": _v3_to_arr(camera_rotation),
		"screenshot_file": screenshot_file,
		"audio_file": audio_file,
		"clip_file": clip_file,
		"created_at": created_at,
	}


static func from_dict(d: Dictionary) -> NoteData:
	var n := NoteData.new()
	n.id = str(d.get("id", ""))
	n.parent_id = str(d.get("parent_id", ""))
	n.author = str(d.get("author", ""))
	n.role = int(d.get("role", Role.ARCHITECT))
	n.type = int(d.get("type", Type.OBSERVATION))
	n.text = str(d.get("text", ""))
	n.resolved = bool(d.get("resolved", false))
	n.position = _arr_to_v3(d.get("position"), Vector3.ZERO)
	n.normal = _arr_to_v3(d.get("normal"), Vector3.UP)
	n.anchor_name = str(d.get("anchor_name", ""))
	n.camera_position = _arr_to_v3(d.get("camera_position"), n.position)
	n.camera_rotation = _arr_to_v3(d.get("camera_rotation"), Vector3.ZERO)
	n.screenshot_file = str(d.get("screenshot_file", ""))
	n.audio_file = str(d.get("audio_file", ""))
	n.clip_file = str(d.get("clip_file", ""))
	n.created_at = str(d.get("created_at", ""))
	if n.id == "":
		n.id = NoteData.make_new().id
	return n
