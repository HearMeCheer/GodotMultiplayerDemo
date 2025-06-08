class_name CircularBuffer

var _buffer: PackedVector2Array
var _capacity: int
var _head: int = 0
var _tail: int = 0
var _size: int = 0
var _guard: Mutex = Mutex.new()

var capacity: int:
	get:
		return _capacity

func _init(buffer_capacity: int):
	self._capacity = buffer_capacity
	_buffer = PackedVector2Array()
	_buffer.resize(buffer_capacity)

func is_full() -> bool:
	return _size == _capacity

func is_empty() -> bool:
	return _size == 0

func size() -> int:
	return _size

func write(data: float):
	write_vector2(Vector2(data, data))

func write_vector2(data: Vector2):
	_guard.lock()
	_buffer[_tail] = data
	_tail = (_tail + 1) % _capacity
	if is_full():
		_head = (_head + 1) % _capacity
	else:
		_size += 1
	_guard.unlock()

func write_vector2_array(data: PackedVector2Array):
	for x in data:
		write_vector2(x)

func read() -> float:
	return read_vector2().x

func read_vector2() -> Vector2:
	if is_empty():
		return Vector2(0, 0)
	_guard.lock()
	var data = _buffer[_head]
	_head = (_head + 1) % _capacity
	_size -= 1
	_guard.unlock()
	return data

func peek(index: int) -> float:
	return peek_vector2(index).x

func peek_vector2(index: int) -> Vector2:
	if is_empty() or index>_size:
		return Vector2(0, 0)
	var abs_index = (_head+index)%_size
	return _buffer[abs_index]

func clear():
	_guard.lock()
	_head = 0
	_tail = 0
	_size = 0
	_guard.unlock()
