extends RefCounted
class_name LinkedList

## List node
class LinkedListNode:
	var item: Variant
	var next: LinkedListNode

	func _init():
		self.item = null
		self.next = null

# =================================================================

var head: LinkedListNode
var tail: LinkedListNode

func _init():
	self.head = null
	self.tail = null

func is_empty() -> bool:
	return !self.head

func clear():
	self.head = null
	self.tail = null

func push_back(item: Variant):
	var node = LinkedListNode.new()
	node.item = item

	if !self.head:
		self.head = node
		self.tail = node
	else:
		self.tail.next = node
		self.tail = node
	pass

func insert_after(item: Variant, after: Variant):
	var node = LinkedListNode.new()
	node.item = item

	var current = self.head
	while current:
		if current.item == after:
			node.next = current.next
			current.next = node
			if current == self.tail:
				self.tail = node
			break
		current = current.next
	pass

func pop_front() -> Variant:
	if !self.head:
		return null
	
	var old_head = self.head
	self.head = old_head.next
	old_head.next = null
	if old_head == self.tail:
		self.tail = null

	var item = old_head.item

	return item

func front() -> Variant:
	if !self.head:
		return null
	return self.head.item

func erase(item: Variant):
	var prev: LinkedListNode = null
	var node = self.head
	while node:
		if node.item == item:
			if prev:
				prev.next = node.next
			else:
				self.head = node.next
			if self.tail == node:
				self.tail = prev
			break
		prev = node
		node = node.next
	pass
