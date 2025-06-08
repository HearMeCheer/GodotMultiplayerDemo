extends Panel
class_name HmcPanel

var hmc_tree : HmcTree
var action_containers : Dictionary = {}
var voice: Voice

func set_voice_controller(vc: Voice):
	voice = vc

func update_events(events: Array):
	var events_path = "/events"
	hmc_tree.delete_item(events_path)
	
	for e:HmcApi.Event in events:
		hmc_tree.update_properties(e, "/events/" + e.id)
	pass

func update_participants(event_id: String, items: Array):
	var participants_path = "/events/"+event_id+"/participants"
	hmc_tree.delete_item(participants_path)

	for participant:HmcApi.Participant in items:
		var part_name = participant.name if participant.name else participant.id
		var node_path = participants_path + "/" + part_name
		hmc_tree.update_properties(participant, node_path)

		var part_item: TreeItem = hmc_tree.get_item(node_path)
		assert(part_item)
		part_item.set_meta("part_id", participant.id)
	pass

func update_rooms(event_id: String, items: Array):
	var rooms_path = "/events/"+event_id+"/rooms"
	hmc_tree.delete_item(rooms_path)
	for room:HmcApi.Room in items:
		var node_path = rooms_path + "/" + room.name
		hmc_tree.update_properties(room, node_path)		

		var room_item: TreeItem = hmc_tree.get_item(node_path)
		assert(room_item)
		room_item.set_meta("room_id", room.id)
	pass

func _find_room_id(info: Dictionary, path: NodePath) -> String:
	var room_item = hmc_tree.get_item("/" + path.get_concatenated_names())
	var room_id = room_item.get_meta("room_id")
	if room_id:
		info["room_id"] = room_id
	return room_id

func _find_participant_id(info: Dictionary, path: NodePath) -> String:
	var part_item = hmc_tree.get_item("/" + path.get_concatenated_names())
	var part_id = part_item.get_meta("part_id")
	if part_id:
		info["part_id"] = part_id
	return part_id

func _get_selected_item_info() -> Dictionary:
	var item: TreeItem = hmc_tree.get_selected()
	if not item:
		return {}
	var path:NodePath = item.get_metadata(0)
	if not path:
		return {}

	var info = {}		
	for n in range(path.get_name_count()):
		var curName = path.get_name(n)
		match n:
			1:
				match path.get_name(0):
					"events":
						info["event_id"] = curName
			3:
				match path.get_name(2):
					"rooms":
						_find_room_id(info, path)
							
					"participants":
						_find_participant_id(info, path)

	return info

func _list_event():
	var response_handler = func handler(result: Variant):
		if result is Array:
			update_events(result as Array)
			for e:HmcApi.Event in result:
				_get_participants(e.id)
				#_get_rooms(e.id)
		pass
	voice.list_events(response_handler)
pass

func _list_participants():
	var info: Dictionary = _get_selected_item_info()
	var event_id = info["event_id"]

	if event_id:
		_get_participants(event_id)

func _get_participants(event_id: String):
	var response_handler = func handler(result: Variant):
		if result is Array:
			update_participants(event_id, result as Array)
		pass
	voice.get_participants(event_id, response_handler)

func _delete_participant():
	var info: Dictionary = _get_selected_item_info()
	var event_id = info["event_id"]
	var part_id = info["part_id"]

	if not event_id or not part_id:
		return

	var cb = func(_result: Variant):
		_get_participants(event_id)
		pass
	voice.delete_participant(event_id, part_id, cb)

func _list_rooms_pressed():
	var info: Dictionary = _get_selected_item_info()
	var event_id = info["event_id"]
	if not event_id:
		return

	_list_rooms(event_id)

func _list_rooms(event_id: String):
	var response_handler = func handler(result: Variant):
		if result is Array:
			update_rooms(event_id, result as Array)
		pass

	voice.list_rooms(event_id, response_handler)


func _add_room():
	var info: Dictionary = _get_selected_item_info()
	var event_id = info["event_id"]
	if not event_id:
		return

	var cb = func(_room: HmcApi.Room):
		_list_rooms(event_id)
		pass

	voice.create_room(event_id, "new room", cb)

func _delete_room():
	var info: Dictionary = _get_selected_item_info()
	var event_id = info.get("event_id")
	var room_id = info.get("room_id")

	if not event_id or not room_id:
		return

	var cb = func():
		_list_rooms(event_id)
		pass

	voice.delete_room(event_id, room_id, cb)

func _hide_actions():
	for k in action_containers.values():
		k.hide()
	pass

# Called when the node enters the scene tree for the first time.
func _ready():	
	var main_container = HBoxContainer.new()
	main_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	self.add_child(main_container)
	hmc_tree = HmcTree.new()
	hmc_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hmc_tree.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	main_container.add_child(hmc_tree)

	hmc_tree.item_selected.connect(_on_item_selected)
	hmc_tree.nothing_selected.connect(_on_nothing_selected)

	var action_container = VBoxContainer.new()
	main_container.add_child(action_container)

	# event buttons
	var event_buttons = VBoxContainer.new()
	event_buttons.visible = true
	action_containers["events"] = event_buttons
	action_container.add_child(event_buttons)
	var event_list_button = Button.new()
	event_list_button.text = "List events"
	event_list_button.pressed.connect(_list_event)
	event_buttons.add_child(event_list_button)

	# room buttons
	var room_buttons = VBoxContainer.new()
	room_buttons.visible = false
	action_containers["rooms"] = room_buttons
	action_container.add_child(room_buttons)

	var room_list_button = Button.new()
	room_list_button.text = "List rooms"
	room_list_button.pressed.connect(_list_rooms_pressed)
	room_buttons.add_child(room_list_button)

	var room_create_button = Button.new()
	room_create_button.text = "Create room"
	room_create_button.pressed.connect(_add_room)
	room_buttons.add_child(room_create_button)

	var room_delete_button = Button.new()
	room_delete_button.text = "Delete room"
	room_delete_button.pressed.connect(_delete_room)
	room_buttons.add_child(room_delete_button)

	# participants
	var participant_buttons = VBoxContainer.new()
	participant_buttons.visible = false
	action_containers["participants"] = participant_buttons
	action_container.add_child(participant_buttons)
	
	var participant_list_button = Button.new()
	participant_list_button.text = "List participants"
	participant_list_button.pressed.connect(_list_participants)
	participant_buttons.add_child(participant_list_button)

	var participant_delete_button = Button.new()
	participant_delete_button.text = "Delete participant"
	participant_delete_button.pressed.connect(_delete_participant)
	participant_buttons.add_child(participant_delete_button)

	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
# func _process(delta):
# 	pass

func _on_nothing_selected():
	print("nothing selected")
	_hide_actions()
	pass

func _on_item_selected():
	var item: TreeItem = hmc_tree.get_selected()
	print("item selected: %s path: %s"%[item.get_text(0), item.get_metadata(0)])
	var path = item.get_metadata(0)

	if not path or path == "":
		return

	_hide_actions()

	var parts = path.split("/")
	action_containers["events"].show()
	if parts.size() > 3:
		match parts[3]:
			"participants":
				action_containers["participants"].show()
			"rooms":
				action_containers["rooms"].show()
		
	pass
			
