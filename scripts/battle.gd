extends RefCounted

const Catalog=preload("res://scripts/catalog.gd")
var SIZE=Vector2(1000,600)
const CELL=76.0
var catalog=Catalog.new()
var units:Array=[]
var projectiles:Array=[]
var effects:Array=[]
var events:Array=[]
var grid:Dictionary={}
var rng=RandomNumberGenerator.new()
var time=0.0
var tick=0
var hero_id=0
var hero_kind="astreya"
var hero_cooldown=0.0
var traces:Array=[]
var trace_timer=0.0
var keep_hp=400.0
var keep_max=400.0
var finished=false
var won=false
var mode="siege"
var total_enemies=0
var kills=0
var initial_allies=0
var buff_until=0.0
var rank=1
var forge=0
var skill_casts=0
var attacks_resolved=0
var keep_position=Vector2(83,300)
var walkable=Callable()
var line_clear=Callable()
var next_uid=0

func start(config:Dictionary):
	units.clear();projectiles.clear();effects.clear();events.clear();grid.clear();traces.clear()
	next_uid=0
	time=0;tick=0;hero_cooldown=0;finished=false;won=false;kills=0;buff_until=0;skill_casts=0;attacks_resolved=0;trace_timer=0
	rng.seed=int(config.get("seed",20261029))
	mode=config.get("mode","siege");hero_kind=config.get("hero","astreya");rank=int(config.get("rank",1));forge=int(config.get("forge",0))
	SIZE=config.get("size",Vector2(1000,600));keep_position=config.get("keep_position",Vector2(83,300))
	keep_max=float(config.get("keep_hp",400));keep_hp=keep_max
	var h=catalog.hero(hero_kind).duplicate(true)
	var level=int(config.get("hero_level",1))
	h.hp=float(h.hp)*(1.0+0.08*(level-1));h.damage=float(h.damage)*(1.0+0.07*(level-1));h.rank=4
	_add_unit("hero",0,Vector2(220,300),h)
	hero_id=0
	var army=config.get("army",{"militia":12,"archer":8,"guard":0})
	var n=0
	var ally_count=0
	for amount in army.values():ally_count+=int(amount)
	var rows=12 if ally_count<60 else 25
	var spacing=34 if ally_count<60 else 20
	for kind in ["guard","militia","archer"]:
		for i in int(army.get(kind,0)):
			var col=n/rows;var row=n%rows
			var x=230.0-float(col)*20.0 if kind!="archer" else 140.0-float(col)*16.0
			if ally_count>=60:x=300-float(col)*10.0
			_add_unit(kind,0,Vector2(x,55+row*spacing+rng.randf_range(-3,3)),catalog.troop(kind))
			n+=1
	initial_allies=n
	var count=int(config.get("enemies",26+rank*7))
	for i in count:
		var kind="militia"
		if i%7==0:kind="archer"
		elif i%9==0:kind="guard"
		var def=catalog.troop(kind).duplicate(true)
		def.hp=float(def.hp)*(0.8+rank*0.07);def.damage=float(def.damage)*(0.65+rank*0.06)
		var enemy_rows=15 if count<60 else 25
		var row=i%enemy_rows;var col=i/enemy_rows
		var separation=22 if count<60 else minf(12.0,220.0/maxf(1.0,ceilf(float(count)/enemy_rows)))
		_add_unit(kind,1,Vector2(730+col*separation+rng.randf_range(-3,3),55+row*(33 if count<60 else 20)+rng.randf_range(-3,3)),def)
	total_enemies=count
	_rebuild_grid()

func _add_unit(kind:String,team:int,pos:Vector2,def:Dictionary):
	var u={"id":units.size(),"uid":next_uid,"kind":kind,"team":team,"pos":pos,"prev":pos,"home":pos,"hp":float(def.hp),"max_hp":float(def.hp),
		"damage":float(def.damage)*(1.0+forge*0.07 if team==0 else 1.0),"speed":float(def.speed),"reach":float(def.reach),"cooldown":float(def.cooldown),
		"rank":int(def.get("rank",1)),"timer":rng.randf_range(0,0.5),"target":-1,"attack_target":-1,"windup":0.0,"attack_left":0.0,
		"facing":Vector2.RIGHT if team==0 else Vector2.LEFT,"goal":Vector2.INF,"goal_until":0.0,"moving":false,"flash":0.0,"died":-1.0,"poison":0.0,"path":[],"command":"guard","route_blocked":false}
	units.append(u)
	next_uid+=1

func _cell(pos:Vector2)->Vector2i:return Vector2i(floori(pos.x/CELL),floori(pos.y/CELL))

func _rebuild_grid():
	grid.clear()
	for u in units:
		if u.hp<=0:continue
		var key=Vector3i(_cell(u.pos).x,_cell(u.pos).y,u.team)
		if not grid.has(key):grid[key]=[]
		grid[key].append(u.id)

func _near(pos:Vector2,team:int,radius:float)->Array:
	var out:Array=[];var center=_cell(pos);var extent=ceili(radius/CELL);var r2=radius*radius
	for x in range(center.x-extent,center.x+extent+1):
		for y in range(center.y-extent,center.y+extent+1):
			for id in grid.get(Vector3i(x,y,team),[]):
				if units[id].hp>0 and pos.distance_squared_to(units[id].pos)<=r2:out.append(id)
	return out

func _find_target(u:Dictionary)->int:
	var closest=-1;var distance=INF;var center=_cell(u.pos)
	var radius=float(u.reach) if u.command=="hold" else (230.0 if u.reach>60 else 160.0)
	# Search local rings first; an engaged unit does not scan the whole battle.
	for ring in range(ceili(radius/CELL)+1):
		for x in range(center.x-ring,center.x+ring+1):
			for y in range(center.y-ring,center.y+ring+1):
				if maxi(absi(x-center.x),absi(y-center.y))!=ring:continue
				for id in grid.get(Vector3i(x,y,1-int(u.team)),[]):
					var target=units[id]
					if target.hp<=0:continue
					var d=u.pos.distance_squared_to(target.pos)
					if d<distance and d<=radius*radius:distance=d;closest=id
		if closest>=0 and ring>=1:return closest
	return closest

func alive(team:int)->int:
	var n=0
	for u in units:
		if u.team==team and u.hp>0:n+=1
	return n

func survivors()->Dictionary:
	var counts={"militia":0,"archer":0,"guard":0}
	for u in units:
		if u.team==0 and u.hp>0 and counts.has(u.kind):counts[u.kind]+=1
	return counts

func order(group:String,pos:Vector2,command:String="advance"):
	if finished:return
	pos=pos.clamp(Vector2(65,45),SIZE-Vector2(40,45))
	var count=0
	for u in units:
		if u.team==0 and u.hp>0 and (group=="all" or group==u.kind):count+=1
	var columns=mini(25,maxi(1,ceili(sqrt(float(count)))))
	var rows=ceili(float(count)/columns)
	var spacing=Vector2(24,26) if mode=="world" else Vector2(17,19)
	var extent=Vector2(columns-1,rows-1)*spacing*0.5
	pos=pos.clamp(Vector2(65,45)+extent,SIZE-Vector2(40,45)-extent)
	var n=0
	for u in units:
		if u.team!=0 or u.hp<=0:continue
		if group!="all" and group!=u.kind:continue
		var offset=Vector2(float(n%columns)-(columns-1)*0.5,float(n/columns)-(rows-1)*0.5)*spacing
		if group=="hero":offset=Vector2.ZERO
		u.goal=(pos+offset).clamp(Vector2(65,35),SIZE-Vector2(35,35));u.goal_until=time+3600.0;u.command=command
		u.target=-1;u.attack_target=-1;u.attack_left=0.0;n+=1
		u.route_blocked=false
	effects.append({"type":"order","pos":pos,"age":0.0,"life":0.8,"radius":22.0,"color":Color("d6c18b")})

func step(dt:float):
	if finished:return
	time+=dt;tick+=1;hero_cooldown=maxf(0,hero_cooldown-dt)
	_rebuild_grid()
	for i in range(effects.size()-1,-1,-1):
		effects[i].age+=dt
		if effects[i].age>=effects[i].life:effects.remove_at(i)
	for u in units:
		u.prev=u.pos;u.flash=maxf(0,u.flash-dt);u.moving=false
		if u.hp<=0:continue
		u.timer-=dt
		if u.poison>0:
			u.poison-=dt;_damage(u.id,dt*5,-1)
			if u.hp<=0:continue
		if u.attack_left>0:
			u.attack_left-=dt
			if u.attack_left<=0:_resolve_attack(u)
			continue
		var commanded=u.goal!=Vector2.INF and time<u.goal_until
		if commanded and u.pos.distance_to(u.goal)<(2.5 if mode=="world" else 9.0):
			u.home=u.goal;u.goal=Vector2.INF;u.path.clear();commanded=false
			if u.command=="move":u.command="guard"
		var ignore_enemy=u.command=="move" and commanded
		if ignore_enemy:u.target=-1
		var valid_target=u.target>=0 and units[u.target].hp>0
		if not valid_target:
			if not ignore_enemy and (u.target>=0 or tick%12==int(u.id)%12):u.target=_find_target(u)
		elif tick%30==int(u.id)%30 and u.pos.distance_squared_to(units[u.target].pos)>pow(u.reach+30,2):u.target=_find_target(u)
		var movement=Vector2.ZERO
		var target=units[u.target] if u.target>=0 and units[u.target].hp>0 else null
		var dist=u.pos.distance_to(target.pos) if target!=null else INF
		if target!=null and dist<=u.reach and (not line_clear.is_valid() or line_clear.call(u.pos,target.pos)):
			u.facing=(target.pos-u.pos).normalized()
			if u.timer<=0:
				u.attack_target=target.id;u.windup=0.17 if u.reach<60 else 0.25;u.attack_left=u.windup;u.timer=u.cooldown
		elif commanded:
			if not u.route_blocked:
				while not u.path.is_empty() and u.pos.distance_to(u.path[0])<6:u.path.pop_front()
				movement=((u.path[0] if not u.path.is_empty() else u.goal)-u.pos).normalized()
		elif target!=null and u.command!="hold":movement=(target.pos-u.pos).normalized()
		elif u.team==1:
			var keep=keep_position
			if u.pos.distance_to(keep)<45 and (not line_clear.is_valid() or line_clear.call(u.pos,keep)):
				if u.timer<=0:
					keep_hp=maxf(0,keep_hp-u.damage);u.timer=u.cooldown
					if effects.size()<160:effects.append({"type":"hit","pos":keep+Vector2(20,rng.randf_range(-25,25)),"age":0.0,"life":0.25,"radius":10.0,"color":Color("edac76")})
			else:movement=(keep-u.pos).normalized()
		if movement.length_squared()>0.01:
			var separation=Vector2.ZERO
			for id in _near(u.pos,u.team,14):
				if id==u.id:continue
				var diff=u.pos-units[id].pos;var d2=diff.length_squared()
				if d2>0.01:separation+=diff.normalized()*(1.0-sqrt(d2)/14.0)
			movement=(movement+separation*0.9).normalized()
			var destination=(u.pos+movement*u.speed*dt).clamp(Vector2(18,18) if mode=="world" else Vector2(60,30),SIZE-Vector2(18,18) if mode=="world" else SIZE-Vector2(25,30))
			if not walkable.is_valid() or walkable.call(destination):u.pos=destination
			elif walkable.call(Vector2(destination.x,u.pos.y)):u.pos.x=destination.x
			elif walkable.call(Vector2(u.pos.x,destination.y)):u.pos.y=destination.y
			u.facing=movement;u.moving=u.pos.distance_squared_to(u.prev)>0.01
	_update_projectiles(dt)
	trace_timer+=dt
	var hero=units[hero_id]
	if hero.hp>0 and hero_kind=="astreya" and hero.moving and trace_timer>0.22:
		trace_timer=0;_trace(hero.pos-hero.facing*28,hero.pos+hero.facing*12)
	for i in range(traces.size()-1,-1,-1):
		if time-traces[i].born>14:traces.remove_at(i)
	if mode=="world":return
	if keep_hp<=0 or alive(0)==0 or time>=180:
		finished=true;won=false
	elif alive(1)==0:finished=true;won=true

func stop(group:String,hold:bool=false):
	for unit in units:
		if unit.team!=0 or unit.hp<=0 or (group!="all" and unit.kind!=group):continue
		unit.command="hold" if hold else "guard";unit.goal=Vector2.INF;unit.path.clear();unit.goal_until=0.0;unit.home=unit.pos
		unit.route_blocked=false
		unit.target=-1;unit.attack_target=-1;unit.attack_left=0.0

func _trace(a:Vector2,b:Vector2):
	traces.append({"a":a,"b":b,"born":time})
	if traces.size()>28:traces.pop_front()

func _resolve_attack(u:Dictionary):
	var id=int(u.attack_target)
	if u.hp<=0 or id<0 or id>=units.size() or units[id].hp<=0:return
	var target=units[id]
	if u.pos.distance_to(target.pos)>u.reach+14:return
	if line_clear.is_valid() and not line_clear.call(u.pos,target.pos):return
	attacks_resolved+=1
	if u.reach>60:
		var destination=target.pos
		projectiles.append({"pos":u.pos+Vector2(0,-9),"to":destination,"target":id,"source":u.id,"damage":u.damage,"team":u.team,"life":2.0})
	else:
		var gap=int(u.rank)-int(target.rank)
		var dodged=gap<=-2 and rng.randf()<0.48
		var hit_color=Color("d3bf8f") if dodged else Color("f6d499")
		if not dodged:_damage(id,u.damage,u.id)
		if effects.size()<160:effects.append({"type":"slash","pos":target.pos,"age":0.0,"life":0.24,"radius":19.0 if u.kind=="hero" else 10.0,"color":hit_color,"dir":u.facing,"miss":dodged})
		if u.kind=="hero" and hero_kind=="astreya":
			var axis=u.facing.orthogonal()*45
			_trace(u.pos+u.facing*24-axis,u.pos+u.facing*24+axis)

func _damage(id:int,amount:float,source:int):
	var u=units[id]
	if u.hp<=0:return
	if u.kind=="guard":amount*=0.7
	if u.kind=="hero" and hero_kind=="warden":amount*=0.55
	if u.team==0 and time<buff_until:amount*=0.5
	u.hp=maxf(0,u.hp-amount);u.flash=0.10
	if u.hp<=0:
		u.died=time
		if u.team==1:kills+=1
		events.append({"type":"death","id":id,"source":source})

func _update_projectiles(dt:float):
	for i in range(projectiles.size()-1,-1,-1):
		var p=projectiles[i];p.life-=dt
		var old:Vector2=p.pos
		p.pos=old.move_toward(p.to,360*dt)
		if line_clear.is_valid() and not line_clear.call(old,p.pos):projectiles.remove_at(i);continue
		var target=units[p.target]
		var nearest=Geometry2D.get_closest_point_to_segment(target.pos,old,p.pos)
		var struck=target.hp>0 and nearest.distance_to(target.pos)<12
		if struck:
			_damage(p.target,p.damage,p.source)
			if effects.size()<160:effects.append({"type":"hit","pos":p.pos,"age":0.0,"life":0.18,"radius":7.0,"color":Color("f0d69c")})
		if struck or p.life<=0 or p.pos.distance_to(p.to)<1:projectiles.remove_at(i)

func skill()->String:
	if finished:return "Бой завершён."
	var hero=units[hero_id]
	if hero.hp<=0:return "Герой выбыл из боя."
	if hero_cooldown>0:return "Техника ещё восстанавливается."
	if hero_kind=="astreya" and traces.is_empty():return "Накопите следы: двигайтесь или атакуйте."
	hero_cooldown=float(catalog.hero(hero_kind).skill_cooldown);skill_casts+=1
	if hero_kind=="astreya":
		for line in traces:
			effects.append({"type":"moon","a":line.a,"b":line.b,"pos":line.a,"age":0.0,"life":0.65,"radius":1.0,"color":Color("ff757f")})
		for u in units:
			if u.team!=1 or u.hp<=0:continue
			for line in traces:
				if Geometry2D.get_closest_point_to_segment(u.pos,line.a,line.b).distance_to(u.pos)<48:
					_damage(u.id,75+hero.damage*0.6,hero_id);break
		traces.clear()
	elif hero_kind=="lina":
		for u in units:
			if u.hp<=0 or hero.pos.distance_to(u.pos)>190:continue
			if u.team==0:u.hp=minf(u.max_hp,u.hp+55)
			else:u.poison=7
		effects.append({"type":"pulse","pos":hero.pos,"age":0.0,"life":1.0,"radius":190.0,"color":Color("86e0be")})
	else:
		buff_until=time+7
		for u in units:
			if u.team==1 and u.hp>0 and hero.pos.distance_to(u.pos)<125:
				_damage(u.id,42,hero_id)
				var pushed=(u.pos+(u.pos-hero.pos).normalized()*32).clamp(Vector2(60,30),SIZE-Vector2(25,30))
				if not walkable.is_valid() or (walkable.call(pushed) and (not line_clear.is_valid() or line_clear.call(u.pos,pushed))):u.pos=pushed
		effects.append({"type":"pulse","pos":hero.pos,"age":0.0,"life":0.7,"radius":125.0,"color":Color("e8c98c")})
	return catalog.hero(hero_kind).skill

func can_auto_skill()->bool:
	var hero=units[hero_id]
	if finished or hero.hp<=0 or hero_cooldown>0:return false
	if hero_kind=="lina" and hero.hp<hero.max_hp*0.6:return true
	return not _near(hero.pos,1,85 if hero_kind=="astreya" else 135).is_empty() and (hero_kind!="astreya" or not traces.is_empty())
