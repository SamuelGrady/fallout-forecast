extends Node
## A stack gives pause and developer menus one owner for time and mouse state.
var stack: Array[Node] = []
var title_played := false


func open(menu: Node) -> void:
	if menu in stack:
		return
	if not stack.is_empty():
		stack.back().visible = false
	stack.append(menu)
	menu.visible = true
	get_tree().paused = true
	TouchInput.release_pointer()
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
	if not stack.is_empty():
		TouchInput.release_pointer()
	else:
		TouchInput.capture_pointer()


func reset() -> void:
	stack.clear()
	GameManager.global_paused = false
	get_tree().paused = false
	TouchInput.release_pointer()
