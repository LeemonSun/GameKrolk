extends RefCounted

const WIDTH=32
const HEIGHT=22
const TILE=32.0

static func generate(seed_value:int)->Dictionary:
	var rng=RandomNumberGenerator.new();rng.seed=seed_value
	var noise=FastNoiseLite.new();noise.seed=seed_value;noise.frequency=0.09
	var tiles=[];var sources=[];var center=Vector2i(16,11)
	for y in HEIGHT:
		for x in WIDTH:
			var n=noise.get_noise_2d(x,y)
			var tile=1 if n<-0.35 else 0
			var clearing=Vector2i(x,y).distance_to(center)<5 or (absi(y-center.y)<2 and x>=center.x) or (x<=3 and y<=3)
			if clearing:tile=0
			tiles.append(tile)
			if tile==0 and not clearing and rng.randf()<0.16:
				var kind="wood" if rng.randf()<0.77 else "stone"
				sources.append({"id":sources.size(),"x":x,"y":y,"kind":kind,"amount":rng.randi_range(24,50) if kind=="wood" else rng.randi_range(50,100)})
	# Accessible starting deposits make each seed playable, independent of noise.
	for pos in [Vector2i(11,9),Vector2i(11,11),Vector2i(12,13),Vector2i(14,15),Vector2i(20,8),Vector2i(20,13)]:
		tiles[pos.y*WIDTH+pos.x]=0
		for source in sources:
			if int(source.x)==pos.x and int(source.y)==pos.y:source.amount=0
		sources.append({"id":sources.size(),"x":pos.x,"y":pos.y,"kind":"stone" if pos==Vector2i(20,8) else "wood","amount":85})
	var workers=[]
	for i in 3:workers.append({"id":i,"x":16.0+i*0.5,"y":14.5,"job":"idle","source":-1,"carry":0,"carry_kind":"wood","progress":0.0})
	return {"seed":seed_value,"width":WIDTH,"height":HEIGHT,"tiles":tiles,"sources":sources,"workers":workers,"clock":0.0,"raid_in":150.0,"raids_defeated":0,"raid_active":false,"raid_number":0}

static func valid(value:Variant)->bool:
	if not value is Dictionary:return false
	if value.get("width")!=WIDTH or value.get("height")!=HEIGHT:return false
	if not value.get("tiles") is Array or value.tiles.size()!=WIDTH*HEIGHT:return false
	for tile in value.tiles:
		if tile!=0 and tile!=1:return false
	if not value.get("sources") is Array or value.sources.size()>WIDTH*HEIGHT:return false
	var ids={};var positions={}
	for s in value.sources:
		if not s is Dictionary:return false
		for key in ["id","x","y","amount"]:
			if not number(s.get(key)):return false
		if s.x<0 or s.x>=WIDTH or s.y<0 or s.y>=HEIGHT or s.amount<0 or s.amount>10000 or s.id<0:return false
		if s.get("kind") not in ["wood","stone"] or ids.has(int(s.id)):return false
		ids[int(s.id)]=true
		var cell=Vector2i(int(s.x),int(s.y))
		if s.amount>0 and positions.has(cell):return false
		if s.amount>0:positions[cell]=true
	if not value.get("workers") is Array or value.workers.size()>30:return false
	for w in value.workers:
		if not w is Dictionary:return false
		for key in ["id","x","y","source","carry","progress"]:
			if not number(w.get(key)):return false
		if w.x<0 or w.x>=WIDTH or w.y<0 or w.y>=HEIGHT or w.carry<0 or w.carry>20 or w.progress<0 or w.progress>10:return false
		if w.get("job") not in ["idle","wood","stone","manual","build","farm"] or w.get("carry_kind") not in ["wood","stone","food"]:return false
	for key in ["clock","raid_in","raids_defeated","raid_number","seed"]:
		if not number(value.get(key)):return false
	if value.clock<0 or value.raid_in<0 or value.raid_in>10000:return false
	var combat=value.get("combat",{})
	if not combat is Dictionary:return false
	if not combat.is_empty():
		for key in ["keep_hp","cooldown","raid_time"]:
			if not number(combat.get(key)) or combat[key]<0:return false
		if not combat.get("units") is Array or combat.units.is_empty() or combat.units.size()>2000:return false
		if not combat.units[0] is Dictionary or combat.units[0].get("kind")!="hero":return false
		var combat_ids={};var maximum_uid=-1
		for u in combat.units:
			if not u is Dictionary or u.get("kind") not in ["hero","militia","archer","guard"]:return false
			for key in ["team","x","y","hp","max_hp","damage","speed","reach","cooldown","rank"]:
				if not number(u.get(key)) or u[key]<0 or u[key]>10000000:return false
			if int(u.team) not in [0,1] or float(u.team)!=int(u.team) or u.x>=WIDTH*TILE or u.y>=HEIGHT*TILE or u.hp>u.max_hp or u.max_hp<=0 or u.cooldown<=0:return false
			if u.has("uid"):
				if not number(u.uid) or u.uid<0 or float(u.uid)!=int(u.uid) or combat_ids.has(int(u.uid)):return false
				combat_ids[int(u.uid)]=true;maximum_uid=maxi(maximum_uid,int(u.uid))
		if combat.has("next_uid"):
			if not number(combat.next_uid) or float(combat.next_uid)!=int(combat.next_uid) or combat.next_uid<=maximum_uid:return false
	return value.get("raid_active") is bool

static func number(v:Variant)->bool:return (v is int or v is float) and is_finite(float(v))
