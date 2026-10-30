extends RefCounted

# Local contracts, not a simulation of canonical factions or a global market.
const OFFERS={
	"wood_export":{"name":"Поставка древесины","take":"wood","amount":20,"give":"coins","reward":26},
	"stone_export":{"name":"Поставка камня","take":"stone","amount":15,"give":"coins","reward":25},
	"food_export":{"name":"Поставка провианта","take":"food","amount":10,"give":"coins","reward":22},
	"stone_import":{"name":"Привезти камень","take":"coins","amount":30,"give":"stone","reward":15},
	"wood_import":{"name":"Привезти древесину","take":"coins","amount":28,"give":"wood","reward":20}
}
static func initialize(data:Dictionary):
	if not data.has("commerce"):data.commerce={"cargo":{},"window":0.0,"orders":0,"income":0,"used":[],"completed":0}

static func valid(data:Dictionary)->bool:
	var c=data.get("commerce")
	if not c is Dictionary:return false
	for key in ["window","orders","income","completed"]:
		var v=c.get(key)
		if not (v is int or v is float) or not is_finite(v) or v<0 or v>10000000:return false
		if key!="window" and float(v)!=int(v):return false
	if c.window>=180.01 or not c.get("used") is Array or c.used.size()>OFFERS.size():return false
	var seen={}
	for id in c.used:
		if id not in OFFERS or seen.has(id):return false
		seen[id]=true
	if not c.get("cargo") is Dictionary:return false
	if not c.cargo.is_empty():
		if c.cargo.get("id") not in OFFERS:return false
		var time=c.cargo.get("remaining")
		if not (time is float or time is int) or not is_finite(time) or time<0 or time>35:return false
	return true

static func reason(state,id:String)->String:
	if id not in OFFERS:return "Неизвестная поставка."
	if state.data.world.raid_active:return "Отгрузка недоступна во время нападения."
	if not state.data.commerce.cargo.is_empty():return "Дождитесь возвращения текущей поставки."
	if id in state.data.commerce.used:return "Этот заказ выполнен в текущем торговом окне."
	var offer=OFFERS[id]
	if state.data[offer.take]<offer.amount:return "Недостаточно запаса для поставки."
	return ""

static func send(state,id:String)->String:
	var error=reason(state,id)
	if not error.is_empty():return error
	var offer=OFFERS[id];state.data[offer.take]-=int(offer.amount)
	state.data.commerce.cargo={"id":id,"remaining":35.0};state.data.commerce.used.append(id)
	state.save_progress();return "Поставка отправлена. Возвращение через 35 игровых секунд; во время нападения разгрузка ждёт."

static func tick(state,dt:float)->String:
	var c=state.data.commerce;c.window+=dt
	if c.window>=180:c.window-=180;c.used.clear()
	if c.cargo.is_empty():return ""
	c.cargo.remaining=maxf(0,float(c.cargo.remaining)-dt)
	if c.cargo.remaining>0 or state.data.world.raid_active:return ""
	var offer=OFFERS[c.cargo.id]
	state.data[offer.give]+=int(offer.reward);c.completed+=1
	if offer.give=="coins":c.orders+=1;c.income+=int(offer.reward)
	c.cargo={}
	return "%s: получено %d %s."%[offer.name,offer.reward,{"wood":"дерева","stone":"камня","coins":"монет"}.get(offer.give,offer.give)]
