extends Control

const State=preload("res://scripts/state.gd")
const BaseView=preload("res://scripts/world_view.gd")
const World=preload("res://scripts/world.gd")
const BattleView=preload("res://scripts/battle_view.gd")
const BG=Color("101b1c")
const PANEL=Color("192827")
const GOLD=Color("d6bc84")
const INK=Color("e5e5cd")
const MUTED=Color("a7b4a8")
var state
var world
var base
var combat
var sidebar:VBoxContainer
var resources:Label
var title:Label
var subtitle:Label
var toast:Label
var battle_stats:Label
var skill_button:Button
var content:HBoxContainer
var root:VBoxContainer
var toolbar:HBoxContainer
var tab="build"
var selected_building=-1
var placement=""
var in_battle=false
var toast_time=0.0
var result_dialog:AcceptDialog
var retreat_dialog:ConfirmationDialog
var ui_clock=0.0
var benchmark_mode=false
var selected_source=-1
var autosave_clock=0.0

func _ready():
	Engine.max_fps=60
	var test_profile="user://progress.json"
	if "--test-mode" in OS.get_cmdline_user_args():test_profile="res://work/test-session.json"
	state=State.new(test_profile);state.load_progress()
	world=World.new(state);world.notice.connect(_notice);world.raid_finished.connect(func(_won):_refresh())
	_setup_theme();_setup_ui();_refresh()
	if not state.warning.is_empty():_notice(state.warning,15)
	print("GAMEKROLK_READY "+JSON.stringify({"version":"0.0.2","save":ProjectSettings.globalize_path(state.save_path),"renderer":RenderingServer.get_current_rendering_method()}))

func _style(color:Color,border:Color=Color.TRANSPARENT,radius:int=10)->StyleBoxFlat:
	var s=StyleBoxFlat.new();s.bg_color=color
	s.set_corner_radius_all(radius);s.set_border_width_all(1);s.border_color=border
	s.content_margin_left=14;s.content_margin_right=14;s.content_margin_top=10;s.content_margin_bottom=10
	return s

func _setup_theme():
	theme=Theme.new();theme.default_font_size=16
	var font=SystemFont.new();font.font_names=PackedStringArray(["Segoe UI","Noto Sans"]);theme.default_font=font
	theme.set_color("font_color","Label",INK)
	theme.set_color("font_color","Button",INK);theme.set_color("font_hover_color","Button",Color.WHITE)
	theme.set_color("font_disabled_color","Button",Color("6c7972"))
	theme.set_stylebox("normal","Button",_style(Color("263a35"),Color("3a4e43"),7))
	theme.set_stylebox("hover","Button",_style(Color("354a3b"),GOLD,7))
	theme.set_stylebox("pressed","Button",_style(Color("4c5440"),GOLD,7))
	theme.set_stylebox("focus","Button",_style(Color(0,0,0,0),GOLD,7))
	theme.set_stylebox("disabled","Button",_style(Color("202d29"),Color("2d3930"),7))
	theme.set_stylebox("panel","PanelContainer",_style(PANEL,Color("344238"),12))
	theme.set_stylebox("panel","AcceptDialog",_style(PANEL,GOLD,10))
	theme.set_constant("separation","VBoxContainer",9)
	theme.set_constant("separation","HBoxContainer",10)

func _label(text:String,size_px:int=16,color:Color=INK)->Label:
	var label=Label.new();label.text=text;label.add_theme_font_size_override("font_size",size_px);label.add_theme_color_override("font_color",color)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	return label

func _button(text:String,callback:Callable=Callable(),accent:bool=false)->Button:
	var b=Button.new();b.text=text;b.custom_minimum_size.y=42;b.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	if callback.is_valid():b.pressed.connect(callback)
	if accent:b.add_theme_stylebox_override("normal",_style(Color("746143"),Color("d6bc84"),7))
	return b

func _setup_ui():
	var bg=ColorRect.new();bg.color=BG;bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);bg.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(bg)
	var margin=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right"]:margin.add_theme_constant_override("margin_"+edge,26)
	for edge in ["top","bottom"]:margin.add_theme_constant_override("margin_"+edge,18)
	add_child(margin);root=VBoxContainer.new();root.add_theme_constant_override("separation",13);margin.add_child(root)
	var header=HBoxContainer.new();root.add_child(header)
	var brand=VBoxContainer.new();brand.size_flags_horizontal=Control.SIZE_EXPAND_FILL;brand.add_theme_constant_override("separation",1);header.add_child(brand)
	title=_label("КРОЛИК  /  ЦИТАДЕЛЬ",29,GOLD);brand.add_child(title)
	subtitle=_label("ЖИВОЙ УЧАСТОК    ·    технический прототип 0.0.2    ·    графика временная",12,MUTED);brand.add_child(subtitle)
	header.add_child(_button("Сохранить",func():_notice("Прогресс сохранён." if state.save_progress() else state.warning)))
	header.add_child(_button("Во весь экран  F11",_fullscreen))
	var resource_panel=PanelContainer.new();root.add_child(resource_panel);resources=_label("",17,INK);resource_panel.add_child(resources)
	toolbar=HBoxContainer.new();root.add_child(toolbar)
	content=HBoxContainer.new();content.size_flags_vertical=Control.SIZE_EXPAND_FILL;content.add_theme_constant_override("separation",16);root.add_child(content)
	var stage=PanelContainer.new();stage.size_flags_horizontal=Control.SIZE_EXPAND_FILL;stage.size_flags_vertical=Control.SIZE_EXPAND_FILL;content.add_child(stage)
	var layers=Control.new();layers.custom_minimum_size=Vector2(640,460);layers.size_flags_vertical=Control.SIZE_EXPAND_FILL;layers.size_flags_horizontal=Control.SIZE_EXPAND_FILL;stage.add_child(layers)
	base=BaseView.new();base.state=state;base.world=world;base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);layers.add_child(base);base.cell_clicked.connect(_base_click);base.order_requested.connect(world.order)
	combat=BattleView.new();combat.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);layers.add_child(combat);combat.hide();combat.ended.connect(_battle_ended);combat.notice.connect(_notice)
	var side=PanelContainer.new();side.custom_minimum_size.x=340;content.add_child(side)
	var scroll=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;side.add_child(scroll)
	sidebar=VBoxContainer.new();sidebar.size_flags_horizontal=Control.SIZE_EXPAND_FILL;sidebar.custom_minimum_size.x=300;sidebar.add_theme_constant_override("separation",10);scroll.add_child(sidebar)
	toast=_label("Начните с крепости или испытайте героя на полигоне. Наведите курсор на кнопки для подсказок.",14,MUTED)
	toast.custom_minimum_size.y=42;root.add_child(toast)
	result_dialog=AcceptDialog.new();result_dialog.title="Итог сражения";result_dialog.ok_button_text="Вернуться в крепость";result_dialog.confirmed.connect(_return_base);result_dialog.canceled.connect(_return_base);add_child(result_dialog)
	retreat_dialog=ConfirmationDialog.new();retreat_dialog.title="Отступить?";retreat_dialog.dialog_text="Осада будет засчитана как поражение. Выжившие вернутся; потраченный провиант не возвращается."
	retreat_dialog.ok_button_text="Отступить";retreat_dialog.cancel_button_text="Остаться";retreat_dialog.confirmed.connect(_retreat);add_child(retreat_dialog)
	get_window().close_requested.connect(_close)

func _clear(box:Node):
	for child in box.get_children():box.remove_child(child);child.queue_free()

func _refresh():
	_update_resources();_clear(toolbar);_clear(sidebar)
	if in_battle:_battle_ui();return
	if not state.data.world.raid_active:world.sync_army()
	for entry in [["build","Поселение"],["heroes","Герои"],["army","Армия"],["officers","Должности"],["tech","Технологии"]]:
		var b=_button(entry[1],_set_tab.bind(entry[0]),tab==entry[0]);toolbar.add_child(b)
	var spacer=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;toolbar.add_child(spacer)
	toolbar.add_child(_button("Продолжить" if world.paused else "Пауза  P",_pause_world))
	toolbar.add_child(_button("Полигон",func():_start_battle("hero")))
	toolbar.add_child(_button("Проверить набег",_trigger_raid,true))
	match tab:
		"build":_build_ui()
		"heroes":_heroes_ui()
		"army":_army_ui()
		"officers":_officers_ui()
		"tech":_tech_ui()
	base.selected=selected_building;base.selected_source=selected_source;base.placement=placement;base.queue_redraw()

func _set_tab(value:String):
	tab=value;placement="";base.placement="";_refresh()

func _update_resources():
	var raid="НАБЕГ!" if state.data.world.raid_active else "НАБЕГ ЧЕРЕЗ %02d:%02d"%[int(state.data.world.raid_in)/60,int(state.data.world.raid_in)%60]
	resources.text="МОНЕТЫ %d    ДРЕВЕСИНА %d    КАМЕНЬ %d    ПРОВИАНТ %d    АРМИЯ %d/%d    %s"%[state.data.coins,state.data.wood,state.data.stone,state.data.food,state.army_count(),state.capacity(),raid]

func _heading(text:String):sidebar.add_child(_label(text,21,GOLD))
func _hint(text:String):sidebar.add_child(_label(text,14,MUTED))
func _line():sidebar.add_child(HSeparator.new())

func _build_ui():
	_heading("Ваш участок мира")
	_hint("Три рабочих добывают ресурсы и несут груз в Штаб. Нажмите на дерево или камень для ручного поручения.")
	if selected_source>=0:
		var source=world._source(selected_source)
		if not source.is_empty():
			sidebar.add_child(_label(("Дерево" if source.kind=="wood" else "Месторождение")+" · осталось "+str(int(source.amount)),18,GOLD))
			sidebar.add_child(_button("Направить свободного рабочего",_gather_selected,true));_line()
	for id in ["hq","barracks","wall","forge","lab","lumber","mine"]:
		var def=state.catalog.building(id)
		var b=_button("%s · %d / %d / %d"%[def.name,def.coins,def.wood,def.stone],_place.bind(id),placement==id)
		b.disabled=def.has("tech") and not state.data.research.get(def.tech,false)
		b.tooltip_text=def.hint;sidebar.add_child(b)
	_line()
	if selected_building>=0 and selected_building<state.data.buildings.size():
		var building=state.data.buildings[selected_building];var def=state.catalog.building(building.id)
		_heading("%s · уровень %d"%[def.name,building.level]);_hint(def.hint)
		if building.level<def.max_level:
			sidebar.add_child(_button("Улучшить · %d / %d / %d"%[def.coins*building.level,def.wood*building.level,def.stone*building.level],_upgrade,true))
		else:_hint("Достигнут предел уровня прототипа.")
	else:_hint("Нажмите на существующее здание, чтобы узнать его эффект и улучшить.")
	_line();_hint("Цена: монеты / древесина / камень. Лесопилка и шахта открываются во вкладке технологий. Колесо мыши приближает участок.")
	sidebar.add_child(_button("Ремонт Штаба · 20 дерева / 10 камня",func():_notice(world.repair());_refresh()))

func _place(id:String):
	placement=id;selected_building=-1;selected_source=-1;_notice("Выберите свободную клетку для: "+state.catalog.building(id).name);_refresh()

func _base_click(cell:Vector2i):
	if in_battle:return
	for i in state.data.buildings.size():
		var building=state.data.buildings[i]
		if int(building.x)==cell.x and int(building.y)==cell.y:
			selected_building=i;selected_source=-1;placement="";_refresh();return
	if placement.is_empty():
		selected_building=-1
		var source=world.source_at(cell);selected_source=int(source.id) if not source.is_empty() else -1
		_refresh();return
	if world.occupied(cell):_notice("Клетка занята человеком. Отведите бойцов или дождитесь рабочего.");return
	_notice(state.build(placement,cell));world.rebuild_navigation();_refresh()

func _upgrade():_notice(state.upgrade(selected_building));_refresh()

func _gather_selected():_notice(world.gather(selected_source));_refresh()

func _tech_ui():
	_heading("Технологии поселения")
	_hint("Технологии открывают постоянное производство. Рабочие физически идут к источнику и возвращают груз.")
	for id in state.catalog.data.technologies:
		var def=state.catalog.data.technologies[id]
		sidebar.add_child(_label(def.name,19,GOLD));_hint(def.hint)
		var b=_button("Изучено" if state.data.research[id] else "Изучить · %d / %d / %d"%[def.coins,def.wood,def.stone],_research.bind(id),true)
		b.disabled=state.data.research[id];sidebar.add_child(b);_line()
	_hint("Числа цены: монеты / древесина / камень. В этой основе два открытия; большая технологическая цепочка ещё предстоит.")

func _research(id:String):_notice(state.research(id));_refresh()
func _pause_world():world.paused=not world.paused;_refresh()
func _trigger_raid():_notice(world.start_raid());_refresh()

func _heroes_ui():
	_heading("Герой вашего похода")
	_hint("В этой первой сборке в бой выходит один выбранный герой. Остальные сохраняют свой опыт.")
	for id in ["astreya","lina","warden"]:
		var def=state.catalog.hero(id);var available=state.hero_available(id)
		var b=_button(("● " if state.data.selected_hero==id else "")+def.name+" · ур. "+str(state.hero_level(id)),_select_hero.bind(id),state.data.selected_hero==id)
		b.disabled=not available;sidebar.add_child(b)
		_hint(def.role)
		if not available:_hint("Нужна лаборатория." if id=="lina" else "Нужен Штаб II.")
		elif state.data.selected_hero==id:
			_hint(def.skill+": "+def.hint)
			_hint("До следующего уровня: %d опыта."%[60-int(state.data.xp[id])%60])
		_line()
	_hint("Способности — тестовые игровые адаптации. Командир гарнизона — временный персонаж вне канона.")

func _select_hero(id:String):
	if not state.hero_available(id):return
	if state.data.world.raid_active:_notice("Во время набега смена героя недоступна.");return
	state.data.selected_hero=id;state.save_progress();_refresh()

func _army_ui():
	_heading("Соберите свой полк")
	_hint("Бойцы участвуют в осаде. Потери учитываются при возвращении; полигон не расходует армию.")
	for id in ["militia","archer","guard"]:
		var def=state.catalog.troop(id)
		sidebar.add_child(_label("%s  ·  %d в строю"%[def.name,state.data.army[id]],18))
		_hint("Здоровье %d · урон %d · %s"%[def.hp,def.damage,"дальний бой" if id=="archer" else "ближний бой"])
		var b=_button("Нанять +1  ·  %d монет"%def.coins,_recruit.bind(id));b.disabled=id=="guard" and state.level("forge")==0;sidebar.add_child(b)
		if b.disabled:_hint("Стражам требуется кузница.")
		_line()
	_hint("Штаб и Казармы расширяют лимит армии. Кузница усиливает обычные атаки союзников.")

func _recruit(id:String):
	if state.data.world.raid_active:_notice("В ранней версии пополнение доступно между набегами.");return
	_notice(state.recruit(id));_refresh()

func _officers_ui():
	_heading("Поручите людям работу")
	_hint("Первые две должности проверяют делегирование. Это пока функциональные назначения без отдельных биографий слуг.")
	for id in ["commander","quartermaster"]:
		var assigned=bool(state.data.officers[id]);var command=id=="commander"
		sidebar.add_child(_label("Командующий" if command else "Снабженец",19,GOLD))
		_hint("После осады пополняет мечников до 12, пока есть монеты и места." if command else "После осады покупает провиант до запаса 12. Цена: 4 монеты за единицу.")
		var b=_button("Освободить должность" if assigned else "Назначить",_assign.bind(id));b.disabled=not command and state.level("hq")<2;sidebar.add_child(b)
		if b.disabled:_hint("Вторая должность откроется на уровне Штаба II.")
		var toggle=CheckButton.new();toggle.text="Разрешить автоматизацию";toggle.button_pressed=state.data.auto_recruit if command else state.data.auto_supply;toggle.disabled=not assigned
		toggle.toggled.connect(_toggle_auto.bind("auto_recruit" if command else "auto_supply"));sidebar.add_child(toggle);_line()
	sidebar.add_child(_button("Купить 3 провианта · 12 монет",_buy_food))
	sidebar.add_child(_button("Выполнить поручения сейчас",_run_automation))
	_hint("Уже есть нужный запас — расхода не будет. Еда пока используется только при отправке в осаду.")

func _assign(id:String):_notice(state.assign(id));_refresh()
func _toggle_auto(enabled:bool,key:String):state.data[key]=enabled;state.save_progress()

func _buy_food():
	if state.data.coins<12:_notice("Недостаточно монет.");return
	state.data.coins-=12;state.data.food+=3;state.save_progress();_notice("Куплено 3 провианта.");_refresh()

func _run_automation():
	var result=state.automate();state.save_progress();_notice("Поручения: нанято %d, провиант +%d, расход %d монет."%[result.recruited,result.food,result.spent]);_refresh()

func _start_battle(kind:String):
	if in_battle:return
	if kind=="siege":
		var error=state.begin_siege()
		if not error.is_empty():_notice(error);return
	benchmark_mode=kind!="siege"
	var army=state.data.army.duplicate()
	var count=26+int(state.data.war_rank)*7
	if kind=="hero":army={"militia":0,"archer":0,"guard":0};count=20
	elif kind in ["200","500","1000"]:
		var half=int(kind)/2;army={"militia":int(half*0.6)-1,"archer":int(half*0.3),"guard":half-int(half*0.6)-int(half*0.3)};count=half
	var wall_hp=0
	for b in state.data.buildings:
		if b.id=="wall":wall_hp+=int(b.level)*80
	in_battle=true;base.hide();combat.show()
	combat.start({"mode":kind,"hero":state.data.selected_hero,"hero_level":state.hero_level(state.data.selected_hero),"rank":state.data.war_rank,
		"forge":state.level("forge"),"army":army,"enemies":count,"keep_hp":300+state.level("hq")*80+wall_hp,"seed":20261029+int(state.data.wins)+int(state.data.losses)})
	_refresh();_notice("ПКМ — приказ выбранной группе. Пробел — техника. P — пауза. Полигон не меняет прогресс." if benchmark_mode else "Защитите крепость! ПКМ — приказ, Пробел — техника, P — пауза.",12)

func _battle_ui():
	toolbar.add_child(_button("Отступить" if not benchmark_mode else "Закрыть полигон",_request_retreat))
	toolbar.add_child(_button("Продолжить" if combat.paused else "Пауза  P",_pause))
	toolbar.add_child(_button("Скорость ×1" if combat.speed==1 else "Скорость ×2",_speed))
	var spacer=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;toolbar.add_child(spacer)
	toolbar.add_child(_label("ПОЛИГОН · без расхода ресурсов" if benchmark_mode else "ОСАДА · защитите крепость",15,GOLD))
	_heading(state.catalog.hero(state.data.selected_hero).name)
	battle_stats=_label("",16,INK);sidebar.add_child(battle_stats)
	skill_button=_button("",combat.cast,true);sidebar.add_child(skill_button)
	_hint(state.catalog.hero(state.data.selected_hero).hint)
	var automatic=CheckButton.new();automatic.text="Применять технику автоматически";automatic.button_pressed=combat.automatic_skill;automatic.toggled.connect(func(value):combat.automatic_skill=value);sidebar.add_child(automatic)
	_line();sidebar.add_child(_label("КОМУ ОТДАТЬ ПРИКАЗ",13,MUTED))
	for item in [["all","Всем бойцам  ·  1"],["hero","Только герою  ·  2"],["militia","Мечникам  ·  3"],["archer","Лучникам  ·  4"],["guard","Стражам  ·  5"]]:
		sidebar.add_child(_button(item[1],_select_group.bind(item[0]),combat.group==item[0]))
	_hint("Нажмите правой кнопкой на поле, чтобы задать направление. В контакте бойцы атакуют самостоятельно.")
	if benchmark_mode:
		_line();_hint("НАГРУЗОЧНЫЕ СЦЕНЫ")
		for count in ["200","500","1000"]:sidebar.add_child(_button(count+" участников",_restart_sandbox.bind(count)))
	_update_battle_ui()

func _update_battle_ui():
	if not in_battle or not is_instance_valid(battle_stats):return
	var b=combat.battle;var hero=b.units[b.hero_id]
	battle_stats.text="Герой: %d / %d\nСоюзники: %d   ·   Враги: %d\nКрепость: %d / %d\nВремя: %02d:%02d   ·   FPS %d"%[hero.hp,hero.max_hp,b.alive(0),b.alive(1),b.keep_hp,b.keep_max,int(b.time)/60,int(b.time)%60,Engine.get_frames_per_second()]
	skill_button.text=("Техника  ·  Пробел" if b.hero_cooldown<=0 else "Восстановление  ·  %.1f с"%b.hero_cooldown)
	skill_button.disabled=b.hero_cooldown>0 or hero.hp<=0 or b.finished

func _select_group(value:String):combat.group=value;_refresh()
func _pause():combat.paused=not combat.paused;_refresh()
func _speed():combat.speed=2.0 if combat.speed==1.0 else 1.0;_refresh()

func _restart_sandbox(count:String):
	in_battle=false;combat.running=false;_start_battle(count)

func _request_retreat():
	if benchmark_mode:_return_base();return
	combat.paused=true;_refresh();retreat_dialog.popup_centered(Vector2i(480,220))

func _retreat():
	if not in_battle:return
	combat.battle.finished=true;combat.battle.won=false;combat.reported=true;_battle_ended(false)

func _battle_ended(won:bool):
	var b=combat.battle;var text="ПОБЕДА" if won else "ПОРАЖЕНИЕ"
	text+="\n\nПротивников побеждено: %d / %d\nВремя боя: %d с"%[b.kills,b.total_enemies,int(b.time)]
	if not benchmark_mode:
		var reward=state.finish_siege(won,b.survivors())
		if not reward.is_empty():
			text+="\n\nМонеты +%d   ·   Материалы +%d\nПровиант +%d   ·   Опыт героя +%d"%[reward.coins,reward.wood,reward.food,reward.xp]
			var auto=reward.automation
			if auto.spent>0:text+="\nПоручения: бойцы +%d, провиант +%d\nРасход поручений: %d монет"%[auto.recruited,auto.food,auto.spent]
			if reward.has("reserves"):text+="\nГарнизон выделил трёх резервных мечников."
	else:text+="\n\nЭто полигон. Армия и ресурсы не изменены."
	text+="\n\nГерои возвращаются даже после поражения.\nОбычные бойцы в осаде несут потери."
	result_dialog.dialog_text=text;result_dialog.popup_centered(Vector2i(570,440));_update_resources()

func _return_base():
	result_dialog.hide();in_battle=false;combat.running=false;combat.hide();base.show();_refresh();state.save_progress();_notice("Вы вернулись в поселение. Мир и добыча продолжаются.")

func _notice(text:String,duration:float=6.0):
	if toast==null:return
	toast.text=text;toast_time=duration;toast.add_theme_color_override("font_color",GOLD)

func _process(dt):
	if world!=null and not in_battle:
		world.step(dt);autosave_clock+=dt
		if autosave_clock>20:autosave_clock=0;state.save_progress()
	if toast_time>0:
		toast_time-=dt
		if toast_time<=0:toast.add_theme_color_override("font_color",MUTED)
	ui_clock+=dt
	if ui_clock>0.2:ui_clock=0;_update_battle_ui();_update_resources()

func _unhandled_key_input(event):
	if not event is InputEventKey or not event.pressed or event.echo:return
	if event.keycode==KEY_F11:_fullscreen();get_viewport().set_input_as_handled();return
	if in_battle and not result_dialog.visible:
		match event.keycode:
			KEY_SPACE:combat.cast()
			KEY_P:_pause()
			KEY_1:_select_group("all")
			KEY_2:_select_group("hero")
			KEY_3:_select_group("militia")
			KEY_4:_select_group("archer")
			KEY_5:_select_group("guard")
			KEY_ESCAPE:_request_retreat()
		get_viewport().set_input_as_handled()
	elif not in_battle:
		match event.keycode:
			KEY_ESCAPE:placement="";_refresh()
			KEY_P:_pause_world()
			KEY_SPACE:_notice("Снимите паузу для применения техники." if world.paused else world.battle.skill())
			KEY_1:base.command_group="all";_notice("Приказ получат все бойцы.")
			KEY_2:base.command_group="hero";_notice("Приказ получит только герой.")
			KEY_3:base.command_group="militia";_notice("Приказ получат мечники.")
			KEY_4:base.command_group="archer";_notice("Приказ получат лучники.")
			KEY_5:base.command_group="guard";_notice("Приказ получат стражи.")

func _fullscreen():
	var window=get_window();window.mode=Window.MODE_WINDOWED if window.mode==Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN

func _close():
	if not in_battle:state.save_progress()
	get_tree().quit()
