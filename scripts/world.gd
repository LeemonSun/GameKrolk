extends RefCounted

signal notice(text:String)
signal raid_finished(won:bool)
const Battle=preload("res://scripts/battle.gd")
const WorldData=preload("res://scripts/world_data.gd")
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
	rebuild_navigation()
	_initialize_battle()
	_restore_combat()
	if not state.data.world.raid_active:sync_army()
	_assign_jobs()
	state.before_save=flush

func home()->Vector2:
	for b in state.data.buildings:
		if b.id=="hq":return (Vector2(b.x,b.y)+Vector2.ONE*0.5)*WorldData.TILE
	return Vector2(528,368)

func maximum_keep()->float:
	var hp=300+state.level("hq")*80
	for b in state.data.buildings:
		if b.id=="wall":hp+=int(b.level)*80
	return hp

func _initialize_battle():
	battle.start({"mode":"world","hero":state.data.selected_hero,"hero_level":state.hero_level(state.data.selected_hero),"army":{"militia":0,"archer":0,"guard":0},"enemies":0,
		"size":Vector2(WorldData.WIDTH,WorldData.HEIGHT)*WorldData.TILE,"keep_position":home(),"keep_hp":maximum_keep(),"forge":state.level("forge")})
	battle.units[0].pos=home()+Vector2(-35,40);battle.units[0].prev=battle.units[0].pos
	battle.walkable=_walkable;hero_type=state.data.selected_hero
	sync_army()

func rebuild_navigation():
	navigation.region=Rect2i(0,0,WorldData.WIDTH,WorldData.HEIGHT)
	navigation.cell_size=Vector2.ONE;navigation.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES;navigation.update()
	for y in WorldData.HEIGHT:
		for x in WorldData.WIDTH:navigation.set_point_solid(Vector2i(x,y),state.data.world.tiles[y*WorldData.WIDTH+x]==1)
	for b in state.data.buildings:
		if b.id=="wall":navigation.set_point_solid(Vector2i(int(b.x),int(b.y)),true)
	paths.clear();destinations.clear()
	if state.data.world.raid_active:
		for u in battle.units:
			if u.team==1 and u.hp>0:_route_unit(u,home())

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

func _route_unit(u:Dictionary,destination:Vector2):
	var route=_route(u.pos/WorldData.TILE,destination/WorldData.TILE)
	u.path=[]
	for p in route:u.path.append(p*WorldData.TILE)
	if not route.is_empty():u.goal=destination;u.goal_until=battle.time+3600.0

func order(group:String,pos:Vector2):
	if not _walkable(pos):notice.emit("Точка недоступна: вода или укрепление.");return
	battle.order(group,pos)
	for u in battle.units:
		if u.team==0 and u.hp>0 and (group=="all" or u.kind==group):_route_unit(u,u.goal)

func sync_army():
	var hero=battle.units[0];var def=state.catalog.hero(state.data.selected_hero)
	var hero_level=state.hero_level(state.data.selected_hero)
	var maximum=float(def.hp)*(1.0+0.08*(hero_level-1))
	if hero_type!=state.data.selected_hero:
		hero.hp=maximum;hero_type=state.data.selected_hero;battle.hero_kind=hero_type;battle.traces.clear();battle.hero_cooldown=0
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
			var pos=home()+Vector2(-80-(i%4)*16,(i/4)*18-40)
			battle._add_unit(kind,0,pos,state.catalog.troop(kind))
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

func gather(id:int)->String:
	var source=_source(id)
	if source.is_empty() or source.amount<=0:return "Источник уже исчерпан."
	for w in state.data.world.workers:
		if w.job=="idle" and w.carry==0:
			var route=_route(Vector2(w.x,w.y),Vector2(source.x+0.5,source.y+0.5))
			if route.is_empty():return "К этому ресурсу нет пути."
			w.job="manual";w.source=id;w.progress=0.0;paths.erase(int(w.id));flush();state.save_progress()
			return "Рабочий направлен на добычу. Груз попадёт в запас после доставки в Штаб."
	return "Все рабочие заняты. Лесопилка и шахта используют тех же людей."

func _assign_jobs():
	var jobs=[]
	for b in state.data.buildings:
		if b.id in ["lumber","mine"]:jobs.append("wood" if b.id=="lumber" else "stone")
	for kind in ["wood","stone"]:
		var needed=jobs.count(kind);var assigned=0
		for w in state.data.world.workers:
			if w.job==kind:assigned+=1
		for w in state.data.world.workers:
			if assigned>=needed:break
			if w.job=="idle":w.job=kind;assigned+=1

func _find_source(w:Dictionary)->Dictionary:
	var closest={};var distance=INF
	for s in state.data.world.sources:
		if s.amount<=0 or s.kind!=w.job:continue
		var near=false
		for b in state.data.buildings:
			if (b.id=="lumber" and w.job=="wood") or (b.id=="mine" and w.job=="stone"):
				if Vector2(b.x,b.y).distance_to(Vector2(s.x,s.y))<=8:near=true;break
		if not near:continue
		var d=Vector2(w.x,w.y).distance_squared_to(Vector2(s.x+0.5,s.y+0.5))
		if d<distance and not _route(Vector2(w.x,w.y),Vector2(s.x+0.5,s.y+0.5)).is_empty():distance=d;closest=s
	return closest

func _travel(w:Dictionary,target:Vector2,dt:float)->bool:
	var pos=Vector2(w.x,w.y);var id=int(w.id)
	if pos.distance_to(target)<0.08:return true
	if destinations.get(id,Vector2.INF)!=target or not paths.has(id):
		paths[id]=_route(pos,target);destinations[id]=target
	if paths[id].is_empty():return false
	var next:Vector2=paths[id][0]
	pos=pos.move_toward(next,dt*2.5)
	if pos.distance_to(next)<0.03:paths[id].pop_front()
	w.x=pos.x;w.y=pos.y
	return pos.distance_to(target)<0.08

func _work(w:Dictionary,dt:float):
	if w.job=="idle":return
	if w.carry>=5 or (w.carry>0 and (_source(int(w.source)).is_empty() or _source(int(w.source)).amount<=0)):
		if _travel(w,home()/WorldData.TILE,dt):
			state.data[w.carry_kind]+=int(w.carry);w.carry=0;w.source=-1;paths.erase(int(w.id))
			if w.job=="manual":w.job="idle"
		return
	var source=_source(int(w.source))
	if source.is_empty() or source.amount<=0:
		if w.job=="manual":w.job="idle";return
		source=_find_source(w)
		if source.is_empty():return
		w.source=int(source.id);paths.erase(int(w.id))
	if _travel(w,Vector2(source.x+0.5,source.y+0.5),dt):
		w.progress+=dt
		var level=state.level("lumber" if source.kind=="wood" else "mine")
		if w.progress>=maxf(0.45,1.1-0.15*level):
			w.progress=0.0
			if source.amount>0:source.amount-=1;w.carry+=1;w.carry_kind=source.kind

func start_raid()->String:
	if state.data.world.raid_active:return "Набег уже идёт."
	state.data.world.raid_active=true;state.data.world.raid_number+=1;raid_time=0.0
	var count=12+mini(50,int(state.data.world.raids_defeated)*4)
	for i in count:
		var kind="archer" if i%7==0 else "militia"
		var pos=Vector2((WorldData.WIDTH-2)*32+float(i%2)*8,home().y+float(i-count/2)*10)
		pos.y=clampf(pos.y,home().y-28,home().y+28)
		var def=state.catalog.troop(kind).duplicate();def.hp*=0.85;def.damage*=0.7
		battle._add_unit(kind,1,pos,def);_route_unit(battle.units[-1],home())
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
	if job_timer>2:job_timer=0;_assign_jobs()
	for w in state.data.world.workers:_work(w,dt)
	battle.step(dt);battle.events.clear()
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
	state.data.world.raid_active=false;state.data.world.raid_in=180.0
	state.data.army=battle.survivors()
	if won:
		state.data.world.raids_defeated+=1;state.data.coins+=55;state.data.food+=2;state.data.xp[state.data.selected_hero]+=35
		notice.emit("Набег отражён. Монеты +55, провиант +2, опыт героя +35. Поселение продолжает жить.")
	else:
		state.data.wood=maxi(0,int(state.data.wood)-20);battle.keep_hp=maximum_keep()*0.5
		for u in battle.units:
			if u.team==1:u.hp=0;u.died=battle.time
		notice.emit("Оборона прорвана. Потеряно 20 древесины; Штаб повреждён. Рабочие и поселение сохранены в этой ранней версии.")
	if battle.units[0].hp<=0:
		battle.units[0].hp=battle.units[0].max_hp*0.5;battle.units[0].pos=home()+Vector2(-30,30);battle.units[0].prev=battle.units[0].pos
	if state.army_count()==0:state.data.army.militia=3
	state.automate();sync_army();flush();state.save_progress();raid_finished.emit(won)

func repair()->String:
	if battle.keep_hp>=battle.keep_max:return "Штаб не нуждается в ремонте."
	if state.data.wood<20 or state.data.stone<10:return "Для ремонта нужно 20 древесины и 10 камня."
	state.data.wood-=20;state.data.stone-=10;battle.keep_hp=battle.keep_max;flush();state.save_progress();return "Штаб отремонтирован."

func flush():
	if not state.data.world.raid_active:sync_army()
	var snapshot={"keep_hp":battle.keep_hp,"keep_max":battle.keep_max,"cooldown":battle.hero_cooldown,"raid_time":raid_time,"units":[]}
	for u in battle.units:
		if u.kind!="hero" and u.hp<=0:continue
		var row={"kind":u.kind,"team":u.team,"x":u.pos.x,"y":u.pos.y,"hp":u.hp}
		for key in ["max_hp","damage","speed","reach","cooldown","rank"]:row[key]=u[key]
		snapshot.units.append(row)
	state.data.world["combat"]=snapshot

func _restore_combat():
	var snapshot=state.data.world.get("combat",{})
	if snapshot.is_empty():return
	battle.units.clear()
	for row in snapshot.units:
		var def={"hp":row.max_hp,"damage":row.damage,"speed":row.speed,"reach":row.reach,"cooldown":row.cooldown,"rank":row.rank}
		battle._add_unit(row.kind,int(row.team),Vector2(row.x,row.y),def);battle.units[-1].hp=row.hp
		if row.hp<=0:battle.units[-1].died=0
	battle.keep_hp=minf(battle.keep_max,float(snapshot.keep_hp)+maxf(0,battle.keep_max-float(snapshot.get("keep_max",battle.keep_max))))
	battle.hero_cooldown=float(snapshot.cooldown);raid_time=float(snapshot.raid_time)
	if state.data.world.raid_active:
		for u in battle.units:
			if u.team==1 and u.hp>0:_route_unit(u,home())
