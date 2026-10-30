extends SceneTree
var checks=0
var failures=0
func check(ok:bool,message:String):
	checks+=1
	if not ok:failures+=1;push_error(message)
func capture(path:String):
	await process_frame;await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(path)
func find_button(node:Node,text:String):
	if node is Button and node.text==text:return node
	for child in node.get_children():
		var found=find_button(child,text)
		if found!=null:return found
	return null
func _initialize():call_deferred("run")
func run():
	var app=load("res://scenes/main.tscn").instantiate();root.add_child(app);await process_frame
	app.state.data.world.raid_in=9999;root.size=Vector2i(1440,900)
	find_button(app.toolbar,"Мир").pressed.emit();await process_frame
	check(app.tab=="map" and app.map_view.visible and not app.base.visible,"world tab opens real world stage")
	check(app.world.regional.ready and app.map_view.texture!=null,"map has generated actual geography")
	await capture("res://work/ui-atlas-v8.png")
	var map=app.map_view;var model=app.world.regional
	var target=model.home()+Vector2i.LEFT
	var event=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
	event.position=map.map_rect().position+(Vector2(target)+Vector2.ONE*0.5)*(map.map_rect().size.x/128)
	map._gui_input(event);await process_frame
	check(map.selected==target,"map mouse click selects exact world coordinate")
	var scale_before=map.zoom;event.button_index=MOUSE_BUTTON_WHEEL_UP;map._gui_input(event)
	check(map.zoom>scale_before,"world zoom responds at pointer")
	find_button(app.sidebar,"Область").pressed.emit();await process_frame
	check(map.mode=="region","region control opens detailed chunk")
	find_button(app.sidebar,"→").pressed.emit();await process_frame
	check(map.selected==model.home(),"neighbor browsing reaches preserved home chunk")
	root.size=Vector2i(1152,720);await capture("res://work/ui-region-home-v8.png")
	find_button(app.sidebar,"Окрестности").pressed.emit();await capture("res://work/ui-nearby-v8.png")
	check(map.mode=="nearby" and map.nearby_texture!=null and model.chunks.cache.size()<=9,"nearby view prepares at most nine detailed chunks")
	var generations=model.chunks.generation_count
	find_button(app.sidebar,"←").pressed.emit();await process_frame
	check(model.chunks.generation_count-generations<=3,"moving neighboring view reuses shared chunks without eviction churn")
	var near_event=InputEventMouseButton.new();near_event.button_index=MOUSE_BUTTON_LEFT;near_event.pressed=true
	near_event.position=map.nearby_rect().position+map.nearby_rect().size*Vector2(5.0/6.0,0.5)
	map._gui_input(near_event);await process_frame
	check(map.selected==model.home(),"clicking neighboring region recenters streamed view")
	find_button(app.sidebar,"Карта мира").pressed.emit();await process_frame
	for d in model.atlas.DIRS:
		var p=model.home()+d
		if model.atlas.land(p) and not model.route(p).is_empty():map.selected=p;break
	app._refresh();find_button(app.sidebar,"Разведать область").pressed.emit();await process_frame
	check(not app.state.data.regional.expedition.is_empty(),"actual scout button dispatches crew")
	check(find_button(app.sidebar,"Отозвать отряд")!=null,"recall becomes available while away")
	for i in 660:app.world.step(1.0/30.0)
	app._refresh();check(app.state.data.regional.expedition.is_empty() and model.known(map.selected),"world screen refreshes after real scouting and return")
	find_button(app.sidebar,"Область").pressed.emit();await capture("res://work/ui-region-scouted-v8.png")
	check(app.state.save_progress(),"world UI session saves valid progress")
	app._set_tab("build");check(app.base.visible and not map.visible,"return to construction preserves normal stage")
	var previous_path=app.state.save_path;var previous_text=FileAccess.get_file_as_string(previous_path);var old_texture=map.texture
	app._new_party(314159,"calm","Another atlas")
	check(map.model==null and not map.visible and app.state.data.regional.known.is_empty(),"new party drops previous geography and exploration view")
	find_button(app.toolbar,"Мир").pressed.emit();await process_frame
	check(map.texture!=old_texture and map.model.atlas.seed_value==314159 and FileAccess.get_file_as_string(previous_path)==previous_text,"new world builds own atlas without overwriting previous party")
	print("ATLAS_UI_TESTS "+JSON.stringify({"checks":checks,"failures":failures,"cache":model.chunks.cache.size()}));quit(1 if failures else 0)
