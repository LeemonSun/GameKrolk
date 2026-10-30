extends SceneTree
const Atlas=preload("res://scripts/atlas.gd")
const Chunks=preload("res://scripts/terrain_chunks.gd")
func _initialize():call_deferred("run")
func measure(side:int)->Dictionary:
	var before=Performance.get_monitor(Performance.MEMORY_STATIC)
	var atlas=Atlas.new();atlas.build(20261029,side)
	var geographic_memory=Performance.get_monitor(Performance.MEMORY_STATIC)-before
	var chunks=Chunks.new(atlas);var samples=[]
	for x in 40:
		var start=Time.get_ticks_usec();chunks.get_chunk(Vector2i(side/2+x-20,side/2));samples.append((Time.get_ticks_usec()-start)/1000.0)
	samples.sort();var total=0.0
	for sample in samples:total+=sample
	var resident_memory=Performance.get_monitor(Performance.MEMORY_STATIC)-before
	return {"side":side,"regions":side*side,"potential_tiles":side*side*704,"atlas_ms":atlas.elapsed_ms,"atlas_retained_bytes":geographic_memory,"atlas_plus_nine_chunks_bytes":resident_memory,"chunk_mean_ms":total/samples.size(),"chunk_p95_ms":samples[int(samples.size()*0.95)-1],"chunks":chunks.cache.size()}
func run():
	var result=[]
	for side in [128,256,512]:result.append(measure(side))
	var file=FileAccess.open("res://work/atlas-benchmark.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("ATLAS_BENCHMARK "+JSON.stringify(result));quit()
