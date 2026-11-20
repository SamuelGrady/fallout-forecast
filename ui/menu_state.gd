extends Node
## A stack gives pause and developer menus one owner for time and mouse state.
var stack: Array[Node] = []


func open(menu: Node) -> void:
	if menu in stack:
		return
	if not stack.is_empty():
		stack.back().visible = false
	stack.append(menu)
	menu.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu.focus_default()


func close(menu: Node) -> void:
	if stack.is_empty() or stack.back() != menu:
		return
	stack.pop_back()
	menu.visible = false
	get_tree().paused = not stack.is_empty() or GameManager.global_paused
	if not stack.is_empty():
		stack.back().visible = true
		stack.back().focus_default()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if not stack.is_empty() or GameManager.mutations.stage != "" else Input.MOUSE_MODE_CAPTURED


func reset() -> void:
	stack.clear()
	GameManager.global_paused = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
