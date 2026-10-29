extends Control

signal ended(won:bool)
signal notice(text:String)
const Battle=preload("res://scripts/battle.gd")
const Art=preload("res://scripts/art.gd")
var battle=Battle.new()
var running=false
var paused=false
var speed=1.0
var group="all"
var accumulator=0.0
var reported=false
var frame_samples:Array=[]
var last_ms=0
var automatic_skill=false

func _ready():mouse_filter=Control.MOUSE_FILTER_STOP

func start(config:Dictionary):
	battle.start(config);running=true;paused=false;reported=false;accumulator=0;frame_samples.clear();automatic_skill=false;queue_redraw()

func field_rect()->Rect2:
	var factor=minf(size.x/1000.0,size.y/600.0)
	return Rect2((size-Vector2(1000,600)*factor)*0.5,Vector2(1000,600)*factor)

func _gui_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT and running:
		var rect=field_rect()
		if rect.has_point(event.position):battle.order(group,(event.position-rect.position)/(rect.size.x/1000.0));accept_event()

func _process(dt):
	if running and not paused and not battle.finished:
		var begin=Time.get_ticks_usec()
		accumulator+=minf(dt,0.15)*speed
		var steps=0
		while accumulator>=1.0/30.0 and steps<6:
			battle.step(1.0/30.0);accumulator-=1.0/30.0;steps+=1
			if automatic_skill and battle.can_auto_skill():battle.skill()
			if battle.finished:break
		if frame_samples.size()<20000:frame_samples.append(float(Time.get_ticks_usec()-begin)/1000.0)
		battle.events.clear()
	if running and battle.finished and not reported:
		reported=true
		print("BATTLE_RESULT "+JSON.stringify({"won":battle.won,"mode":battle.mode,"seconds":battle.time,"enemies":battle.total_enemies,"kills":battle.kills,"simulation_p95_ms":p95(),"skills":battle.skill_casts}))
		ended.emit(battle.won)
	queue_redraw()

func p95()->float:
	if frame_samples.is_empty():return 0
	var samples=frame_samples.duplicate();samples.sort();return samples[mini(samples.size()-1,int(samples.size()*0.95))]

func cast():
	if paused:notice.emit("Снимите паузу, чтобы применить технику.");return
	notice.emit(battle.skill())

func _draw():
	draw_rect(Rect2(Vector2.ZERO,size),Color("263b35"))
	var rect=field_rect();var factor=rect.size.x/1000.0
	draw_set_transform(rect.position,0,Vector2.ONE*factor)
	draw_rect(Rect2(0,0,1000,600),Color("34483b"))
	for i in 100:
		var p=Vector2(fmod(i*113.3,970)+10,fmod(i*67.7,570)+15)
		draw_line(p,p+Vector2(3,-4),Color("445640"),2)
	draw_rect(Rect2(60,245,880,110),Color("5c614a"))
	for y in [205,390]:
		for x in range(130,920,85):draw_rect(Rect2(x,y,44,3),Color("45523d"))
	for y in [55,125,195,415,485,555]:
		draw_rect(Rect2(51,y-16,28,35),Color("6d7969"));draw_rect(Rect2(48,y-20,34,10),Color("9a9f87"))
	Art.building(self,rect.position+Vector2(72,300)*factor,"hq",1,false,factor)
	# Drawing helpers reset the transform; restore field coordinates afterward.
	draw_set_transform(rect.position,0,Vector2.ONE*factor)
	if not running:
		draw_set_transform(Vector2.ZERO);return
	for trace in battle.traces:
		draw_line(trace.a,trace.b,Color(0.95,0.55,0.6,0.22),2)
	var ordered=battle.units.duplicate();ordered.sort_custom(func(a,b):return a.pos.y<b.pos.y)
	var alpha=clampf(accumulator/(1.0/30.0),0,1) if not paused else 1.0
	var hero_color=Color(battle.catalog.hero(battle.hero_kind).color)
	for u in ordered:
		if u.hp<=0 and battle.time-u.died>14:continue
		var p:Vector2=u.prev.lerp(u.pos,alpha)
		if u.kind=="hero" and u.hp>0:
			draw_arc(p+Vector2(0,3),22,0,TAU,28,Color("e4c68a"),2)
		var phase=battle.time*10+u.id if u.moving else 0
		var attack=1.0-u.attack_left/u.windup if u.attack_left>0 and u.windup>0 else 0.0
		# Helpers take screen coordinates. Restore scale around each compact sprite.
		draw_set_transform(rect.position,0,Vector2.ONE*factor)
		_draw_person_scaled(p,u,phase,attack,hero_color,rect,factor)
		draw_set_transform(rect.position,0,Vector2.ONE*factor)
		if u.hp>0 and (u.hp<u.max_hp or u.kind=="hero"):
			var w=34.0 if u.kind=="hero" else 15.0
			draw_rect(Rect2(p.x-w/2,p.y-39 if u.kind=="hero" else p.y-25,w,3),Color("1d2827"))
			draw_rect(Rect2(p.x-w/2,p.y-39 if u.kind=="hero" else p.y-25,w*u.hp/u.max_hp,3),Color("b4cf9b") if u.team==0 else Color("d18b77"))
	for p in battle.projectiles:
		var dir=(p.to-p.pos).normalized();draw_line(p.pos-dir*9,p.pos,Color("ead9b4"),2)
	for effect in battle.effects:
		var age=effect.age/effect.life;var color:Color=effect.color;color.a=1-age
		if effect.type=="moon":
			draw_line(effect.a,effect.b,color,7*(1-age)+1)
			draw_line(effect.a,effect.b,Color(1,0.9,0.85,(1-age)*0.8),2)
		elif effect.type=="slash":
			var angle=effect.get("dir",Vector2.RIGHT).angle()
			draw_arc(effect.pos,effect.radius+age*7,angle-1.3+age,angle+1.1+age,14,color,3*(1-age)+1)
		elif effect.type=="pulse":
			draw_circle(effect.pos,effect.radius*age,Color(color,0.12*(1-age)))
			draw_arc(effect.pos,effect.radius*age,0,TAU,60,color,3)
		else:
			draw_arc(effect.pos,effect.radius*(0.5+age),0,TAU,16,color,2)
	draw_set_transform(Vector2.ZERO)

func _draw_person_scaled(p:Vector2,u:Dictionary,phase:float,attack:float,color:Color,rect:Rect2,factor:float):
	# A nested draw transform cannot be stacked in CanvasItem; use a helper transform.
	# The 1000x600 field is close to native scale. Sprites stay pixel readable when resized.
	Art.person(self,rect.position+p*factor,u.kind,int(u.team),phase,u.facing,attack,float(u.flash),color,u.hp<=0,factor)
