extends RefCounted

const Atlas=preload("res://scripts/atlas.gd")
const Chunks=preload("res://scripts/terrain_chunks.gd")
const SIZE=128
var state
var atlas
var chunks
var navigation=AStarGrid2D.new()
var ready=false

static func initialize(data:Dictionary):
	if not data.has("regional"):
		data.regional={"version":1,"generator":1,"seed":int(data.world.seed),"size":SIZE,"home":[-1,-1],"known":[],"changes":{},"expedition":{},"completed":0}

func _init(game_state):state=game_state

func ensure():
	if ready:return
	atlas=Atlas.new();atlas.build(int(state.data.regional.seed),int(state.data.regional.size));chunks=Chunks.new(atlas)
	navigation.region=Rect2i(0,0,atlas.side,atlas.side);navigation.cell_size=Vector2.ONE;navigation.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES;navigation.update()
	for y in atlas.side:
		for x in atlas.side:navigation.set_point_solid(Vector2i(x,y),not atlas.land(Vector2i(x,y)))
	if empty_home(state.data.regional.home):
		state.data.regional.home=[atlas.home.x,atlas.home.y];state.data.regional.known=[key(atlas.home)]
	ready=true

static func key(point:Vector2i)->String:return "%d:%d"%[point.x,point.y]
func home()->Vector2i:ensure();return Vector2i(int(state.data.regional.home[0]),int(state.data.regional.home[1]))
func known(point:Vector2i)->bool:return key(point) in state.data.regional.known

func route(point:Vector2i)->Array:
	ensure()
	if not atlas.land(point):return []
	var result=[]
	for cell in navigation.get_id_path(home(),point):result.append([cell.x,cell.y])
	return result

func region(point:Vector2i)->Dictionary:
	ensure()
	if point==home():return {"x":point.x,"y":point.y,"tiles":state.data.world.tiles,"sources":state.data.world.sources,"home":true}
	var generated=chunks.get_chunk(point)
	if generated.is_empty():return {}
	var result=generated.duplicate(true);var changes=state.data.regional.changes.get(key(point),{})
	for source in result.sources:
		if changes.has(str(source.id)):source.amount=int(changes[str(source.id)])
	return result

func remaining(point:Vector2i,kind:String)->int:
	var result=0
	for source in region(point).get("sources",[]):
		if source.kind==kind:result+=int(source.amount)
	return result

func reason(point:Vector2i,operation:String)->String:
	ensure()
	if not state.data.regional.expedition.is_empty():return "Сначала дождитесь возвращения отряда."
	if state.data.world.raid_active:return "Нельзя отправить людей во время нападения."
	if not atlas.land(point):return "Отряд не пересекает море или озеро."
	if point==home():return "Это ваше поселение: добыча здесь управляется на месте."
	if operation not in ["survey","wood","stone"]:return "Неизвестное поручение."
	if operation!="survey" and not known(point):return "Сначала разведайте область."
	if operation!="survey" and remaining(point,operation)==0:return "Доступный запас исчерпан."
	if state.data.army.militia<2:return "Нужно два мечника для походного отряда."
	if state.data.food<3:return "Нужно три провианта на поход."
	if route(point).is_empty():return "Нет сухопутного маршрута от поселения."
	return ""

func send(point:Vector2i,operation:String)->String:
	var error=reason(point,operation)
	if not error.is_empty():return error
	var path=route(point)
	state.data.army.militia-=2;state.data.food-=3
	state.data.regional.expedition={"destination":[point.x,point.y],"path":path,"phase":"outbound","index":0,"elapsed":0.0,"cargo":{"wood":0,"stone":0},"crew":2,"operation":operation}
	state.save_progress();return "Отряд отправлен. Два мечника отсутствуют в гарнизоне до возвращения."

func tick(dt:float)->String:
	var expedition=state.data.regional.expedition
	if expedition.is_empty():return ""
	ensure()
	if expedition.phase=="waiting":expedition.elapsed=0.0
	else:expedition.elapsed+=dt
	if expedition.phase=="gather":
		if expedition.elapsed<12:return ""
		expedition.elapsed=0.0
		if expedition.operation!="survey":_collect(expedition)
		expedition.phase="return";expedition.index=expedition.path.size()-1
		return "Поручение выполнено. Отряд возвращается с грузом: %d дерева, %d камня."%[expedition.cargo.wood,expedition.cargo.stone]
	elif expedition.phase=="outbound" or expedition.phase=="return":
		if expedition.elapsed<2:return ""
		expedition.elapsed-=2.0
		if expedition.phase=="outbound":
			expedition.index+=1
			var visited=expedition.path[mini(int(expedition.index),expedition.path.size()-1)]
			var explored=key(Vector2i(int(visited[0]),int(visited[1])))
			if explored not in state.data.regional.known:state.data.regional.known.append(explored)
			if expedition.index>=expedition.path.size()-1:
				expedition.index=expedition.path.size()-1;expedition.phase="gather";expedition.elapsed=0.0
				var destination=Vector2i(int(expedition.destination[0]),int(expedition.destination[1]))
				if not known(destination):state.data.regional.known.append(key(destination))
				return "Отряд достиг области %d,%d и приступил к поручению."%expedition.destination
		else:
			expedition.index-=1
			if expedition.index<=0:expedition.index=0;expedition.phase="waiting";expedition.elapsed=0.0
	if expedition.phase=="waiting" and not state.data.world.raid_active:
		state.data.army.militia+=int(expedition.crew);state.data.wood+=int(expedition.cargo.wood);state.data.stone+=int(expedition.cargo.stone)
		var message="Отряд вернулся: 2 мечника, %d дерева, %d камня."%[expedition.cargo.wood,expedition.cargo.stone]
		state.data.regional.expedition={};state.data.regional.completed+=1;return message
	return ""

func recall()->String:
	var expedition=state.data.regional.expedition
	if expedition.is_empty():return "Нет отряда в пути."
	if expedition.phase in ["return","waiting"]:return "Отряд уже возвращается."
	expedition.phase="waiting" if expedition.index==0 else "return";expedition.elapsed=0.0
	state.save_progress();return "Отряд возвращается по пройденному маршруту. Провиант не возвращается."

func _collect(expedition:Dictionary):
	var point=Vector2i(int(expedition.destination[0]),int(expedition.destination[1]));var id=key(point)
	var budget=25
	if not state.data.regional.changes.has(id):state.data.regional.changes[id]={}
	for source in region(point).sources:
		if source.kind!=expedition.operation or source.amount<=0:continue
		var amount=mini(budget,int(source.amount));budget-=amount
		state.data.regional.changes[id][str(source.id)]=int(source.amount)-amount;expedition.cargo[source.kind]+=amount
		if budget==0:break

static func coordinate(value:Variant,size:int,allow_empty:bool=false)->bool:
	if not value is Array or value.size()!=2:return false
	if allow_empty and empty_home(value):return true
	for n in value:
		if not integer(n) or n<0 or n>=size:return false
	return true
static func empty_home(value:Variant)->bool:
	return value is Array and value.size()==2 and integer(value[0]) and integer(value[1]) and value[0]==-1 and value[1]==-1
static func valid(data:Dictionary)->bool:
	var map=data.get("regional")
	if not map is Dictionary or map.get("version")!=1 or map.get("generator")!=1 or map.get("seed")!=data.world.seed or map.get("size")!=SIZE:return false
	if not coordinate(map.get("home"),SIZE,true) or not integer(map.get("completed")) or map.completed<0 or map.completed>10000000:return false
	if not map.get("known") is Array or map.known.size()>SIZE*SIZE or not map.get("changes") is Dictionary or map.changes.size()>4096 or not map.get("expedition") is Dictionary:return false
	var seen={}
	for entry in map.known:
		if not valid_key(entry) or seen.has(entry):return false
		seen[entry]=true
	if empty_home(map.home):
		if not map.known.is_empty() or not map.changes.is_empty() or not map.get("expedition",{}).is_empty():return false
	elif key(Vector2i(int(map.home[0]),int(map.home[1]))) not in seen:return false
	var changed=0
	for chunk in map.changes:
		if not valid_key(chunk) or not map.changes[chunk] is Dictionary:return false
		changed+=map.changes[chunk].size()
		if changed>32768:return false
		for source in map.changes[chunk]:
			if not source is String or not source.is_valid_int() or str(int(source))!=source or int(source)<0 or int(source)>=32*22:return false
			var amount=map.changes[chunk][source]
			if not integer(amount) or amount<0 or amount>80:return false
	if not map.get("expedition") is Dictionary:return false
	var e=map.expedition
	if not e.is_empty():
		if empty_home(map.home) or not coordinate(e.get("destination"),SIZE) or e.get("operation") not in ["survey","wood","stone"] or e.get("phase") not in ["outbound","gather","return","waiting"] or e.get("crew")!=2:return false
		if not e.get("path") is Array or e.path.size()<2 or e.path.size()>SIZE*SIZE:return false
		if e.path[0]!=map.home or e.path[-1]!=e.destination:return false
		for i in e.path.size():
			if not coordinate(e.path[i],SIZE):return false
			if i>0:
				var delta=Vector2(e.path[i][0]-e.path[i-1][0],e.path[i][1]-e.path[i-1][1])
				if delta.length_squared()==0 or delta.length_squared()>2:return false
		if not integer(e.get("index")) or e.index<0 or e.index>=e.path.size() or not number(e.get("elapsed")) or e.elapsed<0 or e.elapsed>12.01:return false
		if not e.get("cargo") is Dictionary or e.cargo.size()!=2:return false
		for kind in ["wood","stone"]:
			if not integer(e.cargo.get(kind)) or e.cargo[kind]<0 or e.cargo[kind]>25:return false
		if e.cargo.wood+e.cargo.stone>25:return false
		if e.operation=="survey" and (e.cargo.wood!=0 or e.cargo.stone!=0):return false
		if e.operation=="wood" and e.cargo.stone!=0 or e.operation=="stone" and e.cargo.wood!=0:return false
		if e.phase in ["outbound","gather"] and (e.cargo.wood!=0 or e.cargo.stone!=0):return false
		if e.phase=="outbound" and e.index>=e.path.size()-1:return false
		if e.phase=="gather" and e.index!=e.path.size()-1:return false
		if e.phase=="waiting" and (e.index!=0 or e.elapsed!=0):return false
	return true
static func valid_key(value:Variant)->bool:
	if not value is String:return false
	var parts=value.split(":")
	if parts.size()!=2:return false
	for n in parts:
		if not n.is_valid_int() or str(int(n))!=n or int(n)<0 or int(n)>=SIZE:return false
	return true
static func number(value:Variant)->bool:return (value is int or value is float) and is_finite(value)
static func integer(value:Variant)->bool:return number(value) and absf(value)<=1e12 and float(value)==int(value)
