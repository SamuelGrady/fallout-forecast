extends Node
## Autoload "Preload": warms the resource cache while the player sits on the
## title, lobby or join screens, so pressing Play (and the first gunshot,
## enemy or explosion) doesn't stall on a disk/pck read.
##
## Desktop: everything is requested as threaded loads up front.
## Web (single-threaded export): no worker threads, so one resource is loaded
## per frame from a queue, which spreads the cost into tiny hitches on the
## menus instead of one long hang at the start of a run.
##
## Loaded resources are held here so the cache never drops them.

signal finished

const SCENES := [
	"res://main.tscn",
	"res://player/player.tscn",
	"res://enemies/drip/drip.tscn",
	"res://enemies/gutter/gutter.tscn",
	"res://enemies/mister/mister.tscn",
	"res://enemies/boss/boss_cumulus.tscn",
	"res://crates/crate.tscn",
	"res://crates/double_crate.tscn",
	"res://ui/results.tscn",
	"res://ui/lobby.tscn",
	"res://ui/teammate_card.tscn",
]
const DIRS := ["res://weapons", "res://weapons/cursed", "res://assets/audio/sfx", "res://assets/audio/music"]
const EXTENSIONS := ["tres", "wav", "ogg", "tscn"]

var _queue: Array[String] = []
var _pending: Array[String] = []
var _held: Array[Resource] = []
var _web := OS.has_feature("web")
var done := false


func _ready() -> void:
	# The dedicated server loads what it needs on demand; nothing to warm.
	if Net.dedicated or DisplayServer.get_name() == "headless":
		done = true
		return
	# On web every load blocks the only thread, so warm only the small things
	# (sounds, weapon data); big scenes load once, when the run starts.
	if not _web:
		for path in SCENES:
			_queue_path(path)
	for dir in DIRS:
		for path in _list(dir):
			if _web and path.get_extension() == "tscn":
				continue
			_queue_path(path)
	if not _web:
		for path in _queue:
			if ResourceLoader.load_threaded_request(path, "", true) == OK:
				_pending.append(path)
		_queue.clear()


func _queue_path(path: String) -> void:
	if path not in _queue and ResourceLoader.exists(path):
		_queue.append(path)


## Files in a res:// folder, including exported ones (which only list their
## .import / .remap stubs inside the pck).
func _list(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		var name := f.trim_suffix(".import").trim_suffix(".remap")
		if name.get_extension() in EXTENSIONS:
			var path := dir.path_join(name)
			if path not in out:
				out.append(path)
	return out


func _process(_delta: float) -> void:
	if done:
		set_process(false)
		return
	if _web:
		# Never load on the same frame a scene change might happen in a run.
		if GameManager.run_active:
			return
		if not _queue.is_empty():
			var res := load(_queue.pop_front())
			if res:
				_held.append(res)
	else:
		for i in range(_pending.size() - 1, -1, -1):
			var path := _pending[i]
			var status := ResourceLoader.load_threaded_get_status(path)
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				_held.append(ResourceLoader.load_threaded_get(path))
				_pending.remove_at(i)
			elif status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				_pending.remove_at(i)
	if _queue.is_empty() and _pending.is_empty():
		done = true
		finished.emit()


## 0–1, for an optional loading indicator.
func progress() -> float:
	var total := _held.size() + _queue.size() + _pending.size()
	return 1.0 if total == 0 else float(_held.size()) / total
