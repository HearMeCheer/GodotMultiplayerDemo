extends Tree
class_name HmcTree

var hmc_data: Dictionary = {}
var tree_root: TreeItem

var hidden_properties = ["script"]

func add_item(path: NodePath, value: Variant) -> TreeItem:
	var item = _create_path(path)
	_set_value(path, value)
	return item
	
func get_item(path: String) -> TreeItem:
	return hmc_data.get(path)	

func delete_item(path: String):
	var item : TreeItem = hmc_data.get(path)
	if not item or item == tree_root:
		return

	tree_root.remove_child(item)
	item.free()
	hmc_data.erase(path)
	var all_paths = hmc_data.keys()
	for p in all_paths:
		if p.begins_with(path):
			#var child_item : TreeItem = hmc_data.get(p)
			#child_item.free()
			hmc_data.erase(p)
	pass
	
	
func set_item_callback(path: NodePath, callback: Callable):
	var item : TreeItem = hmc_data.get(path)
	if item:
		item.selected.connect(callback)
	pass

func update_dict(dict: Dictionary, path: String):
	for k in dict.keys():
		var v = dict[k]
		if v is Dictionary:
			self.update_dict(v, path + "/" + k)
		else:
			self.add_item(path + "/" + k, dict[k])

	pass

func update_properties(obj: Object, path: String):
	var props = obj.get_property_list()
	for p in props:
		if p["type"] == Variant.Type.TYPE_NIL:
			continue
			
		var prop_name = p["name"] 
		
		if prop_name in hidden_properties:
			continue
			
		var prop_value = obj.get(prop_name)
		if prop_value:
			if prop_value is Dictionary:
				self.update_dict(prop_value, path + "/" + prop_name)
			else:
				self.add_item(path + ":" + prop_name, prop_value)
	pass

func _find_or_create_node(node_name: String, path: String, parent_node: TreeItem) -> TreeItem:
	var path_item = hmc_data.get(path)
	if not path_item:
		if parent_node:
			path_item = create_item(parent_node)
		else:
			path_item = create_item(tree_root)
			
		path_item.set_text(0, node_name)
		path_item.set_metadata(0, path)

		if parent_node:
			path_item.collapsed = true
		hmc_data[path] = path_item
	return path_item

func _create_path(path: NodePath) -> TreeItem:
	# Split the path into its components
	var path_components = path.get_name_count()
	var parent_node : TreeItem = null
	var current_path : String = ""
	for i in range(path_components):
		var path_component = path.get_name(i)
		current_path += "/" + path_component
		var path_item = _find_or_create_node(path_component, current_path, parent_node)
		parent_node = path_item

	if path.get_subname_count() > 0:
		current_path += ":" + path.get_subname(0)
		var path_item = _find_or_create_node(path.get_subname(0), current_path, parent_node)
		if not path_item:
			print("Failed to create path item for: ", current_path)
	
	return parent_node

func _set_value(path: String, value: Variant):
	var item : TreeItem = hmc_data.get(path)
	if item:
		item.set_text(1, str(value))
	pass

# Called when the node enters the scene tree for the first time.
func _ready():	
	self.hide_root = true
	self.columns = 2
	tree_root = self.create_item()
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
# func _process(delta):
# 	pass

			
