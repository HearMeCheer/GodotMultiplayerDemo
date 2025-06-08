class_name JsonConfigFile

var data: Dictionary = {}
var loaded = false

var TAG: String = "JsonConfigFile"

func _init():
	data = {}
	loaded = false

func _logS(msg: String):
	print(TAG + ": " + msg)

func load(path: String):
	data = {}
	if FileAccess.file_exists(path):
		_logS("loading " + path)
		var save_file = FileAccess.open(path, FileAccess.READ)
		var line = save_file.get_as_text()
		save_file.close()
		var json = JSON.new()
		if line and !line.is_empty():
			var parse_result = json.parse(line)
			if not parse_result == OK:
				_logS("JSON Parse Error: " + json.get_error_message() + " in " + line + " at line " + json.get_error_line())
			_logS(str(json.data))
			data = json.data as Dictionary
		loaded = true
	else:
		print("File not found: " + path)
		loaded = false

func save(path: String):
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_line(JSON.stringify(data))
	file.close()

func from_object(obj: Object):
	self.data = {}
	var prop_list = obj.get_property_list()
	for p in prop_list:
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE == PROPERTY_USAGE_SCRIPT_VARIABLE:
			data[p.name] = obj.get(p.name)

func to_object(obj: Object):
	var prop_list = obj.get_property_list()
	var prop_map = {}
	for p in prop_list:
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE == PROPERTY_USAGE_SCRIPT_VARIABLE:
			prop_map[p.name] = p
		
	for k in data:
		if prop_map.has(k):
			_logS("Setting " + k + " to " + str(data[k]))
			obj.set(k, data[k])
		pass
