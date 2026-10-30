extends RefCounted

const INTEGERS=["tick","hero_id","total_enemies","kills","initial_allies","rank","forge","skill_casts","attacks_resolved","next_uid"]
const FLOATS=["time","hero_cooldown","trace_timer","keep_hp","keep_max","buff_until"]
const UNIT_INTEGERS=["id","uid","team","rank","target","attack_target"]
const UNIT_FLOATS=["hp","max_hp","damage","speed","reach","cooldown","timer","windup","attack_left","goal_until","flash","died","poison"]
const COMMANDS=["guard","advance","move","hold"]

static func pack(value:Variant)->Variant:
	if value is Vector2:return {"v":[value.x,value.y]} if value.is_finite() else null
	if value is Color:return {"c":[value.r,value.g,value.b,value.a]}
	if value is Array:
		var result=[]
		for item in value:result.append(pack(item))
		return result
	if value is Dictionary:
		var result={}
		for key in value:result[str(key)]=pack(value[key])
		return result
	return str(value) if value is StringName else value

static func unpack(value:Variant)->Variant:
	if value is Dictionary:
		if value.size()==1 and value.has("v"):return Vector2(value.v[0],value.v[1])
		if value.size()==1 and value.has("c"):return Color(value.c[0],value.c[1],value.c[2],value.c[3])
		var result={}
		for key in value:result[key]=unpack(value[key])
		return result
	if value is Array:
		var result=[]
		for item in value:result.append(unpack(item))
		return result
	return value

static func capture(battle)->Dictionary:
	var globals={"hero_kind":battle.hero_kind,"finished":battle.finished,"won":battle.won,"rng_seed":str(battle.rng.seed),"rng_state":str(battle.rng.state)}
	for key in INTEGERS:globals[key]=int(battle.get(key))
	for key in FLOATS:globals[key]=float(battle.get(key))
	var rows=[]
	for unit in battle.units:
		var row=pack(unit);row.erase("pos");row.x=unit.pos.x;row.y=unit.pos.y
		for key in UNIT_FLOATS:row[key]=float(row[key])
		rows.append(row)
	return {"complete":1,"globals":globals,"units":rows,"projectiles":pack(battle.projectiles),"effects":pack(battle.effects),"traces":pack(battle.traces),
		"keep_position":pack(battle.keep_position),"keep_hp":float(battle.keep_hp),"keep_max":float(battle.keep_max),"cooldown":float(battle.hero_cooldown),"next_uid":battle.next_uid}

static func restore(battle,snapshot:Dictionary):
	battle.units=[]
	for row in snapshot.units:
		var unit=unpack(row);unit.pos=Vector2(row.x,row.y);unit.erase("x");unit.erase("y")
		unit.goal=Vector2.INF if row.goal==null else unpack(row.goal)
		for key in UNIT_INTEGERS:unit[key]=int(unit[key])
		battle.units.append(unit)
	for key in INTEGERS:battle.set(key,int(snapshot.globals[key]))
	for key in FLOATS:battle.set(key,float(snapshot.globals[key]))
	for key in ["hero_kind","finished","won"]:battle.set(key,snapshot.globals[key])
	battle.rng.seed=int(snapshot.globals.rng_seed);battle.rng.state=int(snapshot.globals.rng_state)
	battle.projectiles=unpack(snapshot.projectiles)
	for projectile in battle.projectiles:
		for key in ["target","source","team"]:projectile[key]=int(projectile[key])
	battle.effects=unpack(snapshot.effects);battle.traces=unpack(snapshot.traces);battle.keep_position=unpack(snapshot.keep_position)
	battle.events.clear();battle._rebuild_grid()

static func normalize(snapshot:Dictionary):
	snapshot.complete=int(snapshot.complete);snapshot.next_uid=int(snapshot.next_uid)
	for key in INTEGERS:snapshot.globals[key]=int(snapshot.globals[key])
	for row in snapshot.units:
		for key in UNIT_INTEGERS:row[key]=int(row[key])
	for projectile in snapshot.projectiles:
		for key in ["target","source","team"]:projectile[key]=int(projectile[key])
	for row in snapshot.runtime.workers:
		row.id=int(row.id)
		if not row.site.is_empty():row.site.uid=int(row.site.uid)

static func number(value:Variant)->bool:return (value is float or value is int) and is_finite(float(value))
static func integer(value:Variant)->bool:return number(value) and absf(float(value))<=1e12 and float(value)==int(value)

static func rng_integer(value:Variant)->bool:
	if not value is String or not value.is_valid_int():return false
	var digits=value.trim_prefix("-")
	if digits.length()>19:return false
	if digits.length()==19 and digits>("9223372036854775808" if value.begins_with("-") else "9223372036854775807"):return false
	return str(int(value))==value

static func vector(value:Variant,padding:float=0)->bool:
	if not value is Dictionary or value.size()!=1 or not value.get("v") is Array or value.v.size()!=2:return false
	for component in value.v:
		if not number(component):return false
	return value.v[0]>=-padding and value.v[0]<1024+padding and value.v[1]>=-padding and value.v[1]<704+padding

static func vector_list(value:Variant,limit:int=704,padding:float=0)->bool:
	if not value is Array or value.size()>limit:return false
	for item in value:
		if not vector(item,padding):return false
	return true

static func tile_vector(value:Variant)->bool:return vector(value) and value.v[0]<32 and value.v[1]<22

static func encoded(value:Variant,depth:int=0)->bool:
	if depth>8:return false
	if value==null or value is bool:return true
	if value is String:return value.length()<=256
	if value is int or value is float:return number(value) and absf(float(value))<=1e15
	if value is Array:
		if value.size()>2000:return false
		for item in value:
			if not encoded(item,depth+1):return false
		return true
	if value is Dictionary:
		if value.size()>60:return false
		if value.has("v"):return vector(value,4096)
		if value.has("c"):
			if value.size()!=1 or not value.c is Array or value.c.size()!=4:return false
			for component in value.c:
				if not number(component) or component<0 or component>1:return false
			return true
		for key in value:
			if (not key is String and not key is StringName) or not encoded(value[key],depth+1):return false
		return true
	return false

static func valid(snapshot:Dictionary,workers:Array)->bool:
	if snapshot.get("complete")!=1 or not snapshot.get("globals") is Dictionary:return false
	var globals=snapshot.globals
	for key in INTEGERS:
		if not integer(globals.get(key)) or globals[key]<0 or globals[key]>1e12:return false
	for key in FLOATS:
		if not number(globals.get(key)) or globals[key]<0 or globals[key]>1e12:return false
	if globals.get("hero_kind") not in ["astreya","lina","warden"] or not globals.get("finished") is bool or not globals.get("won") is bool:return false
	for key in ["rng_seed","rng_state"]:
		if not rng_integer(globals.get(key)):return false
	if not snapshot.get("units") is Array or snapshot.units.is_empty() or snapshot.units.size()>2000:return false
	var count=snapshot.units.size()
	if globals.hero_id!=0 or globals.next_uid!=snapshot.get("next_uid"):return false
	for index in count:
		var unit=snapshot.units[index]
		if not unit is Dictionary or not encoded(unit):return false
		for key in UNIT_INTEGERS:
			if not integer(unit.get(key)):return false
		if unit.id!=index or unit.get("command") not in COMMANDS:return false
		for key in ["target","attack_target"]:
			if unit[key]<-1 or unit[key]>=count:return false
		for key in ["timer","windup","attack_left","goal_until","flash","died","poison"]:
			if not number(unit.get(key)) or absf(float(unit[key]))>1e12:return false
		if unit.windup<0 or unit.windup>10 or unit.attack_left>unit.windup+0.001 or unit.flash<0 or unit.poison< -1:return false
		for key in ["prev","home"]:
			if not vector(unit.get(key)):return false
		if not vector(unit.get("facing"),2) or not unit.get("moving") is bool:return false
		if not unit.get("route_blocked") is bool:return false
		if unit.get("goal")!=null and not vector(unit.goal):return false
		if not unit.has("goal") or not vector_list(unit.get("path")):return false
	if not vector(snapshot.get("keep_position")):return false
	for key in ["effects","traces","projectiles"]:
		if not snapshot.get(key) is Array or snapshot[key].size()>512 or not encoded(snapshot[key]):return false
	for projectile in snapshot.projectiles:
		if not projectile is Dictionary or not vector(projectile.get("pos"),32) or not vector(projectile.get("to")):return false
		for key in ["target","source"]:
			if not integer(projectile.get(key)) or projectile[key]<0 or projectile[key]>=count:return false
		if not integer(projectile.get("team")) or int(projectile.team) not in [0,1] or not number(projectile.get("damage")) or projectile.damage<0 or not number(projectile.get("life")) or projectile.life<0 or projectile.life>2:return false
	for trace in snapshot.traces:
		if not trace is Dictionary or not vector(trace.get("a"),128) or not vector(trace.get("b"),128) or not number(trace.get("born")) or trace.born<0 or trace.born>globals.time:return false
	for effect in snapshot.effects:
		if not effect is Dictionary or effect.get("type") not in ["order","hit","slash","moon","pulse"]:return false
		if not number(effect.get("age")) or not number(effect.get("life")) or effect.age<0 or effect.life<=0 or effect.life>30 or effect.age>effect.life or not number(effect.get("radius")) or effect.radius<0 or effect.radius>4096:return false
		if not vector(effect.get("pos"),128) or not effect.get("color") is Dictionary or not effect.color.has("c"):return false
		if effect.type=="moon" and (not vector(effect.get("a"),128) or not vector(effect.get("b"),128)):return false
	var runtime=snapshot.get("runtime")
	if not runtime is Dictionary or runtime.get("command_mode") not in ["advance","move"]:return false
	if not runtime.get("paused") is bool:return false
	for key in ["accumulator","job_timer","chase_clock"]:
		if not number(runtime.get(key)) or runtime[key]<0 or runtime[key]>2.1:return false
	if not runtime.get("workers") is Array or runtime.workers.size()!=workers.size():return false
	var seen={};var ids=[]
	for worker in workers:ids.append(int(worker.id))
	for row in runtime.workers:
		if not row is Dictionary or not integer(row.get("id")) or int(row.id) not in ids or seen.has(int(row.id)):return false
		seen[int(row.id)]=true
		if not vector_list(row.get("path")):return false
		for point in row.path:
			if not tile_vector(point):return false
		if row.get("destination")!=null and not tile_vector(row.destination):return false
		if not row.get("site") is Dictionary:return false
		if not row.site.is_empty() and (not integer(row.site.get("uid")) or row.site.uid<=0 or not tile_vector(row.site.get("point"))):return false
		if not number(row.get("search_after")) or row.search_after<0 or row.search_after>1e12:return false
	return true
