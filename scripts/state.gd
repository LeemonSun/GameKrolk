extends RefCounted

const Catalog=preload("res://scripts/catalog.gd")
const WorldData=preload("res://scripts/world_data.gd")
const Settlement=preload("res://scripts/settlement.gd")
const WorldRules=preload("res://scripts/world_rules.gd")
const Snapshot=preload("res://scripts/combat_snapshot.gd")
const Logistics=preload("res://scripts/logistics.gd")
const Commerce=preload("res://scripts/commerce.gd")
const Personnel=preload("res://scripts/personnel.gd")
const Regional=preload("res://scripts/regional_world.gd")
const SAVE_VERSION=8
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
		"research":{"forestry":false,"mining":false,"agriculture":false},"world":WorldData.generate(20261029)}
	for b in data.buildings:
		b.width=int(catalog.building(b.id).width);b.height=int(catalog.building(b.id).height)
	Settlement.initialize(data,catalog)
	Commerce.initialize(data)
	Personnel.initialize(data)
	Regional.initialize(data)
	data["rules"]={"threat":"standard"}

func new_game(seed_value:int,threat:String,title:String)->bool:
	if seed_value<1 or seed_value>2147483647 or threat not in WorldRules.MODES or title.strip_edges().length()>40:return false
	reset();data.world=WorldData.generate(seed_value);Settlement.initialize(data,catalog)
	Personnel.initialize(data)
	data.erase("regional");Regional.initialize(data)
	data.selected_hero="warden"
	data.rules.threat=threat;data.world.raid_in=WorldRules.MODES[threat].first
	data["profile"]={"name":title.strip_edges() if not title.strip_edges().is_empty() else "Новое поселение","created":Time.get_unix_time_from_system()}
	return true

func _valid(d:Variant)->bool:
	if not d is Dictionary or d.get("version")!=SAVE_VERSION:return false
	for key in ["coins","wood","stone","food","war_rank","wins","losses"]:
		if not d.get(key) is float and not d.get(key) is int:return false
		if not is_finite(float(d[key])) or d[key]<0 or d[key]>10000000 or float(d[key])!=int(d[key]):return false
	if d.war_rank<1:return false
	if d.has("rules"):
		if not d.rules is Dictionary or d.rules.get("threat") not in WorldRules.MODES:return false
	if d.has("profile"):
		if not d.profile is Dictionary or not d.profile.get("name") is String or d.profile.name.length()<1 or d.profile.name.length()>40 or not WorldData.number(d.profile.get("created")) or d.profile.created<0:return false
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
	var combat=d.world.get("combat",{})
	if not combat.is_empty():
		if not combat.has("next_uid"):return false
		if not combat.has("complete") and combat.get("legacy",false)!=true:return false
		for unit in combat.units:
			if not unit.has("uid"):return false
	return Settlement.valid(d,catalog) and Commerce.valid(d) and Personnel.valid(d) and Regional.valid(d)

func load_progress()->bool:
	if not FileAccess.file_exists(save_path) and not FileAccess.file_exists(save_path+".bak"):return true
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
		for key in ["x","y","level","uid","width","height","paid_wood","paid_stone","target_level"]:b[key]=int(b[key])
		if not b.repair.is_empty():
			for key in ["wood","stone"]:b.repair[key]=int(b.repair[key])
	for i in data.world.tiles.size():data.world.tiles[i]=int(data.world.tiles[i])
	for source in data.world.sources:
		for key in ["id","x","y","amount"]:source[key]=int(source[key])
	for worker in data.world.workers:
		for key in ["id","source","carry","workplace","depot"]:worker[key]=int(worker[key])
		for skill in Personnel.SKILLS:worker.skills[skill]=int(worker.skills[skill]);worker.practice[skill]=int(worker.practice[skill])
	for key in ["width","height","seed","raids_defeated","raid_number"]:data.world[key]=int(data.world[key])
	for unit in data.world.get("combat",{}).get("units",[]):
		for key in ["team","rank"]:unit[key]=int(unit[key])
		if unit.has("uid"):unit.uid=int(unit.uid)
	if not data.world.get("combat",{}).is_empty():data.world.combat.next_uid=int(data.world.combat.next_uid)
	if data.world.get("combat",{}).has("complete"):Snapshot.normalize(data.world.combat)
	data.next_building_uid=int(data.next_building_uid)
	for key in ["orders","income","completed"]:data.commerce[key]=int(data.commerce[key])
	for post in Personnel.POSTS:data.personnel.posts[post]=int(data.personnel.posts[post])
	for kind in data.personnel.wounded:data.personnel.wounded[kind]=int(data.personnel.wounded[kind])
	for key in ["treated","lost"]:data.personnel[key]=int(data.personnel[key])
	var map=data.regional
	for key in ["version","generator","seed","size","completed"]:map[key]=int(map[key])
	for i in 2:map.home[i]=int(map.home[i])
	for chunk in map.changes:
		for source in map.changes[chunk]:map.changes[chunk][source]=int(map.changes[chunk][source])
	if not map.expedition.is_empty():
		var expedition=map.expedition
		for i in 2:expedition.destination[i]=int(expedition.destination[i])
		for point in expedition.path:
			for i in 2:point[i]=int(point[i])
		for key in ["index","crew"]:expedition[key]=int(expedition[key])
		for key in ["wood","stone"]:expedition.cargo[key]=int(expedition.cargo[key])
	for key in data.stats:data.stats[key]=int(data.stats[key])

func _migrate(value:Variant)->Variant:
	if not value is Dictionary or value.get("version") not in [1,1.0,2,2.0,3,3.0,4,4.0,5,5.0,6,6.0,7,7.0]:return value
	var migrated=value.duplicate(true)
	if migrated.version==1:
		migrated.wood=migrated.get("wood",migrated.get("materials",180));migrated.erase("materials")
		migrated.stone=100;migrated.world=WorldData.generate(20261029);migrated.research={"forestry":false,"mining":false}
		if migrated.get("buildings") is Array:
			for b in migrated.buildings:
				if b is Dictionary and WorldData.number(b.get("x")) and WorldData.number(b.get("y")):b.x+=12;b.y+=9
	if not migrated.get("buildings") is Array or not migrated.get("world") is Dictionary or not migrated.world.get("workers") is Array or not migrated.get("research") is Dictionary:return null
	if not WorldData.valid(migrated.world):return null
	for b in migrated.buildings:
		if not b is Dictionary or not catalog.data.buildings.has(b.get("id","")) or not WorldData.number(b.get("level")):return null
	migrated.version=SAVE_VERSION;Settlement.initialize(migrated,catalog)
	Commerce.initialize(migrated)
	Personnel.initialize(migrated)
	Regional.initialize(migrated)
	if not migrated.world.get("combat",{}).is_empty() and not migrated.world.combat.has("complete"):migrated.world.combat["legacy"]=true
	return migrated

func save_progress()->bool:
	if read_only:return false
	if before_save.is_valid():before_save.call()
	if not _valid(data):warning="Ошибка состояния: сохранение отменено.";return false
	var temp=save_path+".tmp"
	var f=FileAccess.open(temp,FileAccess.WRITE)
	if f==null:warning="Не удалось записать прогресс.";return false
	f.store_string(JSON.stringify(data,"\t",true,true));f.flush();f.close()
	if not _valid(_read_json(temp)):warning="Проверка записанного сохранения не пройдена. Прежний файл сохранён.";return false
	if FileAccess.file_exists(save_path) and _valid(_migrate(_read_json(save_path))):
		if DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path),ProjectSettings.globalize_path(save_path+".bak"))!=OK:warning="Не удалось обновить резервную копию. Прежнее сохранение не заменено.";return false
	var err=DirAccess.rename_absolute(ProjectSettings.globalize_path(temp),ProjectSettings.globalize_path(save_path))
	if err!=OK:warning="Не удалось заменить файл прогресса.";return false
	return true

func level(id:String)->int:
	var highest=0
	for b in data.buildings:
		if b.id==id and b.built:highest=maxi(highest,int(b.level))
	return highest

func worker_capacity(exclude_uid:int=-1)->int:
	var amount=3
	for b in data.buildings:
		if b.id=="house" and b.built and int(b.uid)!=exclude_uid:amount+=int(b.level)*2
	return mini(24,amount)

func building_at(cell:Vector2i)->int:
	for i in data.buildings.size():
		if Settlement.rect(data.buildings[i]).has_point(cell):return i
	return -1

func building_uid(uid:int)->Dictionary:
	for b in data.buildings:
		if int(b.uid)==uid:return b
	return {}

func capacity()->int:
	var command=Personnel.holder(data,"commander")
	var bonus=2*(int(command.skills.command)-1) if Personnel.ready(data,"commander") else 0
	return 22+level("hq")*4+level("barracks")*6+bonus

func army_count()->int:
	var total=0
	for value in data.army.values():total+=int(value)
	return total

func army_away()->int:return int(data.regional.expedition.get("crew",0))
func army_total()->int:return army_count()+army_away()

func hero_level(id:String)->int:return 1+int(data.xp[id])/60

func hero_available(id:String)->bool:
	return id in ["astreya","warden"] or (id=="lina" and level("lab")>0)

func can_build(id:String,cell:Vector2i)->String:
	if not catalog.data.buildings.has(id):return "Неизвестная постройка."
	var def=catalog.building(id);var area=Rect2i(cell,Vector2i(int(def.width),int(def.height)))
	if cell.x<0 or cell.y<0 or area.end.x>WorldData.WIDTH or area.end.y>WorldData.HEIGHT:return "Здание выходит за границы участка."
	for x in range(area.position.x,area.end.x):
		for y in range(area.position.y,area.end.y):
			if data.world.tiles[y*WorldData.WIDTH+x]==1:return "На воде строить нельзя."
			for source in data.world.sources:
				if source.amount>0 and int(source.x)==x and int(source.y)==y:return "Сначала добудьте ресурс на клетках постройки."
	for b in data.buildings:
		if Settlement.rect(b).intersects(area):return "Место уже занято зданием или стройкой."
		if b.id in ["hq","warehouse"] and area.has_point(Vector2i(int(b.x)+int(b.width)/2,int(b.y+b.height))):return "Оставьте свободным вход в хранилище."
		if id not in ["wall","gate","warehouse","lumber","mine","house","farm"] and b.id==id:return "Такая постройка уже есть. Выберите её для улучшения."
	if def.has("tech") and not data.research.get(def.tech,false):return "Сначала откройте технологию: "+catalog.data.technologies[def.tech].name
	if data.coins<def.coins or data.wood<def.wood or data.stone<def.stone:return "Недостаточно монет, древесины или камня."
	return ""

func build(id:String,cell:Vector2i)->String:
	var reason=can_build(id,cell)
	if not reason.is_empty():return reason
	var def=catalog.building(id)
	data.coins-=int(def.coins);data.wood-=int(def.wood);data.stone-=int(def.stone)
	data.buildings.append({"id":id,"uid":data.next_building_uid,"x":cell.x,"y":cell.y,"level":1,"target_level":1,"width":int(def.width),"height":int(def.height),
		"built":false,"work_done":0.0,"hp":float(def.hp),"paid_wood":int(def.wood),"paid_stone":int(def.stone),"gate_open":false,"repair":{}})
	data.next_building_uid+=1
	save_progress();return "Заложено: "+def.name+". Нужен рабочий-строитель."

func upgrade(index:int)->String:
	if index<0 or index>=data.buildings.size():return "Сначала выберите постройку."
	var b=data.buildings[index];var def=catalog.building(b.id)
	if not b.built or b.target_level>b.level:return "Сначала завершите текущую стройку."
	if not b.repair.is_empty():return "Сначала завершите или отмените ремонт."
	if b.level>=def.max_level:return "Максимальный уровень в этом прототипе."
	var coins=int(def.coins)*int(b.level);var materials=int(def.wood)*int(b.level);var stone=int(def.stone)*int(b.level)
	if data.coins<coins or data.wood<materials or data.stone<stone:return "Недостаточно ресурсов для улучшения."
	data.coins-=coins;data.wood-=materials;data.stone-=stone
	b.target_level=int(b.level)+1;b.work_done=0.0;b.paid_wood+=materials;b.paid_stone+=stone
	save_progress();return "Начато улучшение: %s · уровень %d"%[def.name,b.target_level]

func hire_worker()->String:
	if data.world.workers.size()>=worker_capacity():return "Нет свободного жилья. Постройте или улучшите дом."
	if data.coins<40 or data.food<4:return "Нужно 40 монет и 4 еды."
	var uid=0
	for w in data.world.workers:uid=maxi(uid,int(w.id)+1)
	data.coins-=40;data.food-=4
	data.world.workers.append({"id":uid,"name":Settlement.NAMES[uid%Settlement.NAMES.size()],"x":17.0,"y":14.5,"job":"idle","source":-1,"carry":0,"carry_kind":"wood","progress":0.0,"preference":"auto","workplace":0,"returning":false,"depot":0})
	Personnel.initialize_worker(data.world.workers[-1])
	save_progress();return "Прибыл рабочий: "+data.world.workers[-1].name

func demolish(index:int)->String:
	if index<0 or index>=data.buildings.size():return "Выберите постройку."
	var b=data.buildings[index]
	if b.id=="hq":return "Штаб нельзя снести."
	if b.id=="house" and b.built and worker_capacity(int(b.uid))<data.world.workers.size():return "Сначала обеспечьте рабочих другим жильём."
	data.wood+=int(b.paid_wood)/2;data.stone+=int(b.paid_stone)/2
	var unused=Logistics.refund(b.repair);data.wood+=unused.wood;data.stone+=unused.stone
	data.buildings.remove_at(index);save_progress();return "Постройка убрана. Возвращена половина затраченных древесины и камня."

func research(id:String)->String:
	if not catalog.data.technologies.has(id):return "Неизвестная технология."
	if data.research[id]:return "Технология уже изучена."
	var def=catalog.data.technologies[id]
	if data.coins<def.coins or data.wood<def.wood or data.stone<def.stone:return "Недостаточно ресурсов для изучения."
	data.coins-=int(def.coins);data.wood-=int(def.wood);data.stone-=int(def.stone);data.research[id]=true
	save_progress();return "Изучено: "+def.name

func recruit(id:String)->String:
	if data.world.raid_active:return "Пополнение доступно после нападения."
	if not catalog.data.troops.has(id):return "Неизвестный тип бойца."
	if id=="guard" and level("forge")==0:return "Для щитоносцев нужна кузница."
	if army_total()>=capacity():return "Армия заполнена. Места походного отряда зарезервированы. Улучшите Штаб или Казармы."
	var cost=int(catalog.troop(id).coins)
	if data.coins<cost:return "Недостаточно монет."
	data.coins-=cost;data.army[id]+=1;save_progress();return "Нанят: "+catalog.troop(id).name

func assign(id:String,person_id:int=-1)->String:
	if id not in Personnel.POSTS:return "Неизвестная должность."
	if id=="quartermaster" and level("hq")<2:return "Для второй должности нужен Штаб II."
	if id=="medic" and level("infirmary")==0:return "Для лекаря нужен лазарет."
	var previous=Personnel.holder(data,id)
	if person_id<0 and not previous.is_empty():
		previous.post="";previous.at_post=false;data.personnel.posts[id]=-1
		if id in data.officers:data.officers[id]=false;data["auto_recruit" if id=="commander" else "auto_supply"]=false
		save_progress();return previous.name+" освобождён от должности."
	var person=Personnel.worker(data,person_id)
	if person_id<0:
		for candidate in data.world.workers:
			if candidate.post.is_empty():person=candidate;break
	if person.is_empty():return "Нет доступного человека для назначения."
	if not person.post.is_empty() and person.post!=id:return "Человек уже занимает другую должность."
	if not previous.is_empty():previous.post="";previous.at_post=false
	person.post=id;person.at_post=false;data.personnel.posts[id]=int(person.id)
	if person.carry>0:person.returning=true
	else:person.job="idle";person.workplace=0;person.source=-1;person.progress=0.0
	if id in data.officers:data.officers[id]=true
	save_progress();return person.name+": "+Personnel.POSTS[id]+". Производственную работу больше не выполняет."

func automate()->Dictionary:
	var out={"recruited":0,"food":0,"spent":0}
	if data.world.raid_active:return out
	if Personnel.ready(data,"quartermaster") and data.auto_supply:
		while data.food<12 and data.coins>=4:
			data.food+=1;data.coins-=4;out.food+=1;out.spent+=4
	if Personnel.ready(data,"commander") and data.auto_recruit:
		while data.army.militia<12 and army_total()<capacity() and data.coins>=int(catalog.troop("militia").coins):
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
