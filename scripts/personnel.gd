extends RefCounted

const POSTS={"commander":"Командующий","quartermaster":"Снабженец","medic":"Лекарь"}
const SKILLS=["command","logistics","medicine","build","wood","stone","farm"]
const SKILL_NAMES={"command":"Командование","logistics":"Снабжение","medicine":"Лечение","build":"Строительство","wood":"Лесное дело","stone":"Добыча","farm":"Земледелие"}

static func initialize(data:Dictionary):
	if not data.has("personnel"):
		data.personnel={"posts":{"commander":-1,"quartermaster":-1,"medic":-1},"wounded":{"militia":0,"archer":0,"guard":0},"treatment":0.0,"treated":0,"lost":0,"auto_treat":true}
	if not data.personnel.has("last_report"):data.personnel.last_report="Нападений пока не было."
	for worker in data.world.workers:initialize_worker(worker)
	# Legacy functional appointments become real appointments when possible.
	for post in ["commander","quartermaster"]:
		if data.officers[post] and int(data.personnel.posts[post])<0:
			for worker in data.world.workers:
				if worker.post.is_empty():worker.post=post;data.personnel.posts[post]=int(worker.id);break
			if int(data.personnel.posts[post])<0:data.officers[post]=false

static func initialize_worker(worker:Dictionary):
	if not worker.has("post"):worker.post=""
	if not worker.has("at_post"):worker.at_post=false
	if not worker.has("skills"):
		worker.skills={}
		for skill in SKILLS:worker.skills[skill]=1
		worker.skills[["command","wood","medicine","stone","farm","build","logistics"][int(worker.id)%7]]=3
	if not worker.has("practice"):
		worker.practice={}
		for skill in SKILLS:worker.practice[skill]=(int(worker.skills[skill])-1)*50

static func worker(data:Dictionary,id:int)->Dictionary:
	for person in data.world.workers:
		if int(person.id)==id:return person
	return {}

static func holder(data:Dictionary,post:String)->Dictionary:
	return worker(data,int(data.personnel.posts.get(post,-1)))

static func ready(data:Dictionary,post:String)->bool:
	var person=holder(data,post)
	if person.is_empty() or person.carry!=0 or person.job!="idle" or person.returning or not person.at_post:return false
	for building in data.buildings:
		if building.built and building.id==("infirmary" if post=="medic" else "hq"):return true
	return false

static func practice(person:Dictionary,skill:String,amount:int=1):
	person.practice[skill]=mini(1000000,int(person.practice[skill])+amount)
	person.skills[skill]=mini(5,maxi(int(person.skills[skill]),1+int(person.practice[skill])/50))

static func valid(data:Dictionary)->bool:
	var p=data.get("personnel")
	if not p is Dictionary or not p.get("posts") is Dictionary or not p.get("wounded") is Dictionary:return false
	if p.posts.size()!=POSTS.size() or p.wounded.size()!=3:return false
	for key in ["treated","lost"]:
		if not integer(p.get(key)) or p[key]<0 or p[key]>10000000:return false
	if not p.get("auto_treat") is bool or not number(p.get("treatment")) or p.treatment<0 or p.treatment>30.01:return false
	if not p.get("last_report") is String or p.last_report.length()>1000:return false
	for kind in ["militia","archer","guard"]:
		if not integer(p.wounded.get(kind)) or p.wounded[kind]<0 or p.wounded[kind]>10000:return false
	var appointments={}
	for post in POSTS:
		var id=p.posts.get(post)
		if not integer(id) or id< -1 or id>10000000:return false
		if id>=0:
			var person=worker(data,int(id))
			if person.is_empty() or person.get("post")!=post or appointments.has(int(id)):return false
			appointments[int(id)]=post
		if post in data.officers and bool(data.officers[post])!=(id>=0):return false
	for person in data.world.workers:
		if not person.get("at_post") is bool or (person.at_post and person.get("post","").is_empty()):return false
		if not person.get("post") is String or (not person.post.is_empty() and person.post not in POSTS):return false
		if not person.post.is_empty() and p.posts[person.post]!=person.id:return false
		for map in [person.get("skills"),person.get("practice")]:
			if not map is Dictionary or map.size()!=SKILLS.size():return false
		for skill in SKILLS:
			if not integer(person.skills.get(skill)) or person.skills[skill]<1 or person.skills[skill]>5:return false
			if not integer(person.practice.get(skill)) or person.practice[skill]<0 or person.practice[skill]>1000000:return false
	return true

static func casualties(data:Dictionary,before:Dictionary,after:Dictionary)->Dictionary:
	var result={"wounded":0,"lost":0}
	for kind in ["militia","archer","guard"]:
		var missing=maxi(0,int(before[kind])-int(after[kind]))
		var recoverable=missing/2
		data.personnel.wounded[kind]+=recoverable;data.personnel.lost+=missing-recoverable
		result.wounded+=recoverable;result.lost+=missing-recoverable
	return result

static func treatment_reason(state)->String:
	if not state.data.personnel.auto_treat:return "Лечение приостановлено."
	if state.data.world.raid_active:return "Лазарет ждёт окончания нападения."
	if state.level("infirmary")==0:return "Нужен достроенный лазарет."
	if not ready(state.data,"medic"):return "Назначьте свободного лекаря; занятый человек сначала доставит груз."
	var total=0
	for amount in state.data.personnel.wounded.values():total+=int(amount)
	if total==0:return "Раненых нет."
	if state.army_total()>=state.capacity():return "Нет места для возвращения бойца. Места походного отряда зарезервированы."
	if state.data.coins<3 or state.data.food<2:return "На бойца нужно 3 монеты и 2 провианта."
	return ""

static func treatment_seconds(state)->float:
	var medic=holder(state.data,"medic")
	return 30.0/(1.0+0.15*(int(medic.get("skills",{}).get("medicine",1))-1)+0.1*maxi(0,state.level("infirmary")-1))

static func tick(state,dt:float)->String:
	if not treatment_reason(state).is_empty():return ""
	var p=state.data.personnel;p.treatment+=dt
	if p.treatment+0.000001<treatment_seconds(state):return ""
	p.treatment=0.0
	for kind in ["guard","archer","militia"]:
		if p.wounded[kind]<=0:continue
		state.data.coins-=3;state.data.food-=2;p.wounded[kind]-=1;state.data.army[kind]+=1;p.treated+=1
		practice(holder(state.data,"medic"),"medicine")
		return "Лазарет: в строй вернулся "+state.catalog.troop(kind).name+". Потрачено 3 монеты и 2 провианта."
	return ""

static func number(v:Variant)->bool:return (v is int or v is float) and is_finite(v)
static func integer(v:Variant)->bool:return number(v) and float(v)==int(v)
