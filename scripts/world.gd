extends RefCounted

signal notice(text:String)
signal raid_finished(won:bool)
signal settlement_changed
const Settlement=preload("res://scripts/settlement.gd")
var work_status={}
var worker_moving={}
var site_targets={}
var chase_clock=0.0
var search_after={}
const Battle=preload("res://scripts/battle.gd")
const WorldData=preload("res://scripts/world_data.gd")
const WorldRules=preload("res://scripts/world_rules.gd")
const Snapshot=preload("res://scripts/combat_snapshot.gd")
const Logistics=preload("res://scripts/logistics.gd")
const Commerce=preload("res://scripts/commerce.gd")
const Personnel=preload("res://scripts/personnel.gd")
const Regional=preload("res://scripts/regional_world.gd")
var regional
var command_mode="advance"
var navigation_signature=0
var state
var battle=Battle.new()
var navigation=AStarGrid2D.new()
var paused=false
var accumulator=0.0
var paths={}
var destinations={}
var job_timer=0.0
var raid_time=0.0
var hero_type=""
var synced={}

func _init(game_state):
	state=game_state
	regional=Regional.new(state)
	rebuild_navigation()
	_initialize_battle()
	var complete=_restore_combat()
	if not complete:
		_relocate_blocked()
		if not state.data.world.raid_active:sync_army()
		_assign_jobs()
	state.before_save=flush

func home()->Vector2:
	for b in state.data.buildings:
		if b.id=="hq":return Vector2(float(b.x)+floorf(float(b.width)*0.5)+0.5,float(b.y+b.height)+0.5)*WorldData.TILE
	return Vector2(544,432)

func maximum_keep()->float:
	return 300+state.level("hq")*80

func _initialize_battle():
	battle.start({"mode":"world","seed":state.data.world.seed,"hero":state.data.selected_hero,"hero_level":state.hero_level(state.data.selected_hero),"army":{"militia":0,"archer":0,"guard":0},"enemies":0,
		"size":Vector2(WorldData.WIDTH,WorldData.HEIGHT)*WorldData.TILE,"keep_position":home(),"keep_hp":maximum_keep(),"forge":state.level("forge")})
	battle.units[0].pos=home()+Vector2(-35,40);battle.units[0].prev=battle.units[0].pos
	battle.walkable=_walkable;battle.line_clear=_line_clear;hero_type=state.data.selected_hero
	sync_army()

func rebuild_navigation():
	navigation.region=Rect2i(0,0,WorldData.WIDTH,WorldData.HEIGHT)
	navigation.cell_size=Vector2.ONE;navigation.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES;navigation.update()
	for y in WorldData.HEIGHT:
		for x in WorldData.WIDTH:navigation.set_point_solid(Vector2i(x,y),state.data.world.tiles[y*WorldData.WIDTH+x]==1)
	for b in state.data.buildings:
		if not Logistics.solid(b):continue
		for x in range(int(b.x),int(b.x+b.width)):
			for y in range(int(b.y),int(b.y+b.height)):navigation.set_point_solid(Vector2i(x,y),true)
	paths.clear();destinations.clear();site_targets.clear();search_after.clear()
	if state.data.world.raid_active:
		for u in battle.units:
			if u.team==1 and u.hp>0:_route_unit(u,home())
	for u in battle.units:
		if u.team==0 and u.hp>0 and u.goal!=Vector2.INF:_route_unit(u,u.goal,u.get("route_kind","order"))
	navigation_signature=_navigation_signature()

func _navigation_signature()->int:
	var sites=[]
	for building in state.data.buildings:sites.append([building.uid,building.x,building.y,building.width,building.height,Logistics.solid(building)])
	return hash([state.data.world.tiles,sites])

func _walkable(pos:Vector2)->bool:
	var cell=Vector2i(floori(pos.x/WorldData.TILE),floori(pos.y/WorldData.TILE))
	return navigation.region.has_point(cell) and not navigation.is_point_solid(cell)

func occupied(cell:Vector2i)->bool:
	for u in battle.units:
		if u.hp>0 and Vector2i(floori(u.pos.x/WorldData.TILE),floori(u.pos.y/WorldData.TILE))==cell:return true
	for w in state.data.world.workers:
		if Vector2i(floori(w.x),floori(w.y))==cell:return true
	return false

func _route(start:Vector2,end:Vector2)->Array:
	var a=Vector2i(floori(start.x),floori(start.y));var b=Vector2i(floori(end.x),floori(end.y))
	if not navigation.region.has_point(a) or not navigation.region.has_point(b):return []
	if navigation.is_point_solid(a) or navigation.is_point_solid(b):return []
	var result=[]
	for p in navigation.get_id_path(a,b):result.append(Vector2(p)+Vector2.ONE*0.5)
	return result

func _route_unit(u:Dictionary,destination:Vector2,kind:String="order")->bool:
	u["route_kind"]=kind
	destination=_nearest_open(destination)
	var route=_route(u.pos/WorldData.TILE,destination/WorldData.TILE)
	if route.is_empty() and u.team==1:
		var a=Vector2i(u.pos/WorldData.TILE);var b=Vector2i(destination/WorldData.TILE)
		if navigation.region.has_point(a) and navigation.region.has_point(b) and not navigation.is_point_solid(a) and not navigation.is_point_solid(b):
			for p in navigation.get_id_path(a,b,true):route.append(Vector2(p)+Vector2.ONE*0.5)
	u.path=[]
	for p in route:u.path.append(p*WorldData.TILE)
	u.route_blocked=route.is_empty()
	if route.is_empty():u.goal=destination;u.goal_until=battle.time+3600.0;return false
	if u.team==1:destination=route[-1]*WorldData.TILE
	if u.path[-1].distance_to(destination)>1:u.path.append(destination)
	u.goal=destination;u.goal_until=battle.time+3600.0;return true

func order(group:String,pos:Vector2):
	if not _walkable(pos):notice.emit("Точка недоступна: вода или укрепление.");return
	battle.order(group,pos,command_mode)
	var accepted=0;var blocked=0
	for u in battle.units:
		if u.team==0 and u.hp>0 and (group=="all" or u.kind==group):
			if _route_unit(u,u.goal):accepted+=1
			else:blocked+=1
	if blocked>0:notice.emit("Приказ получили %d; нет пути для %d бойцов."%[accepted,blocked])

func stop(group:String,hold:bool=false):
	battle.stop(group,hold);notice.emit("Удерживать позицию." if hold else "Маршрут отменён; свободная оборона.")

func sync_army():
	var hero=battle.units[0];var def=state.catalog.hero(state.data.selected_hero)
	var hero_level=state.hero_level(state.data.selected_hero)
	var maximum=float(def.hp)*(1.0+0.08*(hero_level-1))
	if hero_type!=state.data.selected_hero:
		hero.hp=maximum;hero_type=state.data.selected_hero;battle.hero_kind=hero_type;battle.traces.clear();battle.hero_cooldown=0.0
	elif maximum>hero.max_hp:hero.hp+=maximum-hero.max_hp
	hero.max_hp=maximum
	hero.damage=float(def.damage)*(1.0+0.07*(hero_level-1))*(1.0+state.level("forge")*0.07)
	for key in ["speed","reach","cooldown"]:hero[key]=float(def[key])
	battle.forge=state.level("forge")
	for kind in state.catalog.data.troops:
		var count=0
		for u in battle.units:
			if u.team==0 and u.kind==kind and u.hp>0:count+=1
		if count>int(state.data.army[kind]):
			for u in battle.units:
				if count<=int(state.data.army[kind]):break
				if u.team==0 and u.kind==kind and u.hp>0:u.hp=0;u.died=battle.time;count-=1
		for i in maxi(0,int(state.data.army[kind])-count):
			var slot=maxi(0,battle.alive(0)-1)
			var pos=home()+Vector2(-130+(slot%5)*20,30+(slot/5)*20)
			battle._add_unit(kind,0,_unit_spawn(pos),state.catalog.troop(kind))
		for u in battle.units:
			if u.team==0 and u.kind==kind:u.damage=float(state.catalog.troop(kind).damage)*(1.0+battle.forge*0.07)
	var previous_max=battle.keep_max
	battle.keep_max=maximum_keep();battle.keep_position=home()
	if battle.keep_max>previous_max:battle.keep_hp+=battle.keep_max-previous_max
	battle.keep_hp=minf(battle.keep_hp,battle.keep_max)

func source_at(cell:Vector2i)->Dictionary:
	for s in state.data.world.sources:
		if s.amount>0 and int(s.x)==cell.x and int(s.y)==cell.y:return s
	return {}

func _source(id:int)->Dictionary:
	for source in state.data.world.sources:
		if int(source.id)==id:return source
	return {}

func gather(id:int,worker_id:int=-1)->String:
	var source=_source(id)
	if source.is_empty() or source.amount<=0:return "Источник уже исчерпан."
	for w in state.data.world.workers:
		if worker_id>=0 and int(w.id)!=worker_id:continue
		if worker_id>=0 and (w.carry>0 or not w.post.is_empty()):return "Выбранный человек несёт груз или занимает должность. Сначала завершите доставку или освободите должность."
		if (w.job=="idle" or worker_id>=0) and w.carry==0 and (w.preference!="rest" or worker_id>=0) and w.post.is_empty():
			if _route(Vector2(w.x,w.y),Vector2(source.x+0.5,source.y+0.5)).is_empty():continue
			_release(w);w.job="manual";w.source=id;w.workplace=0;w.progress=0.0;w.depot=0;w.returning=false
			if worker_id>=0 and w.preference=="rest":w.preference="auto"
			paths.erase(int(w.id));state.save_progress()
			return w.name+" будет добывать выбранный источник до исчерпания и носить груз в Штаб."
	return "Нет свободного рабочего с доступным маршрутом. Измените назначения во вкладке «Люди»."

func _assign_jobs():
	var jobs=[];var production=[]
	for b in state.data.buildings:
		if needs_work(b):jobs.append({"kind":"build","uid":int(b.uid)})
		if b.built and b.id in ["lumber","mine","farm"]:
			production.append({"kind":{"lumber":"wood","mine":"stone","farm":"farm"}[b.id],"uid":int(b.uid)})
	jobs=jobs+production if state.data.construction_first else production+jobs
	var assigned={}
	for w in state.data.world.workers:
		if not w.post.is_empty():
			if w.job!="idle":_release(w)
			continue
		if w.returning or w.job=="manual":continue
		if w.job!="idle":
			var key=w.job+":"+str(int(w.workplace))
			var exists=false
			for j in jobs:
				if j.kind==w.job and j.uid==int(w.workplace):exists=true;break
			if not exists or assigned.has(key) or w.preference=="rest" or (w.preference!="auto" and w.preference!=w.job):_release(w)
			else:assigned[key]=true
	for j in jobs:
		var key=j.kind+":"+str(j.uid)
		if assigned.has(key):continue
		var candidate={}
		for preferred in [j.kind,"auto"]:
			for w in state.data.world.workers:
				if w.job=="idle" and w.carry==0 and w.preference==preferred and w.post.is_empty():
					candidate=w;break
			if not candidate.is_empty():break
		if candidate.is_empty():
			if j.kind=="build" and state.data.construction_first:
				for w in state.data.world.workers:
					if w.preference=="auto" and w.post.is_empty() and w.job in ["wood","stone","farm"] and not w.returning:
						_release(w);break
			continue
		candidate.job=j.kind;candidate.workplace=j.uid;candidate.source=-1;candidate.progress=0.0;paths.erase(int(candidate.id));assigned[key]=true

func _find_source(w:Dictionary)->Dictionary:
	var workplace=state.building_uid(int(w.workplace))
	if workplace.is_empty():return {}
	var closest={};var distance=INF
	for source in state.data.world.sources:
		if source.amount<=0 or source.kind!=w.job:continue
		if Vector2(workplace.x,workplace.y).distance_to(Vector2(source.x,source.y))>8:continue
		var d=Vector2(w.x,w.y).distance_squared_to(Vector2(source.x+0.5,source.y+0.5))
		if d<distance and not _route(Vector2(w.x,w.y),Vector2(source.x+0.5,source.y+0.5)).is_empty():distance=d;closest=source
	return closest

func _travel(w:Dictionary,target:Vector2,dt:float)->bool:
	var pos=Vector2(w.x,w.y);var id=int(w.id)
	if pos.distance_to(target)<0.08:return true
	if destinations.get(id,Vector2.INF)!=target or not paths.has(id):
		paths[id]=_route(pos,target);destinations[id]=target
	if paths[id].is_empty():work_status[id]="Нет пути";return false
	var next:Vector2=paths[id][0]
	pos=pos.move_toward(next,dt*2.5)
	if pos.distance_to(next)<0.03:paths[id].pop_front()
	w.x=pos.x;w.y=pos.y
	return pos.distance_to(target)<0.08

func _work(w:Dictionary,dt:float):
	if not w.post.is_empty() and w.carry==0:
		var station={}
		for building in state.data.buildings:
			if building.built and building.id==("infirmary" if w.post=="medic" else "hq"):station=building;break
		w.at_post=false
		if station.is_empty():work_status[int(w.id)]="Нет здания для службы";return
		var point=_site_target(w,station)
		if point==Vector2.INF:work_status[int(w.id)]="Нет пути к месту службы";return
		w.at_post=_travel(w,point,dt)
		work_status[int(w.id)]=Personnel.POSTS[w.post]+(" · на месте службы" if w.at_post else " · идёт к месту службы");return
	work_status[int(w.id)]={"idle":"Отдыхает" if w.preference=="rest" else "Ждёт задания","manual":"Добывает выбранный ресурс","wood":"Заготовка древесины","stone":"Добыча камня","farm":"Выращивает еду","build":"Строит"}[w.job]
	var source=_source(int(w.source))
	if w.returning or w.carry>=5 or (w.carry>0 and (Logistics.room(state.data,w.carry_kind)==0 or (w.job in ["wood","stone","manual"] and (source.is_empty() or source.amount<=0)))):
		var free=Logistics.room(state.data,w.carry_kind)
		if free==0:work_status[int(w.id)]="Хранилища заполнены; груз %d сохранён"%w.carry;return
		var target=_delivery_target(w)
		if target==Vector2.INF:work_status[int(w.id)]="Нет пути к хранилищу; груз сохранён";return
		work_status[int(w.id)]="Несёт %d %s в %s"%[w.carry,{"wood":"дерева","stone":"камня","food":"еды"}[w.carry_kind],"Штаб" if state.building_uid(int(w.depot)).get("id")=="hq" else "склад"]
		if _travel(w,target,dt):
			var amount=mini(int(w.carry),free)
			state.data[w.carry_kind]+=amount;state.data.stats[w.carry_kind+"_delivered"]+=amount;w.carry-=amount;paths.erase(int(w.id))
			Personnel.practice(w,"farm" if w.carry_kind=="food" else w.carry_kind,amount)
			if w.carry>0:w.returning=true;return
			w.depot=0;site_targets.erase(int(w.id))
			if w.returning or (w.job=="manual" and (source.is_empty() or source.amount<=0)):
				w.returning=false;w.job="idle";w.workplace=0;w.source=-1;w.progress=0.0
		return
	if w.job=="idle":return
	var skill="wood" if w.job=="manual" and source.get("kind")=="wood" else ("stone" if w.job=="manual" else w.job)
	dt*=1.0+0.08*(int(w.skills.get(skill,1))-1)
	if w.job in ["wood","stone","manual","farm"]:
		var output="food" if w.job=="farm" else (source.get("kind","wood") if w.job=="manual" else w.job)
		if Logistics.room(state.data,output)==0:work_status[int(w.id)]="Пауза производства: хранилища заполнены";return
	if w.job in ["build","farm"]:
		var building=state.building_uid(int(w.workplace))
		if building.is_empty():_release(w);return
		var point=_site_target(w,building)
		if point==Vector2.INF:work_status[int(w.id)]="Нет пути к рабочему месту";return
		if not _travel(w,point,dt):return
		if w.job=="build":
			if not building.repair.is_empty():
				work_status[int(w.id)]="Ремонтирует "+state.catalog.building(building.id).name
				var maximum=battle.keep_max if building.id=="hq" else float(state.catalog.building(building.id).hp)*int(building.level)
				var current=battle.keep_hp if building.id=="hq" else float(building.hp)
				var restored=minf(float(building.repair.remaining),minf(float(building.repair.rate)*dt,maximum-current))
				if building.id=="hq":battle.keep_hp+=restored
				else:building.hp+=restored
				building.repair.remaining=maxf(0,float(building.repair.remaining)-restored)
				if building.repair.remaining<0.00001 or current+restored>=maximum-0.00001:
					if maximum-current-restored<0.00001:
						if building.id=="hq":battle.keep_hp=maximum
						else:building.hp=maximum
					building.repair={};_release(w);notice.emit("Ремонт завершён: "+state.catalog.building(building.id).name);settlement_changed.emit()
				return
			building.work_done=minf(required_work(building),float(building.work_done)+dt)
			if building.work_done>=required_work(building):
				building.built=true;building.level=int(building.target_level);building.hp=float(state.catalog.building(building.id).hp)*building.level
				Personnel.practice(w,"build",10)
				_release(w);rebuild_navigation();sync_army()
				notice.emit("Готово: "+state.catalog.building(building.id).name+" · уровень "+str(building.level));settlement_changed.emit()
		else:
			w.progress+=dt
			if w.progress>=maxf(0.5,1.6-0.25*int(building.level)):
				w.progress=0.0;w.carry+=1;w.carry_kind="food"
		return
	if source.is_empty() or source.amount<=0:
		if w.job=="manual":_release(w);return
		if battle.time<float(search_after.get(int(w.id),0)):
			work_status[int(w.id)]="Нет доступного ресурса в радиусе 8 клеток";return
		source=_find_source(w)
		if source.is_empty():
			search_after[int(w.id)]=battle.time+2.0;work_status[int(w.id)]="Нет доступного ресурса в радиусе 8 клеток";return
		w.source=int(source.id);paths.erase(int(w.id))
	if _travel(w,Vector2(source.x+0.5,source.y+0.5),dt):
		w.progress+=dt
		var building=state.building_uid(int(w.workplace));var level=int(building.level) if not building.is_empty() else 0
		if w.progress>=maxf(0.45,1.1-0.15*level):
			w.progress=0.0
			if source.amount>0:source.amount-=1;w.carry+=1;w.carry_kind=source.kind

func start_raid()->String:
	if state.data.world.raid_active:return "Набег уже идёт."
	_compact_army()
	state.data.world.raid_active=true;state.data.world.raid_number+=1;raid_time=0.0
	var rules=WorldRules.settings(state.data)
	var count=int(rules.base)+mini(int(rules.extra),int(state.data.world.raids_defeated)*int(rules.growth))
	for i in count:
		var kind="archer" if i%7==0 else "militia"
		var formation=int(state.data.world.raid_number-1)%3
		if formation==1:kind="archer" if i%3!=0 else "militia"
		elif formation==2:kind="guard" if i%3==0 else ("archer" if i%5==0 else "militia")
		var pos=Vector2((WorldData.WIDTH-2)*32+float(i%2)*8,home().y+float(i-count/2)*10)
		pos.y=clampf(pos.y,home().y-28,home().y+28)
		var def=state.catalog.troop(kind).duplicate();def.hp*=float(rules.hp);def.damage*=float(rules.damage)
		battle._add_unit(kind,1,_nearest_open(pos),def);_route_unit(battle.units[-1],home())
	flush();state.save_progress();notice.emit("Набег! Вражеский отряд идёт с востока. Защитите Штаб.")
	return "Вражеский отряд вошёл в регион."

func step(dt:float):
	if paused:return
	accumulator+=minf(dt,0.15)
	var steps=0
	while accumulator>=1.0/30.0 and steps<6:
		accumulator-=1.0/30.0;steps+=1
		_tick(1.0/30.0)

func _tick(dt:float):
	state.data.world.clock+=dt;job_timer+=dt
	if floori(state.data.world.clock/300.0)!=floori((state.data.world.clock-dt)/300.0):_regrow_wood()
	var delivery=Commerce.tick(state,dt)
	if not delivery.is_empty():notice.emit(delivery);settlement_changed.emit()
	var medical=Personnel.tick(state,dt)
	if not medical.is_empty():sync_army();notice.emit(medical);settlement_changed.emit()
	var expedition=regional.tick(dt)
	if not expedition.is_empty():
		if state.data.regional.expedition.is_empty():sync_army()
		notice.emit(expedition);settlement_changed.emit()
	chase_clock+=dt
	if chase_clock>=0.5:chase_clock=0;_update_chase_paths()
	if job_timer>2:job_timer=0;_assign_jobs();_check_goals()
	_food_tick(dt)
	for w in state.data.world.workers:
		var previous=Vector2(w.x,w.y)
		_work(w,dt*(0.6 if state.data.food==0 else 1.0))
		worker_moving[int(w.id)]=previous.distance_squared_to(Vector2(w.x,w.y))>0.00001
	battle.step(dt);battle.events.clear()
	if state.data.world.raid_active:_attack_structures()
	if state.data.world.raid_active:
		raid_time+=dt
		if battle.alive(1)==0:_end_raid(true)
		elif battle.keep_hp<=0 or raid_time>240:_end_raid(false)
	else:
		state.data.world.raid_in=maxf(0,float(state.data.world.raid_in)-dt)
		for u in battle.units:
			if u.team==0 and u.hp>0:u.hp=minf(u.max_hp,u.hp+dt*1.5)
		if state.data.world.raid_in<=0:start_raid()

func _end_raid(won:bool):
	if not state.data.world.raid_active:return
	state.data.world.raid_active=false;state.data.world.raid_in=WorldRules.settings(state.data).interval
	state.data["wins" if won else "losses"]+=1
	battle.projectiles.clear()
	var survivors=battle.survivors()
	var casualties=Personnel.casualties(state.data,state.data.army,survivors)
	state.data.army=survivors
	state.data.personnel.last_report="%s · нападение %d\nРаненых: %d · погибших: %d\nВ строю осталось: %d"%["Оборона удержана" if won else "Оборона прорвана",state.data.world.raid_number,casualties.wounded,casualties.lost,state.army_count()]
	if casualties.wounded+casualties.lost>0:notice.emit("Потери: %d раненых, %d погибших. Раненых можно вернуть через лазарет."%[casualties.wounded,casualties.lost])
	if won:
		state.data.world.raids_defeated+=1;state.data.coins+=55;state.data.food+=2;state.data.xp[state.data.selected_hero]+=35
		notice.emit("Набег отражён. Монеты +55, провиант +2, опыт героя +35. Поселение продолжает жить.")
	else:
		state.data.wood=maxi(0,int(state.data.wood)-20);battle.keep_hp=maximum_keep()*0.5
		for u in battle.units:
			if u.team==1:u.hp=0;u.died=battle.time
		notice.emit("Оборона прорвана. Потеряно 20 древесины; Штаб повреждён. Рабочие и поселение сохранены в этой ранней версии.")
	if battle.units[0].hp<=0:
		battle.units[0].hp=battle.units[0].max_hp*0.5;battle.units[0].pos=_nearest_open(home()+Vector2(-30,30));battle.units[0].prev=battle.units[0].pos
	if state.army_count()==0:state.data.army.militia=3
	state.automate();sync_army();flush();state.save_progress();raid_finished.emit(won)

func repair_quote(uid:int)->Dictionary:
	var b=state.building_uid(uid)
	if b.is_empty():return {}
	return Logistics.repair_quote(b,battle.keep_hp if b.id=="hq" else float(b.hp),battle.keep_max if b.id=="hq" else float(state.catalog.building(b.id).hp)*int(b.level),state.catalog)

func repair(uid:int=-1)->String:
	if uid<0:
		for building in state.data.buildings:
			if building.id=="hq":uid=int(building.uid);break
	var b=state.building_uid(uid);var quote=repair_quote(uid)
	if quote.is_empty():return "Нет доступного ремонта: постройка цела, строится или уже ремонтируется."
	if state.data.wood<quote.wood or state.data.stone<quote.stone:return "Нужно %d древесины и %d камня."%[quote.wood,quote.stone]
	state.data.wood-=int(quote.wood);state.data.stone-=int(quote.stone);b.repair=quote
	_assign_jobs();state.save_progress();return "Заказан ремонт: "+state.catalog.building(b.id).name+". Материалы оплачены, нужен строитель."

func cancel_repair(uid:int)->String:
	var b=state.building_uid(uid)
	if b.is_empty() or b.repair.is_empty():return "Ремонт не назначен."
	var unused=Logistics.refund(b.repair);state.data.wood+=unused.wood;state.data.stone+=unused.stone;b.repair={}
	_assign_jobs();state.save_progress();return "Ремонт отменён. Возвращено %d дерева и %d камня за оставшуюся работу."%[unused.wood,unused.stone]

func toggle_gate(uid:int)->String:
	var b=state.building_uid(uid)
	if b.is_empty() or b.id!="gate" or not b.built:return "Сначала достройте ворота."
	if b.gate_open and occupied(Vector2i(int(b.x),int(b.y))):return "Нельзя закрыть ворота: проход занят человеком."
	b.gate_open=not b.gate_open;rebuild_navigation();_assign_jobs();state.save_progress()
	return "Ворота открыты для всех, включая врага." if b.gate_open else "Ворота закрыты. Проход перекрыт."

func flush():
	if navigation_signature!=_navigation_signature():rebuild_navigation()
	if not state.data.world.raid_active:sync_army()
	var snapshot=Snapshot.capture(battle);snapshot.raid_time=float(raid_time)
	var runtime={"accumulator":float(accumulator),"job_timer":float(job_timer),"chase_clock":float(chase_clock),"command_mode":command_mode,"paused":paused,"workers":[]}
	for worker in state.data.world.workers:
		var id=int(worker.id)
		runtime.workers.append({"id":id,"path":Snapshot.pack(paths.get(id,[])),"destination":Snapshot.pack(destinations.get(id,null)),"site":Snapshot.pack(site_targets.get(id,{})),"search_after":float(search_after.get(id,0))})
	snapshot["runtime"]=runtime
	state.data.world["combat"]=snapshot

func _restore_combat()->bool:
	var snapshot=state.data.world.get("combat",{})
	if snapshot.is_empty():return false
	if snapshot.has("complete"):
		Snapshot.restore(battle,snapshot);raid_time=float(snapshot.raid_time)
		var runtime=snapshot.runtime
		accumulator=float(runtime.accumulator);job_timer=float(runtime.job_timer);chase_clock=float(runtime.chase_clock);command_mode=runtime.command_mode
		paused=runtime.paused
		for row in runtime.workers:
			var id=int(row.id);paths[id]=Snapshot.unpack(row.path)
			if row.destination!=null:destinations[id]=Snapshot.unpack(row.destination)
			if not row.site.is_empty():site_targets[id]=Snapshot.unpack(row.site);site_targets[id].uid=int(site_targets[id].uid)
			search_after[id]=float(row.search_after)
		return true
	battle.units.clear();battle.next_uid=0
	for row in snapshot.units:
		var def={"hp":row.max_hp,"damage":row.damage,"speed":row.speed,"reach":row.reach,"cooldown":row.cooldown,"rank":row.rank}
		battle._add_unit(row.kind,int(row.team),Vector2(row.x,row.y),def);battle.units[-1].hp=row.hp
		battle.units[-1].uid=int(row.get("uid",battle.units[-1].uid));battle.next_uid=maxi(battle.next_uid,int(battle.units[-1].uid)+1)
		if row.hp<=0:battle.units[-1].died=0
	battle.next_uid=maxi(battle.next_uid,int(snapshot.get("next_uid",0)))
	battle.keep_hp=minf(battle.keep_max,float(snapshot.keep_hp)+maxf(0,battle.keep_max-float(snapshot.get("keep_max",battle.keep_max))))
	battle.hero_cooldown=float(snapshot.cooldown);raid_time=float(snapshot.raid_time)
	if state.data.world.raid_active:
		for u in battle.units:
			if u.team==1 and u.hp>0:_route_unit(u,home())
	return false

func needs_work(b:Dictionary)->bool:return not b.built or int(b.target_level)>int(b.level) or not b.repair.is_empty()

func required_work(b:Dictionary)->float:return float(state.catalog.building(b.id).work)*int(b.target_level)

func _release(w:Dictionary):
	paths.erase(int(w.id));site_targets.erase(int(w.id));search_after.erase(int(w.id))
	if w.carry>0:w.returning=true
	else:w.job="idle";w.workplace=0;w.source=-1;w.progress=0.0;w.returning=false

func set_preference(id:int,preference:String)->String:
	if preference not in Settlement.PREFERENCES:return "Неизвестное назначение."
	for w in state.data.world.workers:
		if int(w.id)==id:
			if not w.post.is_empty():return "Сначала освободите человека от должности."
			w.preference=preference;_release(w);_assign_jobs();state.save_progress()
			return w.name+": назначение изменено. Уже добытый груз будет доставлен."
	return "Рабочий не найден."

func set_priority(value:bool):
	state.data.construction_first=value;_assign_jobs();state.save_progress()

func worker_status(id:int)->String:return work_status.get(id,"Ждёт назначения")

func food_need()->int:
	var logistics=Personnel.holder(state.data,"quartermaster")
	var divisor=12+2*(int(logistics.skills.logistics)-1) if Personnel.ready(state.data,"quartermaster") else 12
	return state.data.world.workers.size()+ceili(float(state.army_count())/float(divisor))

func _food_tick(dt:float):
	state.data.world.food_clock+=dt
	if state.data.world.food_clock>=60:
		state.data.world.food_clock-=60;state.data.food=maxi(0,int(state.data.food)-food_need())
		if state.data.food==0:notice.emit("Еда закончилась. Рабочие трудятся с 60% скорости. Нужны ферма или покупка провианта.")

func _regrow_wood():
	for source in state.data.world.sources:
		if source.kind!="wood" or source.amount>0:continue
		var cell=Vector2i(int(source.x),int(source.y))
		if state.building_at(cell)>=0 or state.data.world.tiles[cell.y*32+cell.x]==1:continue
		var duplicate=false
		for other in state.data.world.sources:
			if other.amount>0 and other.x==source.x and other.y==source.y:duplicate=true;break
		if not duplicate:source.amount=12

func _check_goals():
	for goal in Settlement.GOALS:
		if goal.id not in state.data.achieved and Settlement.goal_done(goal.id,state):
			state.data.achieved.append(goal.id);state.data.coins+=int(goal.reward)
			notice.emit("Рубеж пройден: "+goal.title+". Монеты +"+str(goal.reward));settlement_changed.emit()

func _site_target(w:Dictionary,b:Dictionary)->Vector2:
	var key=int(w.id)
	if site_targets.has(key) and site_targets[key].uid==int(b.uid):return site_targets[key].point
	var candidates=[]
	for x in range(int(b.x),int(b.x+b.width)):
		candidates.append(Vector2(x+0.5,float(b.y+b.height)+0.5));candidates.append(Vector2(x+0.5,float(b.y)-0.5))
	for y in range(int(b.y),int(b.y+b.height)):
		candidates.append(Vector2(float(b.x)-0.5,y+0.5));candidates.append(Vector2(float(b.x+b.width)+0.5,y+0.5))
	var best=Vector2.INF;var distance=INF
	for p in candidates:
		if not _walkable(p*WorldData.TILE):continue
		var route=_route(Vector2(w.x,w.y),p)
		if not route.is_empty() and route.size()<distance:distance=route.size();best=p
	if best!=Vector2.INF:site_targets[key]={"uid":int(b.uid),"point":best}
	return best

func _delivery_target(w:Dictionary)->Vector2:
	# Retain the chosen depot through a trip and save/load. Reconsider only if
	# destroyed or disconnected; nearest means actual path length, not distance.
	var chosen=state.building_uid(int(w.depot))
	if not chosen.is_empty() and chosen.built and chosen.id in ["hq","warehouse"]:
		var point=home()/WorldData.TILE if chosen.id=="hq" else _site_target(w,chosen)
		if point!=Vector2.INF and not _route(Vector2(w.x,w.y),point).is_empty():return point
	w.depot=0;site_targets.erase(int(w.id))
	var best=Vector2.INF;var distance=INF;var depot_uid=0
	for depot in state.data.buildings:
		if not depot.built or depot.id not in ["hq","warehouse"]:continue
		var point=home()/WorldData.TILE if depot.id=="hq" else _site_target(w,depot)
		if point==Vector2.INF:continue
		var route=_route(Vector2(w.x,w.y),point)
		if not route.is_empty() and route.size()<distance:best=point;distance=route.size();depot_uid=int(depot.uid)
	w.depot=depot_uid;site_targets.erase(int(w.id))
	if best!=Vector2.INF:site_targets[int(w.id)]={"uid":depot_uid,"point":best}
	return best

func _nearest_open(pos:Vector2)->Vector2:
	if _walkable(pos):return pos
	var center=Vector2i(pos/WorldData.TILE)
	for radius in range(1,maxi(WorldData.WIDTH,WorldData.HEIGHT)):
		for x in range(center.x-radius,center.x+radius+1):
			for y in range(center.y-radius,center.y+radius+1):
				if maxi(absi(x-center.x),absi(y-center.y))!=radius:continue
				var p=(Vector2(x,y)+Vector2.ONE*0.5)*WorldData.TILE
				if _walkable(p):return p
	return pos

func _relocate_blocked():
	for u in battle.units:
		if not _walkable(u.pos):u.pos=_unit_spawn(u.pos);u.prev=u.pos
	for w in state.data.world.workers:
		var pos=_nearest_open(Vector2(w.x,w.y)*WorldData.TILE)/WorldData.TILE
		w.x=pos.x;w.y=pos.y

func _line_clear(a:Vector2,b:Vector2)->bool:
	var count=maxi(1,ceili(a.distance_to(b)/8.0))
	for i in range(1,count):
		if not _walkable(a.lerp(b,float(i)/count)):return false
	return true

func _attack_structures():
	var removed=false
	for u in battle.units:
		if u.team!=1 or u.hp<=0 or u.timer>0 or u.attack_left>0:continue
		var nearest={};var distance=INF
		for b in state.data.buildings:
			if b.id=="hq":continue
			var area=Rect2(Vector2(b.x,b.y)*WorldData.TILE,Vector2(b.width,b.height)*WorldData.TILE)
			var closest=u.pos.clamp(area.position,area.end)
			var d=u.pos.distance_to(closest)
			if d<distance and d<24:nearest=b;distance=d
		if nearest.is_empty():continue
		nearest.hp-=u.damage;u.timer=u.cooldown
		battle.effects.append({"type":"hit","pos":u.pos+u.facing*14,"age":0.0,"life":0.25,"radius":10.0,"color":Color("edac76")})
		if nearest.hp<=0:
			state.data.buildings.erase(nearest);removed=true
			notice.emit("Разрушено: "+state.catalog.building(nearest.id).name);settlement_changed.emit()
	if removed:rebuild_navigation()

func _compact_army():
	var living=[]
	for u in battle.units:
		if u.kind=="hero" or u.hp>0:
			u.id=living.size();u.target=-1;u.attack_target=-1;u.attack_left=0.0;living.append(u)
	battle.units=living;battle.projectiles.clear();battle._rebuild_grid()

func _update_chase_paths():
	for u in battle.units:
		if u.team!=0 or u.hp<=0 or u.target<0 or u.target>=battle.units.size():continue
		if u.command in ["move","hold"]:continue
		if u.goal!=Vector2.INF and u.get("route_kind","")!="chase":continue
		var target=battle.units[u.target]
		if target.hp<=0:continue
		if not _line_clear(u.pos,target.pos):_route_unit(u,target.pos,"chase")
		elif u.get("route_kind","")=="chase":u.goal=Vector2.INF;u.path.clear()

func _unit_spawn(preferred:Vector2)->Vector2:
	for radius in range(13):
		for x in range(-radius,radius+1):
			for y in range(-radius,radius+1):
				if maxi(absi(x),absi(y))!=radius:continue
				var pos=preferred+Vector2(x,y)*16
				if not _walkable(pos) or pos.x<18 or pos.y<18 or pos.x>battle.SIZE.x-18 or pos.y>battle.SIZE.y-18:continue
				var free=true
				for other in battle.units:
					if other.hp>0 and other.pos.distance_squared_to(pos)<14*14:free=false;break
				if free:return pos
	return _nearest_open(preferred)
