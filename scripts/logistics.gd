extends RefCounted

# Stocks are shared by the settlement. Depots provide capacity and physical
# unloading points; this is not a separate inventory per building.
const BASE={"wood":240,"stone":160,"food":40}
const PER_LEVEL={"wood":180,"stone":140,"food":60}

static func capacity(data:Dictionary,kind:String)->int:
	var result=int(BASE.get(kind,0))
	for b in data.buildings:
		if b.id=="warehouse" and b.built:result+=int(PER_LEVEL.get(kind,0))*int(b.level)
	return result

static func room(data:Dictionary,kind:String)->int:
	return maxi(0,capacity(data,kind)-int(data[kind]))

static func solid(b:Dictionary)->bool:
	return not (b.id=="gate" and b.built and b.get("gate_open",false))

static func repair_quote(b:Dictionary,current:float,maximum:float,catalog)->Dictionary:
	if not b.built or b.target_level!=b.level or not b.get("repair",{}).is_empty() or maximum-current<0.001:return {}
	var def=catalog.building(b.id);var missing=maximum-current;var fraction=missing/maximum
	return {"wood":maxi(1,ceili(float(def.wood)*int(b.level)*0.5*fraction)),
		"stone":ceili(float(def.stone)*int(b.level)*0.5*fraction),
		"remaining":missing,"total":missing,"rate":missing/maxf(2.0,float(def.work)*int(b.level)*fraction)}

static func refund(repair:Dictionary)->Dictionary:
	if repair.is_empty():return {"wood":0,"stone":0}
	return {"wood":floori(float(repair.wood)*repair.remaining/repair.total),"stone":floori(float(repair.stone)*repair.remaining/repair.total)}
