extends RefCounted

const State=preload("res://scripts/state.gd")
const Rules=preload("res://scripts/world_rules.gd")
var directory:String
var legacy:String
var index_path:String
var error=""

func _init(root_path:String="user://",legacy_path:String="user://progress.json"):
	directory=root_path.path_join("saves");index_path=root_path.path_join("last-session.json");legacy=legacy_path

func paths()->Array:
	var result=[]
	if FileAccess.file_exists(legacy) or FileAccess.file_exists(legacy+".bak"):result.append(legacy)
	var filenames=DirAccess.get_files_at(directory) if DirAccess.dir_exists_absolute(directory) else PackedStringArray()
	for filename in filenames:
		if filename.ends_with(".json.bak"):filename=filename.trim_suffix(".bak")
		if filename.ends_with(".json"):
			var path=directory.path_join(filename)
			if path not in result:result.append(path)
	result.sort_custom(func(a,b):return modified(a)>modified(b))
	return result

func modified(path:String)->int:return FileAccess.get_modified_time(path if FileAccess.file_exists(path) else path+".bak")

func entries()->Array:
	var result=[]
	for path in paths():
		var s=State.new(path);var loaded=s.load_progress()
		var name=s.data.get("profile",{}).get("name","Первое поселение" if path==legacy else path.get_file().get_basename())
		result.append({"path":path,"name":name,"valid":loaded and not s.read_only,"warning":s.warning,"population":s.data.world.workers.size(),"clock":s.data.world.clock,"seed":s.data.world.seed,"mode":Rules.mode(s.data)})
	return result

func last_path()->String:
	var parser=JSON.new();var selected=""
	if FileAccess.file_exists(index_path) and parser.parse(FileAccess.get_file_as_string(index_path))==OK and parser.data is Dictionary:selected=str(parser.data.get("path",""))
	var available=entries()
	for item in available:
		if item.path==selected and item.valid:return selected
	for item in available:
		if item.valid:return item.path
	return legacy

func remember(path:String)->bool:
	if path not in paths():return false
	if DirAccess.make_dir_recursive_absolute(index_path.get_base_dir())!=OK:return false
	var file=FileAccess.open(index_path+".tmp",FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify({"path":path}));file.close()
	return DirAccess.rename_absolute(index_path+".tmp",index_path)==OK

func create(seed_value:int,threat:String,title:String):
	error=""
	if seed_value<1 or seed_value>2147483647 or threat not in Rules.MODES:error="Проверьте зерно карты и уровень угрозы.";return null
	if title.strip_edges().length()>40:error="Название поселения должно быть не длиннее 40 символов.";return null
	if DirAccess.make_dir_recursive_absolute(directory)!=OK:error="Не удалось создать папку сохранений.";return null
	var path=""
	for attempt in 100:
		var filename="world-%d-%d.json"%[int(Time.get_unix_time_from_system()),randi_range(1,2147483647)]
		path=directory.path_join(filename)
		if not FileAccess.file_exists(path) and not FileAccess.file_exists(path+".bak"):break
		path=""
	if path.is_empty():error="Не удалось выбрать имя файла сохранения.";return null
	var s=State.new(path)
	if not s.new_game(seed_value,threat,title) or not s.save_progress():error=s.warning if not s.warning.is_empty() else "Не удалось сохранить новую партию.";return null
	return s
