extends GameCommon

class_name GameServer

const SERVER_PORT: int = 1370
const MAX_PLAYERS : int = 10

#var event_name: String = ""
var event_id: String = ""

var task_manager: TaskManager = TaskManager.new()

var voice_players: Dictionary = {}
#var player_parts: Dictionary = {} # player id -> participant data
var event_participants: Dictionary = {}
var event_rooms: Dictionary = {}
var voice_data: Dictionary = {
	"1" : {
		"iceUrl" : "",
		"connectionUrl" : "",
		"eventId" : "",
		"participantId" : "",
	}
}

func _initialized():
	self.TAG = "GameServer"
	#self.name = "GameServer"
	_load_config()

	if Error.OK != self.start_host("server", ""):
		push_error("failed to start host!")
		return

	randomize()

	pass

func _load_config():
	# load config file
	var config_file = JsonConfigFile.new()
	config_file.load("user://server.json")
	if config_file.loaded:		
		#options = config_file.data
		_logS("loaded config: " + str(config_file.data))
		config_file.to_object(options)
	else:
		push_error("failed to load config file!")

	config_file.from_object(options)
	config_file.save("user://server.json")
	var user_dir = OS.get_user_data_dir()
	_logS("config saved to: " + user_dir + "/server.json")
	pass

func start_host(nickname: String, skin_color: String) -> int:
	var err = Network.create_server(SERVER_PORT, MAX_PLAYERS)
	if Error.OK != err:
		push_error(TAG + ": failed to create server!")
		return err

	if !nickname:
		nickname = "Player_" + str(multiplayer.get_unique_id())
	if !skin_color:
		skin_color = "blue"

	self.local_player_info["nick"] = nickname
	self.local_player_info["skin"] = skin_color
	
	self.all_players[1] = self.local_player_info

	_logS("hosting at " + Network.SERVER_ADDRESS + ":" + str(SERVER_PORT))
	if options.use_random_event_name:
		_logS("using random event name")
	else:
		_logS("using event: " + options.dev_event_name)

	_on_player_connected(1, self.local_player_info)

	return Error.OK

#region Network handlers
# func _connection_succeeded(peer_id: int):
# 	pass
	
#endregion

#region Player handlers
func _player_added(id: int, player_info : Dictionary):
	_logS("player added: " + str(id) + " " + str(player_info))
	
	if options.enable_voice:
		voice_players[id] = player_info
		start_player_voice(id)
	pass

func _player_removed(id: int, player_info : Dictionary):
	_logS("player removed: " + str(id))
	if options.enable_voice:
		stop_player_voice(id, player_info)
	pass

func start_player_voice(id: int):

	if event_id.is_empty():
		_create_event_task()
	
	if options.enable_player_rooms:
		# create a room for the new player
		add_task(_create_player_room_task(id))
	
	# create a participant for the new player
	add_task(_create_participant_task(id))
	
	if options.enable_player_rooms:
		# join the new room
		add_task(join_player_room_task(id))
		
		# join all rooms
		add_task(_join_all_rooms_task(id))
	
	# send voice data to the player (client)
	add_task(_sync_server_data_task(id))

func stop_player_voice(id: int, player_info : Dictionary):
	var room_id = player_info.get("player_room")
	if room_id:
		add_task(_delete_room_task(room_id))
	#player_parts.erase(id)

	add_task(_remove_voice_player_task(id))

	if voice_players.size() == 1:
		# no players left
		_logS("no players left, deleting event")
		add_task(_delete_all_participants_task())
		add_task(_list_and_delete_all_event_rooms_task())
		if options.delete_empty_event:			
			add_task(_delete_event_task())

#endregion


#region Tasks
func _remove_voice_player_task(player_id: int):
	var task_fn = func (task: TaskManager.SingleTask, _data: Variant):
		voice_players.erase(player_id)
		task.set_done()
		pass

	var main_task = TaskManager.SingleTask.new(task_fn, player_id, {"name": "remove_voice_player_" + str(player_id)})
	return main_task

func _create_event_task():
	var main_task = null
	var event_name = options.dev_event_name
	if options.use_random_event_name:
		var cond = func (): return event_id.is_empty()
		event_name = "game_event_" + str(Time.get_ticks_msec())
		main_task = TaskManager.SingleTask.new(_create_event, event_name, {"condition": cond, "name": "create_event_" + event_name})
	else:
		# check if event already exists
		var cond = func (context: Dictionary): 
			if !event_id.is_empty():
				return false

			var events: Array = context["subcontexts"][0]["output"]
			return !events.any(func (e: Variant): 
				if e is HmcApi.Event:
					var event = e as HmcApi.Event
					if event.name.to_lower() == event_name:
						event_id = event.id
						_logS("_create_event_task: event already exists: " + event_name)
						return true
				_logS("_create_event_task: event not found: " + event_name)
				return false
			)

		main_task = TaskManager.SingleTask.new(_create_event, event_name, 
			{"condition": cond, 
			"name": "create_event_" + event_name})
		
		# add subtask to list events
		var list_event_task = TaskManager.SingleTask.new(_list_events, null, {"name": "list_events"})
		main_task.add_subtask(list_event_task)

	task_manager.add_task(main_task)
	pass

func _delete_event_task() -> TaskManager.SingleTask:
	var cond = func (): return !event_id.is_empty()
	var task = TaskManager.SingleTask.new(_delete_event, null, {"condition": cond})
	task.name = "delete_event_" + event_id
	return task

func _create_player_room_task(player_id: int) -> TaskManager.SingleTask:
	var cond = func (): return !event_id.is_empty()
	var task = TaskManager.SingleTask.new(_create_player_room, player_id, {"condition": cond})
	task.name = "create_room_" + str(player_id)
	return task

func _create_participant_task(player_id: int) -> TaskManager.SingleTask:
	var cond = func (): return !event_id.is_empty()
	var task = TaskManager.SingleTask.new(_create_participant, player_id, {"condition": cond})
	task.name = "create_participant_" + str(player_id)
	return task

func _get_participants_task():
	var cond = func (): return !event_id.is_empty()
	var task = TaskManager.SingleTask.new(_get_participants, null, {"condition": cond})
	task.name = "get_participants"
	task_manager.add_task(task)
	pass

# send voice data to the player after creating a participant
func _sync_server_data_task(player_id: int) -> TaskManager.SingleTask:
	var cond = func (): return !event_id.is_empty()
	var voice_task = func (task: TaskManager.SingleTask, _data):
		var player_voice_data = voice_data.get(player_id)
		if player_voice_data:
			_sync_voice_data.rpc_id(player_id, player_voice_data)
		else:
			_logS("sync_server_data_task: voice data not found for player: " + str(player_id))
		
		task.set_done()
		pass
	var new_task = TaskManager.SingleTask.new(voice_task, player_id, {"condition": cond, "delay": 500})
	new_task.name = "sync_voice_data_" + str(player_id)
	task_manager.add_task(new_task)
	return new_task

# join a new room by old players
func join_player_room_group_task(player_id: int, room_id: String) -> TaskManager.SingleTask:
	var main_task = TaskManager.SingleTask.new(func (task: TaskManager.SingleTask, _data: Variant):
		task.set_done()
		pass, null, {"name": "join_player_room_group_" + str(player_id) + "_" + room_id, "continue_on_fail": true})
	
	for old_player in voice_players.keys():
		if old_player == player_id:
			continue
		var subtask = _join_room_task(old_player, room_id)
		main_task.add_subtask(subtask)

	return main_task

# schedule tasks to join a new room by old players
func join_player_room_task(player_id: int) -> TaskManager.SingleTask:
	var cond = func (): return !event_id.is_empty()

	var task_fn = func (task: TaskManager.SingleTask, _data: Variant):
		var player_info = voice_players[player_id]
		if player_info:
			var room_id = player_info.get("player_room")
			if room_id:
				var subtask = join_player_room_group_task(player_id, room_id)
				task_manager.add_task(subtask)
			else:
				_logS("join_player_room_task: room_id not found for player: " + str(player_id))
		task.set_done()
		pass

	var new_task = TaskManager.SingleTask.new(task_fn, null, {"condition": cond})
	new_task.name = "join_player_room_" + str(player_id)
	return new_task

func _join_room_task(player_id: int, room_id: String) -> TaskManager.SingleTask:
	var cond = func (): 
		var valid_event_id = !event_id.is_empty()
		var valid_participant_id = voice_players[player_id].get("participant_id")
		var can_run = valid_event_id and valid_participant_id
		if !can_run:
			_logS("join_room_task: can't run the task valid_event_id="+str(valid_event_id)+" valid_participant_id=" + valid_participant_id)
		return can_run
	var participant_id = voice_players[player_id].get("participant_id")

	var task_fn = func (task: TaskManager.SingleTask, _data: Variant):
		voice_instance.join_room(event_id, participant_id, room_id, func (result: Variant):
			if result is HmcApi.HmcApiError:
				var err = result as HmcApi.HmcApiError
				push_error("failed to join room: " + err.message)
				task.set_failed(err.message)
			else:
				_logS(str(player_id) + " joined room: " + room_id)
			task.set_done()
			pass
		)

	var new_task = TaskManager.SingleTask.new(task_fn, null, {"condition" : cond})
	new_task.name = "join_room_" + room_id
	return new_task

func _join_all_rooms_task(player_id: int)-> TaskManager.SingleTask:
	var cond = func (): return !event_id.is_empty()
	var new_task = TaskManager.SingleTask.new(_join_all_rooms_task_group, player_id, {"condition": cond})
	new_task.name = "join_all_rooms"
	return new_task

func _join_all_rooms_task_group(task: TaskManager.SingleTask, data: Variant):
	var player_id: int = data
	var main_task_fun = func (main_task: TaskManager.SingleTask, _data: Variant):
		# room data changed, update participants
		_get_participants_task()
		add_task(_set_player_ready_task(player_id, true))
		main_task.set_done()
		pass

	var task_group = TaskManager.SingleTask.new(main_task_fun)
	task_group.name = "join_all_rooms_group"

	for player in voice_players.keys():
		if player == 1:
			continue

		var room_id = voice_players[player].get("player_room")
		if room_id:
			var subtask = _join_room_task(player_id, room_id)
			task_group.add_subtask(subtask)

	task_manager.add_task(task_group)
	task.set_done()

func _set_player_ready_task(player_id: int, player_ready: bool) -> TaskManager.SingleTask:
	var new_task = TaskManager.SingleTask.new(func (task: TaskManager.SingleTask, _data: Variant):
		var player_info = voice_players[player_id]
		if player_info:
			player_info["ready"] = player_ready
			_logS("player " + str(player_id) + " ready: " + str(player_ready))
		task.set_done()
		pass, null, {"name": "set_player_ready_" + str(player_id)}
	)
	new_task.name = "set_player_ready_" + str(player_id)
	return new_task

func _delete_all_participants_task():
	var main_fun = func (task: TaskManager.SingleTask, _data: Variant):		
		task.set_done()
		pass
	var main_task = TaskManager.SingleTask.new(main_fun, null, {"name": "delete_all_participants", "continue_on_fail": true})
	for part_id in event_participants.keys():
		var subtask = TaskManager.SingleTask.new(_delete_participant, {"participant_id": part_id}, {"name": "delete_participant_" + part_id})
		main_task.add_subtask(subtask)
	return main_task

func _delete_all_event_rooms_task(rooms: Array):
	var main_fun = func (task: TaskManager.SingleTask, _data: Variant):
		task.set_done()
		pass

	var main_task = TaskManager.SingleTask.new(main_fun, null, {"name": "delete_all_event_rooms", "continue_on_fail": true})
	for room in rooms:
		if room.id == "audience" or room.id == "main-stage":
			continue
		var subtask = TaskManager.SingleTask.new(_delete_room, room.id, {"name": "delete_room_" + room.id})
		main_task.add_subtask(subtask)
	return main_task

func _list_and_delete_all_event_rooms_task():
	var list_rooms_finalized = func (task_context: Dictionary, task: TaskManager.SingleTask):
		if task.failed:
			return

		var rooms = task_context["output"]
		add_task(_delete_all_event_rooms_task(rooms), task)
		pass

	var list_rooms_task = TaskManager.SingleTask.new(_list_rooms, event_id, {"name": "list_rooms", "finalizer": list_rooms_finalized})

	return list_rooms_task

func _delete_all_players_rooms_task():
	var main_fun = func (task: TaskManager.SingleTask, _data: Variant):
		task.set_done()
		pass
	var main_task = TaskManager.SingleTask.new(main_fun, null, {"name": "delete_all_players_rooms", "continue_on_fail": true})
	for player_id in voice_players.keys():
		if player_id == 1:
			continue

		var room_id = voice_players[player_id].get("player_room")
		if room_id:
			var subtask = TaskManager.SingleTask.new(_delete_room, room_id, {"name": "delete_room_" + room_id})
			main_task.add_subtask(subtask)
	return main_task

func _delete_room_task(room_id: String):
	var cond = func (): return !event_id.is_empty()
	var task = TaskManager.SingleTask.new(_delete_room, room_id, {"condition": cond, "name": "delete_room_" + room_id})
	return task
#endregion

#region Voice handlers
func _list_events(task: TaskManager.SingleTask, _data: Variant):
	voice_instance.list_events(func (result: Variant):
		if result is Array:
			task.set_output(result)
		if result is HmcApi.HmcApiError:
			var err = result as HmcApi.HmcApiError
			push_error("failed to get events: " + err.message)
		task.set_done()
		pass
	)
	pass

func _create_event(task: TaskManager.SingleTask, data: Variant):
	var cb = func (event: Variant):
		if event is HmcApi.Event:
			_logS("event created: " + event.name)
			event_id = event.id
		if event is HmcApi.HmcApiError:
			push_error("failed to create event: " + event.message)
			task.set_failed()
		task.set_done()
		pass
	var event_name = data as String
	voice_instance.create_event(event_name, cb)
	#api_requests.create_event(event_name,

func _delete_event(task: TaskManager.SingleTask, _data: Variant):
	if event_id.is_empty():
		return

	voice_instance.delete_event(event_id, func (result: Variant):
		if result is HmcApi.HmcApiError:
			push_error("failed to delete event: " + result.message)
			task.set_failed()
		else:
			_logS("event deleted: " + event_id)
			event_id = ""
		task.set_done()
		pass
	)
	#event_name = ""
	pass

func _create_player_room(task: TaskManager.SingleTask, data: Variant):
	var player_id: int = data
	var player_info:Dictionary = voice_players[player_id] 
	
	voice_instance.create_room(event_id, "room_" + str(player_id), func (room: Variant):
		if room is HmcApi.Room:
			_logS("room created: " + room.name + "(" + room.id + ")")
			player_info["player_room"] = room.id
			event_rooms[room.id] = room
		if room is HmcApi.HmcApiError:
			push_error("failed to create room: " + room.message)
			task.set_failed(room.message)
		task.set_done()
		pass
	)
	pass

func _list_rooms(task: TaskManager.SingleTask, data: Variant):
	var arg_event_id: String = data
	voice_instance.list_rooms(arg_event_id, func (result: Variant):
		if result is Array:
			var rooms = result as Array
			task.set_output(rooms)
			_logS("rooms: " + str(rooms.size()))
		if result is HmcApi.HmcApiError:
			var err = result as HmcApi.HmcApiError
			push_error("failed to get rooms: " + err.message)
			task.set_failed(err.message)
		task.set_done()
		pass
	)
	pass

func _delete_room(task: TaskManager.SingleTask, data: Variant):
	var room_id: String = data
	voice_instance.delete_room(event_id, room_id, func (result: Variant):
		if result is HmcApi.HmcApiError:
			push_error("failed to delete room: " + result.message)
			task.set_failed(result.message)
		else:
			_logS("room deleted: " + room_id)
			event_rooms.erase(room_id)
		task.set_done()
		pass
	)
	pass

func _create_participant(task: TaskManager.SingleTask, data: Variant):
	var player_id: int = data
	var player_info:Dictionary = voice_players[player_id] 

	voice_instance.create_participant(event_id, player_info["nick"], func (participant: Variant):
		if participant is HmcApi.Participant:
			var part = participant as HmcApi.Participant
			_logS("participant added: " + part.name + "(" + part.id + ") iceUrl: " + part.iceUrl)
			player_info["participant_id"] = part.id
			voice_data[player_id] = {
				"iceUrl" : part.iceUrl,
				"connectionUrl" : part.connectionUrl,
				"participant_id" : part.id,
				"event_id" : event_id,
			}
			
			#player_parts[player_id] = part
			event_participants[part.id] = part
		if participant is HmcApi.HmcApiError:
			var err = participant as HmcApi.HmcApiError
			push_error("failed to add participant: " + err.message)
			task.set_failed(err.message)
		task.set_done()
		pass
	)
	pass

func _get_participants(task: TaskManager.SingleTask, _data: Variant):
	voice_instance.get_participants(event_id, func (result: Variant):
		if result is Array:
			event_participants.clear()
			var parts = result as Array
			for part in parts:
				if part is HmcApi.Participant:
					var p = part as HmcApi.Participant
					event_participants[p.id] = p
					_logS("participant: " + p.name + " rooms: " + str(p.rooms))
			_logS("participants: " + str(event_participants.keys().size()))
		if result is HmcApi.HmcApiError:
			var err = result as HmcApi.HmcApiError
			push_error("failed to get participants: " + err.message)
			task.set_failed(err.message)
		task.set_done()
		pass
	)
	pass

# func _join_room(task: TaskManager.SingleTask, data: Variant):
# 	var participant_id: String = data.get("participant_id")
# 	var room_id: String = data.get("room_id")
# 	var player_id: int = data.get("player_id")
	
# 	voice_instance.join_room(event_id, participant_id, room_id, func (result: Variant):
# 		if result is HmcApi.HmcApiError:
# 			var err = result as HmcApi.HmcApiError
# 			push_error("failed to join room: " + err.message)
# 			task.set_failed(err.message)
# 		else:
# 			_logS(str(player_id) + " joined room: " + room_id)
# 		task.set_done()
# 		pass
# 	)
# 	pass

func _delete_participant(task: TaskManager.SingleTask, data: Variant):
	var part_id: String = data.get("participant_id")
	voice_instance.delete_participant(event_id, part_id, func (result: Variant):
		if result is HmcApi.HmcApiError:
			push_error("failed to delete participant: " + result.message)
			task.set_failed(result.message)
		if result is String:
			_logS("participant deleted: " + result)
			event_participants.erase(part_id)
		task.set_done()
		pass)
	pass

func _upload_participant_data(task: TaskManager.SingleTask, data: Variant):
	var player_id: int = data.get("player_id")
	var player_info = voice_players.get(player_id)
	
	if player_info == null:
		_logS("upload_participant_data: player not found for id: " + str(player_id))
		task.set_failed("upload_participant_data: player not found for id: " + str(player_id))
		return

	var participant_id: String = player_info.get("participant_id")
	var part: HmcApi.Participant = event_participants.get(participant_id)
	if part == null:
		_logS("upload_participant_data: participant not found for id: " + str(participant_id))
		task.set_failed("upload_participant_data: participant not found for id: " + str(participant_id))
		return

	if part.rooms.get(player_info["player_room"]) == null:
		_logS("upload_participant_data: room not found for player: " + str(player_id))
		task.set_failed("upload_participant_data: room not found for player: " + str(player_id))
		return

	if part.rooms.size() < event_rooms.size() + 2:
		_logS("upload_participant_data: not all rooms are joined for player: " + str(player_id) + " part.rooms: " + str(part.rooms.keys()))
		task.set_failed("upload_participant_data: not all rooms are joined for participant: " + str(participant_id))
		return

	_logS("upload_participant_data: participant " + str(participant_id) + " rooms: " + str(part.rooms))
	voice_instance.update_participant_rooms(event_id, part, func (result: Variant):
		if result is HmcApi.HmcApiError:
			var err = result as HmcApi.HmcApiError
			push_error("failed to update participant: " + err.message)
			task.set_failed(err.message)
		task.set_done()
	)
	pass

#endregion

## update all rooms with player positions
func update_participant_position(player_id: int):
	var player_info = voice_players[player_id]
	var player_pos: Vector3 = player_info["position"]
	var part_id = player_info.get("participant_id")
	if part_id == null:
		_logS("update_participant_position("+str(player_id)+"): participant_id not found for player: " + str(player_id))
		return

	var part: HmcApi.Participant = event_participants.get(part_id)
	if part == null:
		_logS("update_participant_position("+str(player_id)+"): participant not found for id: " + str(part_id))
		return

	for id in voice_players.keys():
		if id == player_id or id == 1:
			continue

		var other_player = voice_players[id]

		if other_player["ready"] == false:
			continue

		var room_id = other_player.get("player_room")
		if room_id == null:
			_logS("update_participant_position("+str(player_id)+"): room_id not found for player: " + str(id))
			continue

		var room_data:Dictionary = part.get_room(room_id)
		if room_data.is_empty():
			_logS("update_participant_position("+str(player_id)+"): room data for " + room_id + " not found for participant: " + str(part.name))
			continue

		var room_params: HmcApi.ListenerParameters
		var other_pos: Vector3 = other_player["position"]
		var pos_diff = player_pos - other_pos

		room_params = HmcApi.ListenerParameters.new(0.0, 1.0, pos_diff)
		room_data.merge(room_params.to_dict(), true)

		#_logS("update_player_position("+str(player_id)+"): participant "+ str(id) + " room " + room_id + " " + str(room_data))

	pass

func check_player_position(player_id: int) -> bool:
	if !players_container.has_node(str(player_id)):
		return false
		
	var player = players_container.get_node(str(player_id))
	if !player:
		return false

	var player_info = voice_players[player_id]
	var last_pos = player_info.get("position")
	var current_pos = player.position
	var diff = current_pos - last_pos
	if diff.length() < 0.99:
		return false

	
	player_info["position"] = current_pos
	#_logS("player " + str(player_id) + " position: " + str(current_pos))
	return true

func check_camera_position(player_id: int) -> bool:
	if !voice_players[player_id].has("camera_position_changed"):
		return false

	var changed = voice_players[player_id].get("camera_position_changed")
	voice_players[player_id]["camera_position_changed"] = false
	#_logS("player " + str(player_id) + " camera position changed: " + str(changed))
	return changed

func add_task(task: TaskManager.SingleTask, after: TaskManager.SingleTask = null):
	task_manager.add_task(task, after)

# Called when the node enters the scene tree for the first time.
func _process(_delta):
	task_manager.update()
	pass
