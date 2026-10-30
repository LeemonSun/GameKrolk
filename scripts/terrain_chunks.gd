extends RefCounted

const WIDTH=32
const HEIGHT=22
const LIMIT=9
var atlas
var noise=FastNoiseLite.new()
var cache={}
var recent=[]
var generation_count=0

func _init(source):
	atlas=source;noise.seed=atlas.seed_value^0x7247;noise.frequency=0.09;noise.fractal_octaves=3

func cell(global:Vector2i)->Dictionary:
	var region=Vector2i(floori(float(global.x)/WIDTH),floori(float(global.y)/HEIGHT))
	if not atlas.inside(region):return {"water":true,"height":0.0,"biome":0}
	var index=atlas.index(region);var point=Vector2(float(global.x)/WIDTH,float(global.y)/HEIGHT)
	var local=point-Vector2(region);var height=_height(point)+noise.get_noise_2d(global.x,global.y)*0.018
	var water=height<=atlas.SEA
	if _field(point,atlas.filled)-height>0.035:water=true
	# Sample the same outgoing segments from all neighboring regions. This also
	# covers diagonal corners and estuaries whose receiving sea region has no river flag.
	for offset_y in range(-1,2):
		for offset_x in range(-1,2):
			var origin=region+Vector2i(offset_x,offset_y)
			if not atlas.inside(origin):continue
			var other=atlas.index(origin);var next=atlas.flow[other]
			if atlas.rivers[other]==0 or next<0:continue
			var start=Vector2(origin)+Vector2.ONE*0.5
			var destination=Vector2(next%atlas.side,next/atlas.side)+Vector2.ONE*0.5
			var width=0.035+minf(0.10,sqrt(float(atlas.accumulation[other]))*0.002)
			if Geometry2D.get_closest_point_to_segment(point,start,destination).distance_to(point)<width:water=true
	var moisture=_field(point,atlas.moisture);var biome=2
	if height>0.72:biome=6
	elif height>0.59:biome=5
	elif point.y/atlas.side<0.15:biome=7
	elif moisture<0.37:biome=4
	elif moisture>0.54:biome=3
	return {"water":water,"height":height,"biome":biome,"local":local}

func _height(point:Vector2)->float:
	return _field(point,atlas.heights)

func _field(point:Vector2,values:PackedFloat32Array)->float:
	point=(point-Vector2.ONE*0.5).clamp(Vector2.ZERO,Vector2.ONE*(atlas.side-1))
	var a=Vector2i(floori(point.x),floori(point.y));var b=Vector2i(mini(a.x+1,atlas.side-1),mini(a.y+1,atlas.side-1))
	var fraction=point-Vector2(a)
	return lerpf(lerpf(values[atlas.index(a)],values[atlas.index(Vector2i(b.x,a.y))],fraction.x),lerpf(values[atlas.index(Vector2i(a.x,b.y))],values[atlas.index(b)],fraction.x),fraction.y)

func get_chunk(point:Vector2i)->Dictionary:
	if not atlas.inside(point):return {}
	var key="%d:%d"%[point.x,point.y]
	if cache.has(key):recent.erase(key);recent.append(key);return cache[key]
	var tiles=[];var sources=[];var heights=PackedFloat32Array();var biomes=PackedByteArray()
	for y in HEIGHT:
		for x in WIDTH:
			var global=Vector2i(point.x*WIDTH+x,point.y*HEIGHT+y);var sample=cell(global)
			tiles.append(1 if sample.water else 0)
			heights.append(sample.height);biomes.append(sample.biome)
			if sample.water:continue
			var value=_hash(global.x,global.y)
			var density=230 if sample.biome==3 else (65 if sample.biome==4 else 120)
			if value%1000<density:
				var kind="stone" if sample.biome in [5,6] or (value/1000)%5==0 else "wood"
				sources.append({"id":y*WIDTH+x,"x":x,"y":y,"kind":kind,"amount":24+value%57})
	var chunk={"x":point.x,"y":point.y,"tiles":tiles,"sources":sources,"heights":heights,"biomes":biomes}
	cache[key]=chunk;recent.append(key);generation_count+=1
	while recent.size()>LIMIT:cache.erase(recent.pop_front())
	return chunk

func prefetch(points:Array):
	# Protect the required existing chunks before inserting new ones. A leftward
	# pan must not evict still-needed neighbors merely because they are visited later.
	for point in points:
		var key="%d:%d"%[point.x,point.y]
		if cache.has(key):recent.erase(key);recent.append(key)
	for point in points:get_chunk(point)

func _hash(x:int,y:int)->int:
	var value=(x*374761393+y*668265263+atlas.seed_value*31)&0x7fffffff
	value=((value^(value>>13))*1274126177)&0x7fffffff
	return (value^(value>>16))&0x7fffffff
