extends TestCase
## Milestone 10 asset pipeline: authored models, animations, materials, audio and batching.

const SURVIVOR_ANIMS := ["idle", "walk", "run", "crouch_idle", "crouch_walk", "interact", "revive", "use_item", "hit",
	"downed_idle", "crawl", "death", "dead"]
const HUNTER_ANIMS := ["idle", "patrol", "investigate", "search", "chase", "attack", "alert", "stunned", "door_open"]


func _visual(path: String) -> SkinnedCharacterVisual:
	var v: SkinnedCharacterVisual = load(path).instantiate()
	runner.add_child(v)
	return v


func test_characters_have_rigs_and_all_animations() -> void:
	for spec in [["res://assets/characters/survivor/survivor_visual.tscn", SURVIVOR_ANIMS], ["res://assets/creatures/hunter/hunter_visual.tscn", HUNTER_ANIMS]]:
		var v := _visual(spec[0])
		await wait_frames(2)
		check(v.skeleton != null and v.skeleton.get_bone_count() >= 18, "%s has a skeleton (%d bones)" % [spec[0], v.skeleton.get_bone_count() if v.skeleton else 0])
		check(v.anim_player != null, "%s has animations" % spec[0])
		check(v.tree != null and v.tree.active, "%s animation tree active" % spec[0])
		for a: String in spec[1]:
			check(v.anim_player.has_animation(a), "%s has animation '%s'" % [spec[0].get_file(), a])
		check(v.flashlight_anchor() != v, "%s has a mount point" % spec[0].get_file())
		v.queue_free()


func test_survivor_animation_states_switch() -> void:
	var v := _visual("res://assets/characters/survivor/survivor_visual.tscn")
	await wait_frames(2)
	var cases := [[CharacterVisual.Pose.STAND, "stand"], [CharacterVisual.Pose.CROUCH, "crouch"], [CharacterVisual.Pose.DOWNED, "downed"], [CharacterVisual.Pose.DEAD, "dead"]]
	for c: Array in cases:
		v.set_motion(0.5, c[0], false)
		await wait_frames(3)
		eq(str(v.tree.get("parameters/pose/current_state")), c[1], "pose transition")
	v.set_motion(0.0, CharacterVisual.Pose.STAND, false)
	v.play_action(&"interact")
	await wait_frames(3)
	eq(str(v.tree.get("parameters/work/current_state")), "interact", "interaction animation layer")
	v.play_action(&"revive")
	await wait_frames(3)
	eq(str(v.tree.get("parameters/work/current_state")), "revive", "revive animation layer")
	v.apply_cosmetics({"0": "suit_hazard", "2": "helmet_red"})
	v.queue_free()


func test_item_icons_and_held_items() -> void:
	for it: ItemData in Content.items.values():
		check(it.get_icon() != null, "item %s has an inventory icon" % it.id)
		check(PropFactory.model_for(String(it.id), "items") != null, "item %s has a 3D model" % it.id)
	var v := _visual("res://assets/characters/survivor/survivor_visual.tscn")
	await wait_frames(2)
	var hand := v.find_child("HeldItem", true, false) as Node3D
	check(hand != null, "survivor has a hand attachment")
	v.set_held_item(&"medkit")
	await wait_frames(2)
	check(hand.get_child_count() == 1 and hand.get_child(0).find_children("*", "MeshInstance3D", true, false).size() > 0, "medkit model in hand")
	var palm := hand.global_position
	check(absf(palm.y - 0.89) < 0.25, "grip sits at hand height (%.2f)" % palm.y)
	v.set_held_item(&"crowbar")
	await wait_frames(2)
	eq(hand.get_child_count(), 1, "swapping items replaces the model")
	v.set_motion(0.2, CharacterVisual.Pose.DOWNED, false)
	await wait_frames(1)
	check(not (hand.get_child(0) as Node3D).visible, "held item hidden while downed")
	v.set_held_item(&"")
	await wait_frames(2)
	eq(hand.get_child_count(), 0, "empty hand when nothing selected")
	v.queue_free()


func test_hunter_states_follow_ai() -> void:
	var v := _visual("res://assets/creatures/hunter/hunter_visual.tscn")
	await wait_frames(2)
	for c in [[&"PATROL", 0.8, "patrol"], [&"CHASE", 2.4, "chase"], [&"INVESTIGATE", 1.0, "investigate"], [&"SEARCH", 0.0, "search"], [&"STUNNED", 0.0, "stunned"], [&"IDLE", 0.0, "idle"]]:
		v.set_ai_state(c[0])
		v.set_motion(c[1], CharacterVisual.Pose.STAND, false)
		await wait_frames(3)
		eq(str(v.tree.get("parameters/state/current_state")), c[2], "hunter %s animation" % c[0])
	v.play_action(&"attack")
	await wait_frames(2)
	check(bool(v.tree.get("parameters/attack/active")), "attack one-shot fires")
	v.queue_free()


func test_every_prop_device_and_architecture_kind_has_a_model() -> void:
	var props := ["bench", "crate_stack", "wall_cabinet", "vending", "filing_cabinet", "bookshelf", "shelf_unit", "shelf_row", "plant",
		"water_cooler", "fume_hood", "lab_cabinet", "med_cabinet", "specimen_tank", "med_bed", "iv_stand", "locker", "tool_locker",
		"workbench", "barrel", "server_rack", "server_row", "tank", "pump_unit", "monitor_desk", "containment_cell", "lab_bench",
		"desk_pair", "pillar", "console_island", "barrier", "lamp_post", "evac_beacon", "vehicle", "reception_desk", "scanner_gate",
		"debris", "pipe_cluster"]
	for k in props:
		check(not MeshBatcher.parts(k, "props").is_empty(), "prop model %s" % k)
	for k in ["terminal", "electrical_panel", "generator", "breaker", "containment_console", "evac_console", "alarm_panel", "elevator_panel"]:
		check(PropFactory.model_for(k, "props/devices") != null, "device model %s" % k)
	for k in ["door_frame", "door_panel", "light_fixture", "emergency_light", "wall_vent", "pipe_run", "cable_tray"]:
		check(PropFactory.model_for(k, "environment") != null, "architecture model %s" % k)
	# models must name only materials the library knows (otherwise they render flat grey)
	for k in props:
		for p: Dictionary in MeshBatcher.parts(k, "props"):
			var mesh: Mesh = p.mesh
			for i in mesh.get_surface_count():
				check(mesh.surface_get_material(i) is ShaderMaterial or mesh.surface_get_material(i) is BaseMaterial3D, "%s surface %d has a library material" % [k, i])


func test_pbr_texture_sets_and_materials() -> void:
	for n in ["concrete", "wall_panel", "wall_lab", "wall_medical", "wall_industrial", "floor_tile", "floor_lab", "metal_grate", "steel_dark",
			"steel_bright", "rust_metal", "metal_painted", "metal_yellow", "hazard", "asphalt", "ceiling", "fabric_suit", "fabric_dark",
			"plastic_white", "plastic_dark", "rubber", "wood", "cardboard", "hunter_skin"]:
		for kind in ["albedo", "normal", "orm"]:
			check(ResourceLoader.exists("res://assets/textures/%s/%s_%s.png" % [n, n, kind]), "texture %s_%s" % [n, kind])
	var floor_mat := MaterialLibrary.get_mat("floor_tile") as ShaderMaterial
	check(floor_mat != null and floor_mat.get_shader_parameter("normal_tex") != null, "architecture uses normal-mapped PBR")
	var prop := MaterialLibrary.get_mat("steel_dark") as ORMMaterial3D
	check(prop != null and prop.orm_texture != null, "props use ORM PBR materials")


func test_audio_cues_are_authored_assets() -> void:
	for id in ["amb_vent", "amb_hum", "amb_drone", "amb_distant", "amb_creak", "amb_drip", "music_tension", "music_pulse", "music_chase",
			"step_player", "step_hunter", "door_open", "door_close", "door_locked", "door_bash", "alarm", "power_down", "power_up",
			"generator_loop", "hunter_screech", "hunter_growl", "hunter_click", "hunter_attack", "hunter_breath", "hunter_presence",
			"player_hurt", "heartbeat", "ui_click", "ui_confirm", "ui_back", "ui_error", "pickup", "interact_loop", "interact_done",
			"search", "heal", "stun", "flashlight", "downed", "objective", "evac_horn", "elevator", "ping"]:
		check(Audio.has_authored(id), "authored audio for %s" % id)
		check(Audio.cue(id) is AudioStreamWAV, "cue %s loads" % id)
	var loop := Audio.cue("amb_vent") as AudioStreamWAV
	check(loop.loop_mode != AudioStreamWAV.LOOP_DISABLED, "ambience beds loop")
	var shot := Audio.cue("door_open") as AudioStreamWAV
	eq(shot.loop_mode, AudioStreamWAV.LOOP_DISABLED, "one-shots do not loop")


func test_facility_is_batched() -> void:
	Net.start_solo()
	Net.pending_mission = {"mission_id": &"power_restoration", "seed": 5, "roster": Net.players}
	var mission: MissionController = load(Router.MISSION).instantiate()
	mission.auto_route_results = false
	runner.add_child(mission)
	while not mission.running:
		await wait_frames(1)
	var mmis := mission.facility.find_children("*", "MultiMeshInstance3D", true, false)
	var instances := 0
	for m in mmis:
		instances += (m as MultiMeshInstance3D).multimesh.instance_count
	check(mmis.size() > 50 and instances > mmis.size() * 2, "static models are batched (%d batches, %d instances)" % [mmis.size(), instances])
	var lit := 0
	for l: Dictionary in mission.facility.lights:
		if l.fixture is GeometryInstance3D:
			lit += 1
	check(lit > 50, "light fixtures resolved to switchable meshes (%d)" % lit)
	# the selected inventory item appears in the player's hand
	var p := mission.local_player()
	p.inventory.server_add(&"crowbar", 1)
	var slot := -1
	for i in p.inventory.slots.size():
		if str(p.inventory.slots[i].id) == "crowbar":
			slot = i
	p.inventory.request_select(slot)
	await wait_frames(3)
	eq((p.visual as SkinnedCharacterVisual)._held_id, &"crowbar", "selected item shown in hand")
	mission.queue_free()
	await wait_frames(2)
	Net.leave(false)
