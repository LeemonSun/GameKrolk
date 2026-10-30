extends SceneTree
const Atlas=preload("res://scripts/atlas.gd")
const Chunks=preload("res://scripts/terrain_chunks.gd")
var checks=0
var failures=0
func check(ok:bool,message:String):
	checks+=1
	if not ok:failures+=1;push_error(message)
func _initialize():call_deferred("run")
func run():
	var reports=[]
	for value in [1,5,11,20261029]:
		var atlas=Atlas.new();atlas.build(value)
		var roots=0;var river_count=0;var land=0;var consistent=true
		for i in atlas.side*atlas.side:
			if atlas.biomes[i]>=2:land+=1
			if atlas.rivers[i]!=0:river_count+=1
			if atlas.flow[i]<0:roots+=atlas.accumulation[i]
			else:
				var receiver=atlas.flow[i]
				consistent=consistent and atlas.filled[receiver]<atlas.filled[i] and atlas.accumulation[receiver]>=atlas.accumulation[i]
				if atlas.rivers[i]!=0:consistent=consistent and (atlas.rivers[receiver]!=0 or atlas.biomes[receiver]<2)
		check(consistent,"drainage is downhill and every river reaches another river or water")
		check(roots==atlas.side*atlas.side,"catchments conserve total rainfall")
		check(atlas.land(atlas.home) and not atlas.river(atlas.home),"home is inland and outside river")
		check(land>1000 and land<atlas.side*atlas.side-100 and river_count>10,"seed has usable land, water and river network")
		var twin=Atlas.new();twin.build(value)
		check(atlas.heights==twin.heights and atlas.flow==twin.flow and atlas.biomes==twin.biomes,"same seed reproduces complete geographic fields")
		var chunks=Chunks.new(atlas);var point=atlas.home+Vector2i(2,1);var initial=chunks.get_chunk(point).duplicate(true)
		for x in range(12):chunks.get_chunk(Vector2i(x+5,8))
		check(chunks.cache.size()<=Chunks.LIMIT,"detailed chunk cache remains bounded")
		check(chunks.get_chunk(point)==initial,"eviction and revisit do not regenerate different resources")
		var other=Chunks.new(atlas);other.get_chunk(Vector2i(6,8))
		check(other.get_chunk(point)==initial,"chunk contents are independent of exploration order")
		var valid=true;var seen={}
		for source in initial.sources:
			valid=valid and source.amount>0 and source.amount<=80 and not seen.has(source.id) and initial.tiles[int(source.y)*32+int(source.x)]==0
			seen[source.id]=true
		check(valid and initial.tiles.size()==704,"detailed sources occupy land and use stable unique tile identities")
		var wet=true;var river_samples=0
		for i in atlas.side*atlas.side:
			if atlas.rivers[i]==0 or atlas.flow[i]<0:continue
			var destination=atlas.flow[i]
			var start=Vector2(i%atlas.side,i/atlas.side)+Vector2.ONE*0.5
			var end=Vector2(destination%atlas.side,destination/atlas.side)+Vector2.ONE*0.5
			for t in [0.0,0.25,0.49,0.50,0.51,0.75,1.0]:
				var sample=start.lerp(end,t)*Vector2(32,22)
				wet=wet and chunks.cell(Vector2i(roundi(sample.x),roundi(sample.y))).water;river_samples+=1
		check(wet and river_samples>100,"detailed river beds stay wet across diagonal borders and estuaries")
		reports.append({"seed":value,"land":land,"rivers":river_count,"generation_ms":atlas.elapsed_ms,"resident_chunks":chunks.cache.size()})
	print("ATLAS_TESTS "+JSON.stringify({"checks":checks,"failures":failures,"reports":reports}))
	quit(1 if failures else 0)
