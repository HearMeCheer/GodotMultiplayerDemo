class_name HmcApi extends Node

enum ConnectionState {ERROR, NONE, READY, HAND_SHAKE, EVENTS}

var state = ConnectionState.NONE
var request_result = 0
#var request: HTTPRequest

## Address of HMC API site
@export var HMC_API_SITE: String = "https://api.hearmecheer.com"
@export var HMC_API_KEY: String = ""
@export var HMC_PROPERTY_KEY: String = ""

const API_SITE = "https://api.hearmecheer.com"

signal http_error_signal(error: Error, message: String)
#signal hand_shake_complete(message:String)

class HmcApiError:
	var error: int
	var message: String
	func _init(error_code: int, error_message: String):
		self.error = error_code
		self.message = error_message

class Event:
	var id: String
	var name: String
	var description: String
	var defaultRoom: String
	var broadcastRooms: Array
	var allowRaiseHand: bool
	var rtcPlayoutDelayHint: int
	var allowStreaming: bool
	var tagline: String
	var allowAnonymousUsers: bool

class Room:
	var id: String
	var createdAt: String
	var updatedAt: String
	var name: String
	var gain: float
	var isPrivate: bool
	var isParty: bool
	var muffled: bool
	var allowStreaming: bool

class Participant:
	var id: String
	var name: String
	var connectionUrl: String
	var iceUrl: String
	var createdAt: String
	var connectionCount: int
	var primaryRoom: String
	var rooms: Dictionary
	
	func get_room(room_id: String) -> Dictionary:
		if rooms.has(room_id):
			return rooms[room_id]
		return {}

	func get_raw() -> Dictionary:
		return self.get_meta("item")

class GetItemsResponse:
	var result: int
	var response_code: int
	var status: String
	var items: Array


class GetSingleItemResponse:
	var result: int
	var response_code: int
	var status: String
	var item: Variant

@onready var api_requests: HttpApiRequest = $HttpApiRequest

var TAG: String = "HmcApi"

# ============================================================================

func _logS(msg: String):
	print(TAG + ": " + msg)

func get_error_from_result(result: int, response_code: int) -> HmcApiError:
	var err = HmcApiError.new(result, "Request failed with result=" + str(result) + " response_code=" + str(response_code))
	return err

func load_config() -> bool:
	var args = OS.get_cmdline_args()
	var config_path = "user://hmc_settings.json"

	if "--config" in args:
		var index = args.find("--config")
		if index < args.size() - 1:
			_logS("loading configuration from " + str(args[index + 1]))
			config_path = args[index + 1]
	else:
		var user_dir = OS.get_user_data_dir()
		_logS("loading configuration from " + user_dir + "/" + "hmc_settings.json")

	var config_file: JsonConfigFile = JsonConfigFile.new()
	config_file.load(config_path)
	
	HMC_API_SITE = config_file.data.get("site", HMC_API_SITE)
	HMC_PROPERTY_KEY = config_file.data.get("property", HMC_PROPERTY_KEY)
	HMC_API_KEY = config_file.data.get("key", HMC_API_KEY)					

	return config_file.loaded

# Called when the node enters the scene tree for the first time.
func _ready():
	if !load_config():
		_logS("Failed to load configuration.")
			
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	pass

func hand_shake(cb: Callable):
	_logS("hand_shake")
	var response_handler = func handler(body: Dictionary):
		var response: GetSingleItemResponse = GetSingleItemResponse.new()
		
		response.result = body.error
		response.response_code = body.response_code
		if !body.error:
			response.status = body.status
			response.item = body["message"]
		cb.call(response)
		pass
		
	api_requests.process_request(response_handler)

func get_rtc_config(ice_url: String, cb: Callable):
	_logS("get_rtc_config")
	var response_handler = func handler(body: Dictionary):
		var response: GetSingleItemResponse = GetSingleItemResponse.new()
		response.result = body.error
		response.response_code = body.response_code
		if !body.error:
			response.item = body
		cb.call(response)
		pass
		
	api_requests.process_request(
		response_handler, ice_url, 
		{
			"method": HTTPClient.METHOD_POST, 
			"default_headers": false
		})

func send_offer(connection_url: String, offer: String, cb: Callable):
	_logS("send_offer to " + connection_url)
	var response_handler = func handler(body: Dictionary):
		var response: GetSingleItemResponse = GetSingleItemResponse.new()
		response.result = body.error
		response.response_code = body.response_code
		if !body.error:
			var local_desc = body.get("LocalDescription")
			var remote = Marshalls.base64_to_utf8(local_desc)
			#print("remote description: " + remote)
			var json = JSON.parse_string(remote)
			if json:
				response.item = json

		cb.call(response)
		pass
		
	api_requests.process_request(
		response_handler, connection_url, 
		{
			"method": HTTPClient.METHOD_POST, 
			"data": {"LocalDescription": offer},
			"default_headers": false,
			#"debug_log": true
		})

func fill_properties(obj: Object, item: Dictionary):
	var prop_list = obj.get_property_list()
	var prop_map = {}
	for p in prop_list:
		if item.has(p.name):
			prop_map[p.name] = p
		
	for k in item:
		if prop_map.has(k):
			#print("has property "+k)
			obj.set(k, item[k])
	
	obj.set_meta("item", item)
	pass

func store_properties(obj: Object):
	var item:Dictionary = obj.get_meta("item")

	var prop_list = obj.get_property_list()
	var prop_map = {}
	for p in prop_list:
		if item.has(p.name):
			prop_map[p.name] = p
		
	for k in item:
		if prop_map.has(k):
			#print("has property "+k)
			item[k] = obj.get(k)
		pass

func check_hmc_response(response: Variant, body: Dictionary):
	if body.has("status"):
		response.status = body["status"]
	if response.status == "error":
		response.result = FAILED
		if body.has("message"):
			response.status += ": " + body["message"]

#region Events
func get_events(cb: Callable):
	_logS("get_events")
	var response_handler = func handler(body: Dictionary):
		var response: GetItemsResponse = GetItemsResponse.new()
		response.result = body.error
		response.response_code = body.response_code
		if !response.result:
			response.status = body.status
			for item in body.items:
				var event: Event = Event.new()
				fill_properties(event, item)
				response.items.append(event)
		cb.call(response)
		pass
	api_requests.process_request(response_handler, "events")

func create_event(event_name: String, cb: Callable):
	var response_handler = func handler(body: Dictionary):
		var response: GetSingleItemResponse = GetSingleItemResponse.new()
		response.result = body.error
		response.response_code = body.response_code
		check_hmc_response(response, body)
		if !response.result:
			response.status = body.status		
			var event = Event.new()
			fill_properties(event, body.item)
			response.item = event
		cb.call(response)
		pass
		
	var data = {"name": event_name}
	_logS("create_event data=" + JSON.stringify(data))
	api_requests.process_request(response_handler,
		"events",
		{
			"method": HTTPClient.METHOD_POST,
			"data": data
		})

func delete_event(event_id: String, cb: Callable):
	var response_handler = func handler(body: Dictionary):
		var response: GetSingleItemResponse = GetSingleItemResponse.new()
		response.result = body.error
		response.response_code = body.response_code
		cb.call(response)
		pass
		
	api_requests.process_request(response_handler,
		"events/" + event_id,
		{
			"method": HTTPClient.METHOD_DELETE
		})
#endregion	

#region Rooms
func list_rooms(event_id: String, cb: Callable):
	var response_handler = func handler(body: Dictionary):
		var response: GetItemsResponse = GetItemsResponse.new()
		response.result = body.error
		response.response_code = body.response_code
		if !response.result:
			response.status = body.status
			for item in body.items:
				var room: Room = Room.new()
				fill_properties(room, item)
				response.items.append(room)
		cb.call(response)
		pass
	api_requests.process_request(response_handler, "events/" + event_id + "/rooms")

func create_room(event_id: String, room_name: String, cb: Callable):
	var response_handler = func handler(body: Dictionary):
		var response: GetSingleItemResponse = GetSingleItemResponse.new()
		response.result = body.error
		response.response_code = body.response_code
		if !response.result:
			response.status = body.status		
			var room = Room.new()
			fill_properties(room, body.item)
			response.item = room
		cb.call(response)
		pass
		
	var data = {"name": room_name}
	_logS("create_room data=" + JSON.stringify(data))
	api_requests.process_request(response_handler,
		"events/" + event_id + "/rooms",
		{
			"method": HTTPClient.METHOD_POST,
			"data": data
		})

func delete_room(event_id: String, room_id: String, cb: Callable):
	var response_handler = func handler(body: Dictionary):
		var response: GetSingleItemResponse = GetSingleItemResponse.new()
		response.result = body.error
		response.response_code = body.response_code
		cb.call(response)
		pass
		
	api_requests.process_request(response_handler,
		"events/" + event_id + "/rooms/" + room_id,
		{
			"method": HTTPClient.METHOD_DELETE
		})
#endregion

#region Participants
func get_participants(event_id: String, cb: Callable):
	_logS("get_participants")
	var response_handler = func handler(body: Dictionary):
		var response: GetItemsResponse = GetItemsResponse.new()
		response.result = body.error
		response.response_code = body.response_code
		if !response.result:
			response.status = body.status
			for item in body.items:
				var participant: Participant = Participant.new()
				fill_properties(participant, item)
				#print("participant " + participant.id + " iceUrl: " + participant.iceUrl)
				response.items.append(participant)
		cb.call(response)
		pass
	api_requests.process_request(response_handler, "events/" + event_id + "/participants")
	
func create_participant(event_id: String, participant_name: String, cb: Callable):
	var response_handler = func handler(body: Dictionary):
		var response: GetSingleItemResponse = GetSingleItemResponse.new()
		response.result = body.error
		response.response_code = body.response_code
		if !response.result:		
			response.status = body.status			
			var participant = Participant.new()
			fill_properties(participant, body.item)
			response.item = participant
		cb.call(response)
		pass
		
	var data = {"name": participant_name}
	_logS("create_participant data=" + JSON.stringify(data))
	api_requests.process_request(response_handler,
		"events/" + event_id + "/participants",
		{
			"method": HTTPClient.METHOD_POST,
			"data": data
		})

func update_participant(event_id: String, participant: Participant, cb: Callable):
	var response_handler = func handler(body: Dictionary):
		var response: GetSingleItemResponse = GetSingleItemResponse.new()
		response.result = body.error
		response.response_code = body.response_code
		cb.call(response)
		pass
		
	_logS("update_participant")
	var data = participant.get_meta("item")
	var room_data:Dictionary = data.rooms
	room_data.merge(participant.rooms, true)
	api_requests.process_request(response_handler,
		"events/" + event_id + "/participants/" + participant.id,
		{
			"method": HTTPClient.METHOD_PUT,
			"data": data
		})

func update_participant_rooms(event_id: String, participant: Participant, cb: Callable):
	var response_handler = func handler(body: Dictionary):
		var response: GetSingleItemResponse = GetSingleItemResponse.new()
		response.result = body.error
		response.response_code = body.response_code
		cb.call(response)
		pass
		
	_logS("update_participant")
	var data = participant.get_meta("item")
	var room_data:Dictionary = data.rooms
	room_data.merge(participant.rooms, true)

	var new_data = {
		"name" : data.name,
		"rooms": room_data,
		"primaryRoom": data.primaryRoom,
		"partyRoom": data.partyRoom,
		"isHandRaised": data.isHandRaised
	}

	_logS("update_participant_rooms data=" + JSON.stringify(new_data))

	api_requests.process_request(response_handler,
		"events/" + event_id + "/participants/" + participant.id,
		{
			"method": HTTPClient.METHOD_PUT,
			"data": new_data
		})		

func delete_participant(event_id: String, participant_id: String, cb: Callable):
	var response_handler = func handler(body: Dictionary):
		var response: GetSingleItemResponse = GetSingleItemResponse.new()
		response.result = body.error
		response.response_code = body.response_code
		cb.call(response)
		pass
		
	_logS("delete_participant")
	api_requests.process_request(response_handler,
		"events/" + event_id + "/participants/" + participant_id,
		{
			"method": HTTPClient.METHOD_DELETE
		})

# /events/{eventId}/participants/{participantId}/join-room/{roomId}
func join_room(event_id: String, participant_id: String, room_id: String, cb: Callable):
	var response_handler = func handler(body: Dictionary):
		var response: GetSingleItemResponse = GetSingleItemResponse.new()
		response.result = body.error
		response.response_code = body.response_code
		cb.call(response)
		pass
		
	_logS("join_room")
	api_requests.process_request(response_handler,
		"events/" + event_id + "/participants/" + participant_id + "/join-room/" + room_id,
		{
			"method": HTTPClient.METHOD_POST
		})

# /events/{eventId}/participants/{participantId}/leave-room/{roomId}
func leave_room(event_id: String, participant_id: String, room_id: String, cb: Callable):
	var response_handler = func handler(body: Dictionary):
		var response: GetSingleItemResponse = GetSingleItemResponse.new()
		response.result = body.error
		response.response_code = body.response_code
		cb.call(response)
		pass
		
	_logS("leave_room")
	api_requests.process_request(response_handler,
		"events/" + event_id + "/participants/" + participant_id + "/leave-room/" + room_id,
		{
			"method": HTTPClient.METHOD_POST
		})
#endregion
