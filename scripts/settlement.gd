extends RefCounted

const NAMES=["Марк","Тая","Орин","Ника","Бран","Лея","Рен","Ива","Дан","Эна","Тор","Мира","Фенн","Юна","Лар","Сева","Вел","Дора","Кир","Зоя","Алан","Мея","Нор","Эль"]
const PREFERENCES=["auto","build","wood","stone","farm","rest"]
const GOALS=[
	{"id":"delivery","title":"Начните заготовку","hint":"Доставьте рабочими 10 древесины.","reward":35},
	{"id":"industry","title":"Наладьте производство","hint":"Достройте лесопилку и шахту.","reward":60},
	{"id":"food","title":"Обеспечьте стол","hint":"Доставьте с фермы 5 еды.","reward":45},
	{"id":"people","title":"Поселение растёт","hint":"Постройте жильё и наймите до 5 рабочих.","reward":60},
	{"id":"defense","title":"Первый рубеж","hint":"Отразите два набега.","reward":100}
]

static func initialize(data:Dictionary,catalog):
	var next=1
	for b in data.buildings:
		var def=catalog.building(b.id)
		if not b.has("uid"):b.uid=next
		next=maxi(next,int(b.uid)+1)
		if not b.has("built"):b.built=true
		if not b.has("target_level"):b.target_level=int(b.level)
		if not b.has("work_done"):b.work_done=float(def.work)*int(b.level) if b.built else 0.0
		if not b.has("hp"):b.hp=float(def.hp)*int(b.level)
		if not b.has("width"):b.width=1
		if not b.has("height"):b.height=1
		if not b.has("paid_wood"):b.paid_wood=0
		if not b.has("paid_stone"):b.paid_stone=0
	data["next_building_uid"]=maxi(next,int(data.get("next_building_uid",1)))
	data["construction_first"]=data.get("construction_first",true)
	data["achieved"]=data.get("achieved",[])
	data["stats"]=data.get("stats",{"wood_delivered":0,"stone_delivered":0,"food_delivered":0})
	if not data.world.has("food_clock"):data.world.food_clock=0.0
	for w in data.world.workers:
		if not w.has("name"):w.name=NAMES[int(w.id)%NAMES.size()]
		if not w.has("preference"):w.preference="auto"
		if not w.has("workplace"):w.workplace=0
		if not w.has("returning"):w.returning=false
	if not data.research.has("agriculture"):data.research.agriculture=false
	var combat=data.world.get("combat",{})
	if not combat.is_empty():
		var next_uid=0
		for unit in combat.units:
			if not unit.has("uid"):unit.uid=next_uid
			next_uid=maxi(next_uid,int(unit.uid)+1)
		if not combat.has("next_uid"):combat.next_uid=next_uid

static func rect(b:Dictionary)->Rect2i:return Rect2i(int(b.x),int(b.y),int(b.width),int(b.height))

static func valid(data:Dictionary,catalog)->bool:
	if not data.get("construction_first") is bool or not data.get("achieved") is Array or not data.get("stats") is Dictionary:return false
	if data.achieved.size()>GOALS.size():return false
	var goal_ids=[]
	for g in GOALS:goal_ids.append(g.id)
	var seen_goals={}
	for id in data.achieved:
		if id not in goal_ids or seen_goals.has(id):return false
		seen_goals[id]=true
	for key in ["wood_delivered","stone_delivered","food_delivered"]:
		if not integer(data.stats.get(key)) or data.stats[key]<0 or data.stats[key]>10000000:return false
	var ids={};var cells={};var maximum=0
	for b in data.buildings:
		for key in ["uid","width","height","paid_wood","paid_stone","target_level"]:
			if not integer(b.get(key)):return false
		if b.uid<=0 or ids.has(int(b.uid)) or b.width<1 or b.width>2 or b.height<1 or b.height>2 or b.paid_wood<0 or b.paid_stone<0:return false
		ids[int(b.uid)]=true;maximum=maxi(maximum,int(b.uid))
		if not b.get("built") is bool or not number(b.get("work_done")) or not number(b.get("hp")):return false
		if b.target_level<b.level or b.target_level>3:return false
		if b.work_done<0 or b.work_done>catalog.building(b.id).work*3+0.01 or b.hp<=0 or b.hp>catalog.building(b.id).hp*3:return false
		for x in range(int(b.x),int(b.x+b.width)):
			for y in range(int(b.y),int(b.y+b.height)):
				var key=Vector2i(x,y)
				if x<0 or x>=32 or y<0 or y>=22 or cells.has(key):return false
				cells[key]=true
	if not integer(data.get("next_building_uid")) or data.next_building_uid<=maximum:return false
	var worker_ids={}
	for w in data.world.workers:
		if not integer(w.id) or worker_ids.has(int(w.id)) or w.id<0:return false
		worker_ids[int(w.id)]=true
		if not w.get("name") is String or w.name.length()>40 or w.get("preference") not in PREFERENCES:return false
		if not integer(w.get("workplace")) or w.workplace<0 or not w.get("returning") is bool:return false
	return number(data.world.get("food_clock")) and data.world.food_clock>=0 and data.world.food_clock<60.01

static func number(v:Variant)->bool:return (v is int or v is float) and is_finite(float(v))
static func integer(v:Variant)->bool:return number(v) and float(v)==int(v)

static func goal_done(id:String,state)->bool:
	match id:
		"delivery":return state.data.stats.wood_delivered>=10
		"industry":return state.level("lumber")>0 and state.level("mine")>0
		"food":return state.data.stats.food_delivered>=5
		"people":return state.data.world.workers.size()>=5 and state.level("house")>0
		"defense":return state.data.world.raids_defeated>=2
	return false
