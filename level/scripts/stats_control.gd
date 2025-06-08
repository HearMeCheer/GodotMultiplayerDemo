extends VFlowContainer
class_name StatsControl

var labels = {}

func update_stats(key: String, value: Variant):
	var existing:Label = labels.get(key)
	if existing:
		var has_changed = existing.text != str(value)
		if has_changed:
			existing.text = str(value)
	else:		
		var title_label = Label.new()
		var value_label = Label.new()
		var container = HBoxContainer.new()
		title_label.text = key + ":"
		value_label.text = str(value)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.add_child(title_label)
		container.add_child(value_label)
		add_child(container)
		labels[key] = value_label
	pass

# Called when the node enters the scene tree for the first time.
func _ready():
	if OS.has_feature("editor"):
		update_stats("test1", "1.0001")
		update_stats("test2", "2.0")
		update_stats("test3", "3.0")
		update_stats("test4", "4.0")
		update_stats("test5", "5.0")
	
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	pass
