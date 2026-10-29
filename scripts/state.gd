extends RefCounted

const Catalog=preload("res://scripts/catalog.gd")
const WorldData=preload("res://scripts/world_data.gd")
const SAVE_VERSION=2
var catalog=Catalog.new()
var save_path="user://progress.json"
var data:Dictionary={}
var warning=""
var read_only=false
var before_save=Callable()

func _init(path:String="user://progress.json"):
	save_path=path
	reset()

func reset():
	data={"version":SAVE_VERSION,"coins":320,"wood":180,"stone":100,"food":24,"war_rank":1,"wins":0,"losses":0,
		"selected_hero":"astreya","xp":{"astreya":0,"lina":0,"warden":0},
		"army":{"militia":12,"archer":8,"guard":0},
		"buildings":[{"id":"hq","x":16,"y":11,"level":1},{"id":"barracks","x":14,"y":12,"level":1},{"id":"wall","x":19,"y":12,"level":1}],
		"officers":{"commander":false,"quartermaster":false},"auto_recruit":false,"auto_supply":false,"in_flight":false,
		"research":{"forestry":false,"mining":false},"world":WorldData.generate(20261029)}

func _valid(d:Variant)->bool:
	if not d is Dictionary or d.get("version")!=SAVE_VERSION:return false
	for key in ["coins","wood","stone","food","war_rank","wins","losses"]:
		if not d.get(key) is float and not d.get(key) is int:return false
		if not is_finite(float(d[key])) or d[key]<0 or d[key]>10000000 or float(d[key])!=int(d[key]):return false
	if d.war_rank<1:return false
	if not d.get("army") is Dictionary or not d.get("xp") is Dictionary or not d.get("buildings") is Array or not d.get("officers") is Dictionary:return false
	if d.army.size()!=catalog.data.troops.size() or d.xp.size()!=catalog.data.heroes.size():return false
	if not WorldData.valid(d.get("world")):return false
	if not d.get("research") is Dictionary:return false
	for id in catalog.data.technologies:
		if not d.research.get(id) is bool:return false
	if d.buildings.size()>WorldData.WIDTH*WorldData.HEIGHT:return false
	var seen={}
	for b in d.buildings:
		if not b is Dictionary or not b.get("id","") in catalog.data.buildings:return false
		for key in ["x","y","level"]:
			if not b.get(key) is float and not b.get(key) is int:return false
			if float(b[key])!=int(b[key]):return false
		if b.x<0 or b.x>=WorldData.WIDTH or b.y<0 or b.y>=WorldData.HEIGHT or b.level<1 or b.level>3:return false
		var pos=Vector2i(int(b.x),int(b.y))
		if seen.has(pos):return false
		seen[pos]=true
	for id in catalog.data.troops:
		var count=d.army.get(id)
		if (not count is float and not count is int) or count<0 or count>500 or float(count)!=int(count):return false
	for id in catalog.data.heroes:
		var xp=d.xp.get(id)
		if (not xp is float and not xp is int) or xp<0 or xp>10000000 or float(xp)!=int(xp):return false
	if not d.get("selected_hero","") in catalog.data.heroes:return false
	for key in ["commander","quartermaster"]:
		if not d.officers.get(key) is bool:return false
	for key in ["auto_recruit","auto_supply","in_flight"]:
		if not d.get(key) is bool:return false
	return true

func load_progress()->bool:
	if not FileAccess.file_exists(save_path):return true
	var parsed=_migrate(_read_json(save_path))
	if not _valid(parsed):
		var backup=_migrate(_read_json(save_path+".bak"))
		if _valid(backup):
			data=backup;warning="Основное сохранение повреждено. Загружена резервная копия."
		else:
			read_only=true;warning="Сохранение не удалось прочитать. Запущена временная сессия; старые файлы не перезаписываются."
			return false
	else:data=parsed
	_normalize()
	if data.in_flight:
		data.in_flight=false
		warning="Предыдущий поход был прерван. Потраченный провиант не возвращён; армия сохранена."
	return true

func _read_json(path:String)->Variant:
	if not FileAccess.file_exists(path):return null
	var parser=JSON.new()
	return parser.data if parser.parse(FileAccess.get_file_as_string(path))==OK else null

func _normalize():
	for key in ["version","coins","wood","stone","food","war_rank","wins","losses"]:data[key]=int(data[key])
	for id in data.army:data.army[id]=int(data.army[id])
	for id in data.xp:data.xp[id]=int(data.xp[id])
	for b in data.buildings:
		for key in ["x","y","level"]:b[key]=int(b[key])
	for i in data.world.tiles.size():data.world.tiles[i]=int(data.world.tiles[i])
	for source in data.world.sources:
		for key in ["id","x","y","amount"]:source[key]=int(source[key])
	for worker in data.world.workers:
		for key in ["id","source","carry"]:worker[key]=int(worker[key])
	for key in ["width","height","seed","raids_defeated","raid_number"]:data.world[key]=int(data.world[key])
	for unit in data.world.get("combat",{}).get("units",[]):
		for key in ["team","rank"]:unit[key]=int(unit[key])

func _migrate(value:Variant)->Variant:
	if not value is Dictionary or value.get("version")!=1:return value
	var migrated=value.duplicate(true)
	migrated.version=2;migrated.wood=migrated.get("wood",migrated.get("materials",180));migrated.erase("materials")
	migrated.stone=100;migrated.world=WorldData.generate(20261029);migrated.research={"forestry":false,"mining":false}
	if migrated.get("buildings") is Array:
		for b in migrated.buildings:
			if b is Dictionary and WorldData.number(b.get("x")) and WorldData.number(b.get("y")):
				b.x+=12;b.y+=9
	return migrated

func save_progress()->bool:
	if read_only:return false
	if before_save.is_valid():before_save.call()
	if not _valid(data):warning="Ошибка состояния: сохранение отменено.";return false
	var temp=save_path+".tmp"
	var f=FileAccess.open(temp,FileAccess.WRITE)
	if f==null:warning="Не удалось записать прогресс.";return false
	f.store_string(JSON.stringify(data,"\t"));f.flush();f.close()
	if not _valid(_read_json(temp)):return false
	if FileAccess.file_exists(save_path) and _valid(_migrate(_read_json(save_path))):
		if DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path),ProjectSettings.globalize_path(save_path+".bak"))!=OK:return false
	var err=DirAccess.rename_absolute(ProjectSettings.globalize_path(temp),ProjectSettings.globalize_path(save_path))
	if err!=OK:warning="Не удалось заменить файл прогресса.";return false
	return true

func level(id:String)->int:
	var highest=0
	for b in data.buildings:
		if b.id==id:highest=maxi(highest,int(b.level))
	return highest

func capacity()->int:
	return 22+level("hq")*4+level("barracks")*6

func army_count()->int:
	var total=0
	for value in data.army.values():total+=int(value)
	return total

func hero_level(id:String)->int:return 1+int(data.xp[id])/60

func hero_available(id:String)->bool:
	return id=="astreya" or (id=="lina" and level("lab")>0) or (id=="warden" and level("hq")>=2)

func build(id:String,cell:Vector2i)->String:
	if not catalog.data.buildings.has(id):return "Неизвестная постройка."
	if cell.x<0 or cell.x>=WorldData.WIDTH or cell.y<0 or cell.y>=WorldData.HEIGHT:return "Выберите клетку внутри участка."
	if data.world.tiles[cell.y*WorldData.WIDTH+cell.x]==1:return "На воде строить нельзя."
	for source in data.world.sources:
		if source.amount>0 and int(source.x)==cell.x and int(source.y)==cell.y:return "Сначала добудьте ресурс на этой клетке."
	for b in data.buildings:
		if int(b.x)==cell.x and int(b.y)==cell.y:return "Клетка уже занята."
		if id not in ["wall","lumber","mine"] and b.id==id:return "Такая постройка уже есть. Выберите её для улучшения."
	var def=catalog.building(id)
	if def.has("tech") and not data.research.get(def.tech,false):return "Сначала откройте технологию: "+catalog.data.technologies[def.tech].name
	if data.coins<def.coins or data.wood<def.wood or data.stone<def.stone:return "Недостаточно монет, древесины или камня."
	data.coins-=int(def.coins);data.wood-=int(def.wood);data.stone-=int(def.stone)
	data.buildings.append({"id":id,"x":cell.x,"y":cell.y,"level":1})
	save_progress();return "Построено: "+def.name

func upgrade(index:int)->String:
	if index<0 or index>=data.buildings.size():return "Сначала выберите постройку."
	var b=data.buildings[index];var def=catalog.building(b.id)
	if b.level>=def.max_level:return "Максимальный уровень в этом прототипе."
	var coins=int(def.coins)*int(b.level);var materials=int(def.wood)*int(b.level);var stone=int(def.stone)*int(b.level)
	if data.coins<coins or data.wood<materials or data.stone<stone:return "Недостаточно ресурсов для улучшения."
	data.coins-=coins;data.wood-=materials;data.stone-=stone;b.level+=1
	save_progress();return "Улучшено: %s · уровень %d"%[def.name,b.level]

func research(id:String)->String:
	if not catalog.data.technologies.has(id):return "Неизвестная технология."
	if data.research[id]:return "Технология уже изучена."
	var def=catalog.data.technologies[id]
	if data.coins<def.coins or data.wood<def.wood or data.stone<def.stone:return "Недостаточно ресурсов для изучения."
	data.coins-=int(def.coins);data.wood-=int(def.wood);data.stone-=int(def.stone);data.research[id]=true
	save_progress();return "Изучено: "+def.name

func recruit(id:String)->String:
	if not catalog.data.troops.has(id):return "Неизвестный тип бойца."
	if id=="guard" and level("forge")==0:return "Для стражей нужна кузница."
	if army_count()>=capacity():return "Армия заполнена. Улучшите Штаб или Казармы."
	var cost=int(catalog.troop(id).coins)
	if data.coins<cost:return "Недостаточно монет."
	data.coins-=cost;data.army[id]+=1;save_progress();return "Нанят: "+catalog.troop(id).name

func assign(id:String)->String:
	if id not in data.officers:return "Неизвестная должность."
	if id=="quartermaster" and level("hq")<2:return "Для второй должности нужен Штаб II."
	data.officers[id]=not data.officers[id]
	if not data.officers[id]:data["auto_recruit" if id=="commander" else "auto_supply"]=false
	save_progress();return "Назначение обновлено."

func automate()->Dictionary:
	var out={"recruited":0,"food":0,"spent":0}
	if data.officers.quartermaster and data.auto_supply:
		while data.food<12 and data.coins>=4:
			data.food+=1;data.coins-=4;out.food+=1;out.spent+=4
	if data.officers.commander and data.auto_recruit:
		while data.army.militia<12 and army_count()<capacity() and data.coins>=int(catalog.troop("militia").coins):
			data.army.militia+=1;data.coins-=int(catalog.troop("militia").coins);out.recruited+=1;out.spent+=int(catalog.troop("militia").coins)
	return out

func begin_siege()->String:
	if data.in_flight:return "Поход уже начат."
	if army_count()<1:return "Сначала наймите хотя бы одного бойца."
	if data.food<3:return "Нужно 3 провианта. Купите запас в разделе управления."
	data.food-=3;data.in_flight=true
	if not save_progress():
		data.food+=3;data.in_flight=false;return "Не удалось сохранить начало похода."
	return ""

func finish_siege(won:bool,survivors:Dictionary)->Dictionary:
	if not data.in_flight:return {}
	data.in_flight=false
	for id in catalog.data.troops:data.army[id]=clampi(int(survivors.get(id,0)),0,int(data.army[id]))
	var rank=int(data.war_rank)
	var reward={"coins":130+rank*15 if won else 45,"wood":55+rank*8 if won else 20,"food":6+level("lab") if won else 3,"xp":45 if won else 20}
	for key in ["coins","wood","food"]:data[key]+=reward[key]
	data.xp[data.selected_hero]+=reward.xp
	if won:
		data.wins+=1
		if int(data.wins)%2==0:data.war_rank=mini(10,rank+1)
	else:data.losses+=1
	if army_count()==0:data.army.militia=3;reward["reserves"]=3
	reward["automation"]=automate()
	save_progress();return reward
