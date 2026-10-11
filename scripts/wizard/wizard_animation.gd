class_name WizardAnimation
extends RefCounted
## AnimationTree-driven character animation, built in code.
##
##   loco (BlendSpace1D: Idle / Walk / Run by speed, synced)
##     -> loco_rate (TimeScale: playback matched to stride, negative = backpedal)
##     -> cast  (OneShot, UPPER BODY ONLY: legs keep walking while you cast)
##     -> hit   (OneShot, full body)
##     -> dodge (OneShot, full body)
##     -> ko    (Blend2 with KO clip, held on death)
##
## The source clips carry root motion (the Root bone walks forward 1.48 m per
## Walk cycle and 1.9 m per Run cycle, then snaps back on loop). That track is
## consumed via root_motion_track so the mesh stays on the capsule; movement
## comes from the CharacterBody only.

const IDLE := "Idle"
const WALK := "Walk"
const RUN := "Run"
const CAST := "Throw"
const HIT := "Hit"
const DODGE := "Dodge"
const KO := "KO"

## Natural forward speed of each clip (root-motion distance / clip length),
## measured with dev/probe.gd.
const WALK_SPEED := 1.39
const RUN_SPEED := 2.37
## Above RUN_SPEED the cycle is sped up, but not 1:1 (the clip's stride is
## short; full matching looks frantic). Exponent < 1 trades a little slide for
## a natural cadence.
const OVERSPEED_EXP := 0.85

const SKEL := "Skeleton/Skeleton3D:"
const UPPER_BONES := ["Spine", "Spine1", "Neck", "Head",
	"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "LeftHandProp",
	"LeftHandIndex1", "LeftHandIndex2", "LeftHandMiddle1", "LeftHandMiddle2", "LeftHandPinky1", "LeftHandPinky2",
	"LeftHandRing1", "LeftHandRing2", "LeftHandThumb1", "LeftHandThumb2",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand", "RightHandProp",
	"RightHandIndex1", "RightHandIndex2", "RightHandMiddle1", "RightHandMiddle2", "RightHandPinky1", "RightHandPinky2",
	"RightHandRing1", "RightHandRing2", "RightHandThumb1", "RightHandThumb2"]

var tree: AnimationTree
var _ok := false
var _dead := false
var _blend := 0.0      # smoothed loco blend position
var _rate := 1.0       # smoothed playback rate

func _init(player: AnimationPlayer, model_root: Node) -> void:
	for clip in [IDLE, WALK, RUN, CAST, HIT, DODGE, KO]:
		if not player.has_animation(clip):
			push_warning("WizardAnimation: missing clip " + clip)
			return
	for clip in [IDLE, WALK, RUN]:
		player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	for clip in [CAST, HIT, DODGE, KO]:
		player.get_animation(clip).loop_mode = Animation.LOOP_NONE
	player.stop()

	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	model_root.add_child(tree)
	tree.root_node = NodePath("..")
	tree.anim_player = tree.get_path_to(player)
	tree.root_motion_track = NodePath(SKEL + "Root")
	tree.tree_root = _build_graph()
	tree.active = true
	_ok = true

func _anim(clip: String) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = clip
	return a

func _build_graph() -> AnimationNodeBlendTree:
	var bt := AnimationNodeBlendTree.new()

	var loco := AnimationNodeBlendSpace1D.new()
	loco.min_space = 0.0
	loco.max_space = RUN_SPEED
	loco.sync = true
	loco.add_blend_point(_anim(IDLE), 0.0, -1, &"idle")
	loco.add_blend_point(_anim(WALK), WALK_SPEED, -1, &"walk")
	loco.add_blend_point(_anim(RUN), RUN_SPEED, -1, &"run")
	bt.add_node("loco", loco, Vector2(0, 0))

	bt.add_node("loco_rate", AnimationNodeTimeScale.new(), Vector2(200, 0))
	bt.connect_node("loco_rate", 0, "loco")

	# Upper-body cast layer.
	bt.add_node("cast_clip", _anim(CAST), Vector2(200, 160))
	bt.add_node("cast_rate", AnimationNodeTimeScale.new(), Vector2(350, 160))
	bt.connect_node("cast_rate", 0, "cast_clip")
	var cast := AnimationNodeOneShot.new()
	cast.fadein_time = 0.08
	cast.fadeout_time = 0.2
	cast.filter_enabled = true
	for b in UPPER_BONES:
		cast.set_filter_path(NodePath(SKEL + b), true)
	bt.add_node("cast", cast, Vector2(500, 0))
	bt.connect_node("cast", 0, "loco_rate")
	bt.connect_node("cast", 1, "cast_rate")

	# Full-body reactions.
	bt.add_node("hit_clip", _anim(HIT), Vector2(500, 160))
	bt.add_node("hit_rate", AnimationNodeTimeScale.new(), Vector2(650, 160))
	bt.connect_node("hit_rate", 0, "hit_clip")
	var hit := AnimationNodeOneShot.new()
	hit.fadein_time = 0.06
	hit.fadeout_time = 0.25
	bt.add_node("hit", hit, Vector2(800, 0))
	bt.connect_node("hit", 0, "cast")
	bt.connect_node("hit", 1, "hit_rate")

	bt.add_node("dodge_clip", _anim(DODGE), Vector2(800, 160))
	bt.add_node("dodge_rate", AnimationNodeTimeScale.new(), Vector2(950, 160))
	bt.connect_node("dodge_rate", 0, "dodge_clip")
	var dodge := AnimationNodeOneShot.new()
	dodge.fadein_time = 0.05
	dodge.fadeout_time = 0.2
	bt.add_node("dodge", dodge, Vector2(1100, 0))
	bt.connect_node("dodge", 0, "hit")
	bt.connect_node("dodge", 1, "dodge_rate")

	# Death: KO clip blended in fully and held on its last frame.
	bt.add_node("ko_clip", _anim(KO), Vector2(1100, 160))
	bt.add_node("ko_seek", AnimationNodeTimeSeek.new(), Vector2(1250, 160))
	bt.connect_node("ko_seek", 0, "ko_clip")
	bt.add_node("ko", AnimationNodeBlend2.new(), Vector2(1400, 0))
	bt.connect_node("ko", 0, "dodge")
	bt.connect_node("ko", 1, "ko_seek")

	bt.connect_node("output", 0, "ko")
	return bt

## Called every physics frame with the planar speed. `direction` is +1 for
## forward, -1 for backpedal (plays the cycle in reverse).
func set_locomotion(speed: float, direction: float, delta: float) -> void:
	if not _ok or _dead:
		return
	var target_blend := minf(speed, RUN_SPEED)
	var target_rate := 1.0
	if speed > RUN_SPEED:
		target_rate = pow(speed / RUN_SPEED, OVERSPEED_EXP)
	elif speed > 0.15 and speed < WALK_SPEED:
		target_rate = maxf(speed / WALK_SPEED, 0.6)
	var k := 1.0 - exp(-14.0 * delta)
	_blend = lerpf(_blend, target_blend, k)
	_rate = lerpf(_rate, target_rate, k)
	tree.set("parameters/loco/blend_position", _blend)
	tree.set("parameters/loco_rate/scale", _rate * (-1.0 if direction < 0.0 else 1.0))

func play_cast(speed: float = 1.6) -> void:
	_fire("cast", speed)

func play_hit(speed: float = 1.4) -> void:
	_fire("hit", speed)

func play_dodge(speed: float = 2.2) -> void:
	_fire("dodge", speed)

func _fire(shot: String, speed: float) -> void:
	if not _ok or _dead:
		return
	tree.set("parameters/%s_rate/scale" % shot, speed)
	tree.set("parameters/%s/request" % shot, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

func play_ko() -> void:
	if not _ok:
		return
	_dead = true
	for s in ["cast", "hit", "dodge"]:
		tree.set("parameters/%s/request" % s, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	tree.set("parameters/ko_seek/seek_request", 0.0)
	var tw := tree.create_tween()
	tw.tween_method(func(v: float) -> void: tree.set("parameters/ko/blend_amount", v), 0.0, 1.0, 0.15)

func reset() -> void:
	if not _ok:
		return
	_dead = false
	_blend = 0.0
	_rate = 1.0
	for s in ["cast", "hit", "dodge"]:
		tree.set("parameters/%s/request" % s, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	tree.set("parameters/ko/blend_amount", 0.0)
	tree.set("parameters/loco/blend_position", 0.0)
	tree.set("parameters/loco_rate/scale", 1.0)
