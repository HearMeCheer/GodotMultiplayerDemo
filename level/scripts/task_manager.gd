extends RefCounted
class_name TaskManager

const TAG: String = "TaskManager"

static var verbose: bool = false

const DEFAULT_PARAMS: Dictionary = {
	"condition" : null,
	"finalizer" : null,
	"name" : "unnamed",
	"delay" : 0,
	"continue_on_fail" : false,
}

# Helpers

static func _logS(message: String):
	if verbose:
		var tid = OS.get_thread_caller_id()
		var time = Time.get_datetime_string_from_system()
		print(TAG + "(" + str(tid) + "): " + time + " " + message)

class SingleTask:
	var subtasks: LinkedList
	var task_condition: Callable
	var task_finalizer: Callable
	var task_cb: Callable
	var context: Dictionary
	var done: bool = false
	var failed: bool = false
	var running: bool = false
	var name: String = ""
	var run_time: int = 0
	var parameters: Dictionary 

	func _init(task: Callable, data: Variant = null, params: Dictionary = {}):
		assert(task is Callable and task.is_valid())
		self.subtasks = LinkedList.new()
		self.parameters = params
		self.parameters.merge(DEFAULT_PARAMS)
		if self.parameters["condition"] is Callable:
			self.task_condition = self.parameters["condition"] as Callable
		if self.parameters["finalizer"] is Callable:
			self.task_finalizer = self.parameters["finalizer"] as Callable
		self.name = self.parameters["name"]
		self.task_cb = task
		self.context = {
			"name" : self.name,
			"data": data, 
			"output": {}, 
			"error": "",
			"subcontexts": []}
		pass

	func add_subtask(task: SingleTask):
		TaskManager._logS(name + " add_task: " + task.name)
		self.subtasks.push_back(task)

	func _check_condition() -> bool:
		if task_condition.is_valid():
			match task_condition.get_argument_count():
				0: return task_condition.call()
				1: return task_condition.call(context)		
				2: return task_condition.call(context, self)
		
		return true

	func _finalize():
		if task_finalizer.is_valid():
			match task_finalizer.get_argument_count():
				0: task_finalizer.call()
				1: task_finalizer.call(self)
				2: task_finalizer.call(self.context, self)

		if failed:
			TaskManager._logS(name + " task failed: " + context["error"])
		else:
			TaskManager._logS(name + " task done")

		pass

	func get_run_time() -> int:
		var delay = self.parameters["delay"]
		if self.run_time == 0 and delay > 0 :
			self.run_time = Time.get_ticks_msec() + delay
		return self.run_time	

	func can_run() -> bool:
		if failed or done:
			return false

		return _check_condition()

	func run():
		if !subtasks.is_empty():
			_run_subtasks()
			return

		if !can_run():
			TaskManager._logS("task" + name + " cannot run")
			set_done()
			return

		self.running = true
		self.task_cb.call(self, self.context["data"])
		pass


	func _run_subtasks():
		var task = self.subtasks.front()
		if !task:
			return
		
		if !task.is_running():
			task.run()

		if task.is_done():
			TaskManager._logS(name + " task done: " + task.name)
			context["subcontexts"].push_back(task.context)
			task._finalize()
			self.subtasks.pop_front()

		if task.is_failed():
			if !self.parameters["continue_on_fail"]:
				self.set_failed(task.error)
			#self.subtasks.clear()

	func is_running() -> bool:
		# if there are subtasks, the task is considered running - we want run() to be called again
		if !subtasks.is_empty():
			return false

		return running

	func set_output(data: Variant):
		self.context["output"] = data

	func set_done():
		done = true

	func set_failed(error_message: String = ""):
		failed = true
		done = true
		context["error"] = error_message

	func is_done() -> bool:
		return done && subtasks.is_empty()

	func is_failed() -> bool:
		return failed

# =================================================================

var tasks: LinkedList

func _init():
	self.tasks = LinkedList.new()
	pass

func add_task(task: SingleTask, after: SingleTask = null):
	if task == null:
		return

	_logS("add_task: " + task.name + " delay: " + str(task.parameters["delay"]))
	task.run_time = 0
	#task.run_time = Time.get_ticks_msec() + task.parameters["delay"]

	if after:
		tasks.insert_after(task, after)
	else:
		tasks.push_back(task)
	pass

var current_task: Variant = null
func update():
	if current_task == null:
		if tasks.is_empty():
			return
		else:
			current_task = tasks.pop_front()
			_logS("starting task: " + current_task.name)
		
	
	if current_task.get_run_time() > Time.get_ticks_msec():
		tasks.push_back(current_task)
		current_task = null
		return

	if !current_task.is_running():
		current_task.run()

	if current_task.is_done():
		current_task._finalize()
		#_logS("task done: " + task.name)
		current_task = null
	
	pass
