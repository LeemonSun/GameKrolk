extends Control

const State=preload("res://scripts/state.gd")
const Settlement=preload("res://scripts/settlement.gd")
const Profiles=preload("res://scripts/profiles.gd")
const StartMenu=preload("res://scripts/start_menu.gd")
var profiles
var start_menu
var session_started=false
var combat_was_paused=false
var live_labels={}
var demolition_dialog:ConfirmationDialog
var demolition_uid=-1
var dialog_was_paused=false
var selected_building_uid=-1
const BaseView=preload("res://scripts/world_view.gd")
const World=preload("res://scripts/world.gd")
const BattleView=preload("res://scripts/battle_view.gd")
const Palette=preload("res://scripts/palette.gd")
const Logistics=preload("res://scripts/logistics.gd")
const Commerce=preload("res://scripts/commerce.gd")
const Personnel=preload("res://scripts/personnel.gd")
const AtlasView=preload("res://scripts/atlas_view.gd")
const Chapter=preload("res://scripts/chapter.gd")
var objective_panel:PanelContainer
var objective_text:Label
const BG=Palette.BG
const PANEL=Palette.PANEL
const ACCENT=Palette.ACCENT
const INK=Palette.INK
const MUTED=Palette.MUTED
var state
var world
var base
var map_view
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
var toolbar:Container
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
var selected_worker=-1
var autosave_clock=0.0

func _ready():
	Engine.max_fps=60
	var test_profile="user://progress.json"
	var test_mode="--test-mode" in OS.get_cmdline_user_args() or "--ui-playtest" in OS.get_cmdline_user_args()
	if test_mode:
		test_profile="res://work/test-session-%d.json"%OS.get_process_id()
		profiles=Profiles.new("res://work/profiles-%d"%OS.get_process_id(),test_profile)
	else:
		profiles=Profiles.new();test_profile=profiles.last_path()
	state=State.new(test_profile);state.load_progress()
	world=World.new(state);world.notice.connect(_notice);world.raid_finished.connect(_on_home_raid_finished);world.settlement_changed.connect(func():call_deferred("_refresh"))
	_setup_theme();_setup_ui();_refresh()
	start_menu=StartMenu.new();add_child(start_menu)
	start_menu.continue_requested.connect(_continue_profile);start_menu.new_requested.connect(_new_party)
	start_menu.resume_requested.connect(_resume_game);start_menu.exit_requested.connect(_close)
	if test_mode:session_started=true;start_menu.hide()
	else:_open_main_menu()
	if not state.warning.is_empty():_notice(state.warning,15)
	print("GAMEKROLK_READY "+JSON.stringify({"version":"0.0.9","save":ProjectSettings.globalize_path(state.save_path),"renderer":RenderingServer.get_current_rendering_method()}))

func _style(color:Color,border:Color=Color.TRANSPARENT,radius:int=10)->StyleBoxFlat:
	var s=StyleBoxFlat.new();s.bg_color=color
	s.set_corner_radius_all(radius);s.set_border_width_all(1);s.border_color=border
	s.content_margin_left=14;s.content_margin_right=14;s.content_margin_top=10;s.content_margin_bottom=10
	return s

func _setup_theme():
	theme=Palette.make()

func _label(text:String,size_px:int=16,color:Color=INK)->Label:
	var label=Label.new();label.text=text;label.add_theme_font_size_override("font_size",size_px);label.add_theme_color_override("font_color",color)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	return label

func _button(text:String,callback:Callable=Callable(),accent:bool=false)->Button:
	var b=Button.new();b.text=text;b.custom_minimum_size.y=42;b.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	if callback.is_valid():b.pressed.connect(callback)
	if accent:Palette.button_accent(b)
	return b

func _setup_ui():
	var bg=ColorRect.new();bg.color=BG;bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);bg.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(bg)
	var margin=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right"]:margin.add_theme_constant_override("margin_"+edge,26)
	for edge in ["top","bottom"]:margin.add_theme_constant_override("margin_"+edge,18)
	add_child(margin);root=VBoxContainer.new();root.add_theme_constant_override("separation",13);margin.add_child(root)
	var header=HBoxContainer.new();root.add_child(header)
	var brand=VBoxContainer.new();brand.size_flags_horizontal=Control.SIZE_EXPAND_FILL;brand.add_theme_constant_override("separation",1);header.add_child(brand)
	title=_label("КРОЛИК  /  ЦИТАДЕЛЬ",29,ACCENT);brand.add_child(title)
	subtitle=_label("МИР И ПОСЕЛЕНИЕ    ·    прототип 0.0.9    ·    хозяйство и оборона",12,MUTED);brand.add_child(subtitle)
	header.add_child(_button("Сохранить",func():_notice("Прогресс сохранён." if state.save_progress() else state.warning)))
	header.add_child(_button("Меню",_open_main_menu))
	header.add_child(_button("Во весь экран  F11",_fullscreen))
	var resource_panel=PanelContainer.new();root.add_child(resource_panel);resources=_label("",17,INK);resource_panel.add_child(resources)
	objective_panel=PanelContainer.new();root.add_child(objective_panel)
	var objective_row=HBoxContainer.new();objective_panel.add_child(objective_row)
	objective_text=_label("",15,ACCENT);objective_row.add_child(objective_text)
	objective_row.add_child(_button("К текущей цели",_set_tab.bind("mission"),true))
	toolbar=HFlowContainer.new();root.add_child(toolbar)
	content=HBoxContainer.new();content.size_flags_vertical=Control.SIZE_EXPAND_FILL;content.add_theme_constant_override("separation",16);root.add_child(content)
	var stage=PanelContainer.new();stage.size_flags_horizontal=Control.SIZE_EXPAND_FILL;stage.size_flags_vertical=Control.SIZE_EXPAND_FILL;content.add_child(stage)
	var layers=Control.new();layers.custom_minimum_size=Vector2(640,460);layers.size_flags_vertical=Control.SIZE_EXPAND_FILL;layers.size_flags_horizontal=Control.SIZE_EXPAND_FILL;stage.add_child(layers)
	base=BaseView.new();base.state=state;base.world=world;base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);layers.add_child(base);base.cell_clicked.connect(_base_click);base.order_requested.connect(world.order)
	map_view=AtlasView.new();map_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);layers.add_child(map_view);map_view.hide()
	map_view.selected_region.connect(func(point):map_view.selected=point;_refresh())
	combat=BattleView.new();combat.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);layers.add_child(combat);combat.hide();combat.ended.connect(_battle_ended);combat.notice.connect(_notice)
	var side=PanelContainer.new();side.custom_minimum_size.x=340;content.add_child(side)
	var scroll=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;side.add_child(scroll)
	sidebar=VBoxContainer.new();sidebar.size_flags_horizontal=Control.SIZE_EXPAND_FILL;sidebar.custom_minimum_size.x=300;sidebar.add_theme_constant_override("separation",10);scroll.add_child(sidebar)
	toast=_label("Начните с рубежей поселения: наладьте древесину, еду и жильё. Людям можно назначать работу.",14,MUTED)
	toast.custom_minimum_size.y=42;root.add_child(toast)
	result_dialog=AcceptDialog.new();result_dialog.title="Итог сражения";result_dialog.ok_button_text="Вернуться в крепость";result_dialog.confirmed.connect(_return_base);result_dialog.canceled.connect(_return_base);add_child(result_dialog)
	retreat_dialog=ConfirmationDialog.new();retreat_dialog.title="Отступить?";retreat_dialog.dialog_text="Осада будет засчитана как поражение. Выжившие вернутся; потраченный провиант не возвращается."
	retreat_dialog.ok_button_text="Отступить";retreat_dialog.cancel_button_text="Остаться";retreat_dialog.confirmed.connect(_retreat);add_child(retreat_dialog)
	demolition_dialog=ConfirmationDialog.new();demolition_dialog.title="Снести постройку?"
	demolition_dialog.ok_button_text="Снести";demolition_dialog.cancel_button_text="Отмена";demolition_dialog.confirmed.connect(_demolish);add_child(demolition_dialog)
	demolition_dialog.canceled.connect(func():world.paused=dialog_was_paused;_refresh())
	get_window().close_requested.connect(_close)

func _clear(box:Node):
	for child in box.get_children():box.remove_child(child);child.queue_free()

func _refresh():
	_resolve_selected()
	_update_resources();live_labels.clear();_clear(toolbar);_clear(sidebar)
	if in_battle:_battle_ui();return
	if not state.data.world.raid_active:world.sync_army()
	if tab=="map":map_view.activate(world.regional);map_view.show();base.hide()
	else:map_view.hide();base.show()
	for entry in [["map","Мир"],["build","Строить"],["people","Люди"],["logistics","Снабжение"],["trade","Поставки"],["goals","Рубежи"],["orders","Приказы"],["heroes","Герои"],["army","Армия"],["medical","Лазарет"],["officers","Должности"],["tech","Технологии"]]:
		if Chapter.active(state.data) and entry[0] not in ["build","people","army","orders","medical","tech"]:continue
		var b=_button(entry[1],_set_tab.bind(entry[0]),tab==entry[0]);toolbar.add_child(b)
	if Chapter.enabled(state.data):toolbar.add_child(_button("Первый рубеж",_set_tab.bind("mission"),tab=="mission"))
	var spacer=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;toolbar.add_child(spacer)
	toolbar.add_child(_button("Продолжить" if world.paused else "Пауза  P",_pause_world))
	toolbar.add_child(_button("Разведка",func():_notice(preload("res://scripts/world_rules.gd").forecast(state.data),15)))
	if "--test-mode" in OS.get_cmdline_user_args() or "--developer" in OS.get_cmdline_user_args():
		toolbar.add_child(_button("Полигон",func():_start_battle("hero")))
		toolbar.add_child(_button("Проверить набег",_trigger_raid,true))
	match tab:
		"mission":_mission_ui()
		"map":_atlas_ui()
		"build":_build_ui()
		"people":_people_ui()
		"logistics":_logistics_ui()
		"trade":_trade_ui()
		"medical":_medical_ui()
		"goals":_goals_ui()
		"orders":_orders_ui()
		"heroes":_heroes_ui()
		"army":_army_ui()
		"officers":_officers_ui()
		"tech":_tech_ui()
	base.selected=selected_building;base.selected_source=selected_source;base.selected_worker=selected_worker;base.placement=placement;base.show_orders=tab=="orders" or (tab=="mission" and state.data.chapter.phase in ["countdown","battle"]);base.queue_redraw()
	_update_live()

func _set_tab(value:String):
	tab=value;placement="";base.placement="";_refresh()

func _update_resources():
	var raid="НАБЕГ!" if state.data.world.raid_active else "НАБЕГ ЧЕРЕЗ %02d:%02d"%[int(state.data.world.raid_in)/60,int(state.data.world.raid_in)%60]
	if Chapter.active(state.data) and not state.data.world.raid_active:raid="РАЗЪЕЗД ЧЕРЕЗ %d с"%ceili(state.data.chapter.left) if state.data.chapter.phase=="countdown" else "ПОДГОТОВКА · БЕЗ СПЕШКИ"
	var troops=str(state.army_count())+(" + %d в походе"%state.army_away() if state.army_away()>0 else "")
	resources.text="МОНЕТЫ %d    ДРЕВЕСИНА %d    КАМЕНЬ %d    ПРОВИАНТ %d    АРМИЯ %s/%d    %s"%[state.data.coins,state.data.wood,state.data.stone,state.data.food,troops,state.capacity(),raid]

func _heading(text:String):sidebar.add_child(_label(text,21,ACCENT))
func _hint(text:String):sidebar.add_child(_label(text,14,MUTED))
func _line():sidebar.add_child(HSeparator.new())

func _build_ui():
	_heading("Постройки поселения")
	if selected_source>=0:
		var source=world._source(selected_source)
		if not source.is_empty():
			sidebar.add_child(_label(("Дерево" if source.kind=="wood" else "Месторождение")+" · осталось "+str(int(source.amount)),18,ACCENT))
			var person=Personnel.worker(state.data,selected_worker)
			sidebar.add_child(_button("Добывать до исчерпания" if person.is_empty() else "Поручить: "+person.name,_gather_selected,true))
			if not person.is_empty():sidebar.add_child(_button("Выбрать любого свободного",func():selected_worker=-1;_refresh()))
			_line()
	if selected_building>=0 and selected_building<state.data.buildings.size():
		var building=state.data.buildings[selected_building];var def=state.catalog.building(building.id)
		_heading("%s · %s"%[def.name,"уровень "+str(building.level) if building.built else "стройка"])
		_hint(def.hint)
		var progress=_label("",14,ACCENT);live_labels["building_progress"]=progress;sidebar.add_child(progress)
		if building.id=="gate" and building.built:
			sidebar.add_child(_button("Закрыть ворота" if building.gate_open else "Открыть ворота",func():_notice(world.toggle_gate(int(building.uid)));_refresh(),true))
			_hint("Открытый проход доступен обеим сторонам. Занятый проход закрыть нельзя.")
		var quote=world.repair_quote(int(building.uid))
		if not building.repair.is_empty():
			sidebar.add_child(_button("Отменить ремонт",func():_notice(world.cancel_repair(int(building.uid)));_refresh()))
		elif not quote.is_empty():
			sidebar.add_child(_button("Ремонт · %d дерева / %d камня"%[quote.wood,quote.stone],func():_notice(world.repair(int(building.uid)));_refresh(),true))
		if building.built and building.target_level==building.level and building.level<def.max_level:
			var upgrade_button=_button("Улучшить · %d / %d / %d"%[def.coins*building.level,def.wood*building.level,def.stone*building.level],_upgrade,true)
			upgrade_button.disabled=not building.repair.is_empty();sidebar.add_child(upgrade_button)
		if building.id!="hq":sidebar.add_child(_button("Убрать постройку…",_ask_demolish))
		_line()
	elif placement.is_empty():_hint("Выберите здание на карте для улучшения. Новую стройку выполняет рабочий; размеры видны под курсором.")
	if not placement.is_empty():_hint("Размещаете: "+state.catalog.building(placement).name+". ЛКМ — заложить, Esc — отменить.")
	var grid=GridContainer.new();grid.columns=2;sidebar.add_child(grid)
	for id in ["wall","gate","warehouse","house","lumber","mine","farm","infirmary","barracks","forge","lab","hq"]:
		var def=state.catalog.building(id)
		var button=_button("%s\n%d / %d / %d"%[def.name,def.coins,def.wood,def.stone],_place.bind(id),placement==id)
		button.custom_minimum_size.y=62;button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.disabled=def.has("tech") and not state.data.research.get(def.tech,false)
		button.tooltip_text=def.hint+"\nРазмер: %d×%d. Стройка: %d секунд работы."%[def.width,def.height,def.work];grid.add_child(button)
	_line();_hint("Цена: монеты / древесина / камень. Лес, шахты и фермы требуют технологий и рабочих. Рабочее место обслуживает один человек.")
	_hint("Повреждённую постройку выберите на карте: ремонт выполняет строитель после оплаты материалов.")
	_update_live()

func _place(id:String):
	placement=id;selected_building=-1;selected_building_uid=-1;selected_source=-1;selected_worker=-1;_notice("Выберите свободную клетку для: "+state.catalog.building(id).name);_refresh()

func _base_click(cell:Vector2i):
	if in_battle:return
	var index=state.building_at(cell)
	if index>=0:
		selected_building=index;selected_building_uid=int(state.data.buildings[index].uid);selected_source=-1;placement="";_refresh();return
	if placement.is_empty():
		selected_building=-1;selected_building_uid=-1
		for person in state.data.world.workers:
			if Vector2i(floori(person.x),floori(person.y))==cell:selected_worker=int(person.id);selected_source=-1;tab="people";_refresh();return
		var source=world.source_at(cell);selected_source=int(source.id) if not source.is_empty() else -1
		if selected_source>=0:tab="build"
		_refresh();return
	var def=state.catalog.building(placement)
	var mission_reason=Chapter.placement_reason(state,placement,cell)
	if not mission_reason.is_empty():_notice(mission_reason,12);return
	for x in range(cell.x,cell.x+int(def.width)):
		for y in range(cell.y,cell.y+int(def.height)):
			if world.occupied(Vector2i(x,y)):_notice("Площадка занята людьми. Отведите бойцов или дождитесь рабочего.");return
	var result=state.build(placement,cell);_notice(result)
	if result.begins_with("Заложено"):
		selected_building=state.data.buildings.size()-1;selected_building_uid=int(state.data.buildings[-1].uid);placement="";world.rebuild_navigation();world._assign_jobs();state.save_progress()
	_refresh()

func _upgrade():_resolve_selected();_notice(state.upgrade(selected_building));_refresh()

func _gather_selected():_notice(world.gather(selected_source,selected_worker));_refresh()

func _tech_ui():
	_heading("Технологии поселения")
	_hint("Технологии открывают постоянное производство. Рабочие физически идут к источнику и возвращают груз.")
	for id in state.catalog.data.technologies:
		var def=state.catalog.data.technologies[id]
		sidebar.add_child(_label(def.name,19,ACCENT));_hint(def.hint)
		var b=_button("Изучено" if state.data.research[id] else "Изучить · %d / %d / %d"%[def.coins,def.wood,def.stone],_research.bind(id),true)
		b.disabled=state.data.research[id];sidebar.add_child(b);_line()
	_hint("Числа цены: монеты / древесина / камень. Первые три открытия; большая технологическая цепочка ещё предстоит.")

func _research(id:String):_notice(state.research(id));_refresh()
func _pause_world():world.paused=not world.paused;_refresh()
func _trigger_raid():_notice(world.start_raid());_refresh()

func _heroes_ui():
	_heading("Командир отряда")
	var demonstration="--test-mode" in OS.get_cmdline_user_args() or "--developer" in OS.get_cmdline_user_args()
	_hint("Именные капитаны принадлежат своим организациям. Их вступление в отряд требует отдельной системы отношений; обычная новая партия не выдаёт капитанов романа.")
	if state.data.selected_hero!="warden" and not demonstration:_hint("В прежней партии сохранён демонстрационный герой: "+state.catalog.hero(state.data.selected_hero).name)
	for id in (["warden","astreya","lina"] if demonstration else ["warden"]):
		var def=state.catalog.hero(id);var available=state.hero_available(id)
		var b=_button(("● " if state.data.selected_hero==id else "")+def.name+" · ур. "+str(state.hero_level(id)),_select_hero.bind(id),state.data.selected_hero==id)
		b.disabled=not available;sidebar.add_child(b)
		_hint(def.role)
		if not available:_hint("Нужна лаборатория." if id=="lina" else "Нужен Штаб II.")
		elif state.data.selected_hero==id:
			_hint(def.skill+": "+def.hint)
			_hint("До следующего уровня: %d опыта."%[60-int(state.data.xp[id])%60])
		_line()
	_hint("Командир отряда — временный персонаж вне канона. В режиме разработчика доступны отдельные боевые адаптации Астреи и Лины.")

func _select_hero(id:String):
	if not state.hero_available(id):return
	if state.data.world.raid_active:_notice("Во время набега смена героя недоступна.");return
	state.data.selected_hero=id;state.save_progress();_refresh()

func _army_ui():
	_heading("Соберите свой полк")
	if state.army_away()>0:_hint("%d мечника находятся в походе. Их места остаются занятыми до возвращения."%state.army_away())
	_hint(state.data.personnel.last_report)
	_hint("Половина выбывших бойцов каждого типа попадает в раненые с округлением вниз; остальные погибают. Лазарет позволяет вернуть раненых вместо нового найма.")
	_hint("Бойцы защищают этот участок от набегов. Потери сохраняются; полигон служит отдельной тренировкой.")
	for id in ["militia","archer","guard"]:
		var def=state.catalog.troop(id)
		sidebar.add_child(_label("%s  ·  %d в строю"%[def.name,state.data.army[id]],18))
		_hint(def.get("role",""))
		_hint("Здоровье %d · урон %d · %s"%[def.hp,def.damage,"дальний бой" if id=="archer" else "ближний бой"])
		var b=_button("Нанять +1  ·  %d монет"%def.coins,_recruit.bind(id));b.disabled=id=="guard" and state.level("forge")==0;sidebar.add_child(b)
		if b.disabled:_hint("Щитоносцам требуется кузница.")
		_line()
	_hint("Штаб и Казармы расширяют лимит армии. Кузница усиливает обычные атаки союзников.")

func _recruit(id:String):
	if state.data.world.raid_active:_notice("В ранней версии пополнение доступно между набегами.");return
	_notice(state.recruit(id));_refresh()

func _officers_ui():
	_heading("Поручите людям работу")
	_hint("Должность занимает конкретного жителя: он перестаёт работать на производстве. Если несёт груз, сначала доставит его и только затем начнёт службу.")
	for id in Personnel.POSTS:
		var person=Personnel.holder(state.data,id)
		var locked=(id=="quartermaster" and state.level("hq")<2) or (id=="medic" and state.level("infirmary")==0)
		sidebar.add_child(_label(Personnel.POSTS[id],19,ACCENT))
		_hint({"commander":"Пополняет мечников до 12 за обычную цену. Навык командования увеличивает лимит армии на 2 за уровень выше первого.","quartermaster":"Покупает еду до запаса 12 за 4 монеты. Навык снабжения уменьшает расход еды армией: один паёк на 12 + 2 за уровень выше первого бойцов.","medic":"Лечит раненых в лазарете. Навык медицины ускоряет лечение. Оплата: 3 монеты и 2 провианта за бойца."}[id])
		if not person.is_empty():
			var post_status=_label("",14,MUTED);live_labels["post_"+id]=post_status;sidebar.add_child(post_status)
			sidebar.add_child(_button("Освободить должность",_appoint.bind(id,-1)))
		else:
			var choice=OptionButton.new();choice.custom_minimum_size.y=40;choice.add_item("Выберите жителя…",-1)
			choice.name="choice_"+id
			var skill={"commander":"command","quartermaster":"logistics","medic":"medicine"}[id]
			for candidate in state.data.world.workers:
				if candidate.post.is_empty():choice.add_item("%s · навык %d"%[candidate.name,candidate.skills[skill]],int(candidate.id))
			choice.disabled=locked;choice.item_selected.connect(func(index):
				if index>0:_appoint(id,choice.get_item_id(index)))
			sidebar.add_child(choice)
		if locked:_hint("Нужен Штаб II." if id=="quartermaster" else "Нужен достроенный лазарет.")
		if id in ["commander","quartermaster"]:
			var toggle=CheckButton.new();toggle.text="Разрешить автоматизацию";toggle.button_pressed=state.data.auto_recruit if id=="commander" else state.data.auto_supply;toggle.disabled=person.is_empty()
			toggle.toggled.connect(_toggle_auto.bind("auto_recruit" if id=="commander" else "auto_supply"));sidebar.add_child(toggle)
		_line()
	sidebar.add_child(_button("Купить 3 провианта · 12 монет",_buy_food))
	sidebar.add_child(_button("Выполнить поручения сейчас",_run_automation))
	_hint("Уже есть нужный запас — расхода не будет. Еда расходуется населением и армией каждую игровую минуту.")
	_update_live()

func _assign(id:String):_notice(state.assign(id));_refresh()
func _appoint(post:String,id:int):_notice(state.assign(post,id));world._assign_jobs();state.save_progress();_refresh()
func _toggle_auto(enabled:bool,key:String):state.data[key]=enabled;state.save_progress()

func _buy_food():
	if state.data.coins<12:_notice("Недостаточно монет.");return
	state.data.coins-=12;state.data.food+=3;state.save_progress();_notice("Куплено 3 провианта.");_refresh()

func _run_automation():
	if state.data.world.raid_active:_notice("Поручения по пополнению выполняются после нападения.");return
	var result=state.automate();state.save_progress();_notice("Поручения: нанято %d, провиант +%d, расход %d монет."%[result.recruited,result.food,result.spent]);_refresh()

func _start_battle(kind:String):
	if in_battle:return
	if kind=="siege":
		var error=state.begin_siege()
		if not error.is_empty():_notice(error);return
	map_view.hide()
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
	toolbar.add_child(_label("ПОЛИГОН · без расхода ресурсов" if benchmark_mode else "ОСАДА · защитите крепость",15,ACCENT))
	_heading(state.catalog.hero(state.data.selected_hero).name)
	battle_stats=_label("",16,INK);sidebar.add_child(battle_stats)
	skill_button=_button("",combat.cast,true);sidebar.add_child(skill_button)
	_hint(state.catalog.hero(state.data.selected_hero).hint)
	var automatic=CheckButton.new();automatic.text="Применять технику автоматически";automatic.button_pressed=combat.automatic_skill;automatic.toggled.connect(func(value):combat.automatic_skill=value);sidebar.add_child(automatic)
	_line();sidebar.add_child(_label("КОМУ ОТДАТЬ ПРИКАЗ",13,MUTED))
	for item in [["all","Всем бойцам  ·  1"],["hero","Только герою  ·  2"],["militia","Мечникам  ·  3"],["archer","Лучникам  ·  4"],["guard","Щитоносцам  ·  5"]]:
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
	toast.text=text;toast_time=duration;toast.add_theme_color_override("font_color",ACCENT)

func _process(dt):
	if start_menu!=null and start_menu.visible:return
	if world!=null and not in_battle:
		world.step(dt);autosave_clock+=dt
		if autosave_clock>20:autosave_clock=0;state.save_progress()
	if toast_time>0:
		toast_time-=dt
		if toast_time<=0:toast.add_theme_color_override("font_color",MUTED)
	ui_clock+=dt
	if ui_clock>0.2:ui_clock=0;_update_battle_ui();_update_resources();_update_live()

func _unhandled_key_input(event):
	if not event is InputEventKey or not event.pressed or event.echo:return
	if event.keycode==KEY_F11:_fullscreen();get_viewport().set_input_as_handled();return
	if start_menu!=null and start_menu.visible:
		if event.keycode==KEY_ESCAPE:_resume_game();get_viewport().set_input_as_handled()
		return
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
			KEY_ESCAPE:
				if placement.is_empty():_open_main_menu()
				else:placement="";_refresh()
			KEY_P:_pause_world()
			KEY_S:world.stop(base.command_group)
			KEY_H:world.stop(base.command_group,true)
			KEY_SPACE:_notice("Снимите паузу для применения техники." if world.paused else world.battle.skill())
			KEY_1:_world_group("all");_notice("Приказ получат все бойцы.")
			KEY_2:_world_group("hero");_notice("Приказ получит только герой.")
			KEY_3:_world_group("militia");_notice("Приказ получат мечники.")
			KEY_4:_world_group("archer");_notice("Приказ получат лучники.")
			KEY_5:_world_group("guard");_notice("Приказ получат щитоносцы.")

func _orders_ui():
	_heading("Управление бойцами")
	_hint("Выберите группу и режим, затем укажите место правой кнопкой на карте. Приказы доступны на паузе.")
	var grid=GridContainer.new();grid.columns=2;sidebar.add_child(grid)
	for entry in [["all","Все"],["hero","Герой"],["militia","Мечники"],["archer","Лучники"],["guard","Щитоносцы"]]:
		var button=_button(entry[1],_world_group.bind(entry[0]),base.command_group==entry[0]);button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;grid.add_child(button)
	_line()
	sidebar.add_child(_button("Идти без остановки на бой",_world_mode.bind("move"),world.command_mode=="move"))
	sidebar.add_child(_button("Двигаться с ответным боем",_world_mode.bind("advance"),world.command_mode=="advance"))
	_hint("Обычный приказ не отвлекается на врага по пути. При движении с боем отряд останавливается, чтобы атаковать противника в пределах оружия.")
	_line()
	sidebar.add_child(_button("Удерживать позицию  H",func():world.stop(base.command_group,true)))
	sidebar.add_child(_button("Отменить маршрут  S",func():world.stop(base.command_group)))
	_hint("Удержание запрещает преследование, но оставляет атаки в пределах оружия. Отмена маршрута возвращает свободную оборону. При закрытом проходе бойцы ждут; после открытия продолжают путь.")
	var status=_label("",14,ACCENT);live_labels["orders"]=status;sidebar.add_child(status);_update_live()

func _world_group(group:String):
	base.command_group=group
	if tab=="orders":_refresh()
func _world_mode(mode:String):world.command_mode=mode;_refresh()

func _fullscreen():
	var window=get_window();window.mode=Window.MODE_WINDOWED if window.mode==Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN

func _close():
	if session_started and not in_battle:state.save_progress()
	get_tree().quit()

func _people_ui():
	_heading("Люди поселения")
	_hint("Рабочие %d / мест %d. Еда: %d в игровую минуту. В походном полигоне поселение стоит на паузе."%[state.data.world.workers.size(),state.worker_capacity(),world.food_need()])
	var food=_label("",14,ACCENT);live_labels["food"]=food;sidebar.add_child(food)
	var hire=_button("Нанять рабочего · 40 монет / 4 еды",_hire_worker,true)
	hire.disabled=state.data.world.workers.size()>=state.worker_capacity();sidebar.add_child(hire)
	if hire.disabled:_hint("Чтобы пригласить следующего человека, достройте жилой дом.")
	var priority=CheckButton.new();priority.text="Стройка важнее производства";priority.button_pressed=state.data.construction_first
	priority.tooltip_text="Автоматический рабочий вернёт груз и возьмётся за стройку. Ручные поручения и выбранные профессии сохраняются."
	priority.toggled.connect(func(value):world.set_priority(value));sidebar.add_child(priority)
	_line()
	var ordered=state.data.world.workers.duplicate()
	ordered.sort_custom(func(a,b):return int(a.id)==selected_worker if (int(a.id)==selected_worker)!=(int(b.id)==selected_worker) else int(a.id)<int(b.id))
	for worker in ordered:
		sidebar.add_child(_label(("● " if int(worker.id)==selected_worker else "")+worker.name,18,ACCENT))
		sidebar.add_child(_button("Найти на карте",_focus_worker.bind(int(worker.id))))
		var skills=[]
		for skill in Personnel.SKILLS:
			if worker.skills[skill]>1:skills.append("%s %d"%[Personnel.SKILL_NAMES[skill],worker.skills[skill]])
		_hint(" · ".join(skills) if not skills.is_empty() else "Начальные навыки")
		if not worker.post.is_empty():_hint("Должность: "+Personnel.POSTS[worker.post])
		var status=_label("",14,MUTED);live_labels["worker_"+str(int(worker.id))]=status;sidebar.add_child(status)
		var choice=OptionButton.new();choice.custom_minimum_size.y=36
		for text in ["Авто: работа по приоритету","Строитель","Дровосек: нужна лесопилка","Шахтёр: нужна шахта","Фермер: нужна ферма","Отдых"]:
			choice.add_item(text)
		choice.select(Settlement.PREFERENCES.find(worker.preference));choice.item_selected.connect(_worker_choice.bind(int(worker.id)));sidebar.add_child(choice);_line()
		choice.disabled=not worker.post.is_empty()
	_hint("При смене работы груз сначала возвращается в Штаб. Выбранный источник добывается до конца; отдых отменяет поручение.")
	_update_live()

func _worker_choice(index:int,id:int):
	_notice(world.set_preference(id,Settlement.PREFERENCES[index]));_update_live()

func _focus_worker(id:int):
	var person=Personnel.worker(state.data,id)
	if person.is_empty():return
	selected_worker=id;base.focus_cell(Vector2(person.x,person.y));_refresh()

func _hire_worker():
	_notice(state.hire_worker());world._relocate_blocked();world._assign_jobs();state.save_progress();_refresh()

func _on_home_raid_finished(_won:bool):
	if not world.last_chapter_result:_refresh();return
	if state.data.chapter.phase in ["won","recover"]:tab="mission"
	if state.data.chapter.phase=="won":world.paused=true;state.save_progress()
	_refresh()

func _mission_ui():
	var phase=state.data.chapter.phase
	_heading("ПЕРВЫЙ РУБЕЖ")
	if phase=="supply":_hint("У восточной дороги замечен вооружённый разъезд. Его главарь собирается забрать ваше поселение. Наладьте хозяйство, подготовьте гарнизон и удержите Штаб.")
	elif phase in ["prepare","ready"]:_hint("Снабжение работает. Теперь выберите способ обороны и соберите гарнизон.")
	_line();sidebar.add_child(_label(Chapter.title(state.data),19))
	if phase!="battle":_hint(Chapter.hint(state))
	if phase=="ready":sidebar.add_child(_button("Встретить разъезд · 6 провианта",_mission_commit,true))
	if phase in ["countdown","battle"]:sidebar.add_child(_button("Расставить защитный строй",_mission_formation,true))
	if phase=="battle":
		var skill=_button("Техника командира · Пробел",_mission_skill,true);sidebar.add_child(skill);live_labels.chapter_skill=skill
		var status=_label("",16);sidebar.add_child(status);live_labels.chapter=status
	if phase in ["won","free"]:sidebar.add_child(_button("Продолжить поселение",_mission_continue,true))
	if phase=="supply":
		_hint("1. Изучите лесное дело и агротехнику. 2. Поставьте лесопилку рядом с деревьями и ферму у Штаба. Рабочие построят их и доставят продукцию сами.")
		for id in ["forestry","agriculture"]:
			if not state.data.research[id]:
				var t=state.catalog.data.technologies[id]
				sidebar.add_child(_button("%s · %d монет, %d дерева"%[t.name,t.coins,t.wood],_research.bind(id),true))
		for id in ["lumber","farm"]:
			if state.level(id)==0:
				var exists=state.data.buildings.any(func(b):return b.id==id)
				if exists:_hint(state.catalog.building(id).name+": строится. Не занимайте проход к Штабу.")
				else:
					var def=state.catalog.building(id);var button=_button("Поставить: "+def.name,_mission_place.bind(id))
					button.disabled=not state.data.research[def.tech];sidebar.add_child(button)
		_hint("Если работа остановилась, «Люди» покажут занятие каждого жителя. Поставьте P на паузу, чтобы спокойно разобраться.")
		_hint("Награда этапа: 40 монет и 8 провианта.")
	elif phase in ["prepare","ready"]:
		_hint("Разведка: %d противника, включая главаря со щитом. Его здоровье удвоено. Остальные — мечники и лучники."%Chapter.enemy_count(state.data))
		_hint("Выберите один способ подготовки. Начальные 12 мечников и 8 лучников уже ваши; до 24 нужно ещё четыре бойца.")
		for entry in [["shields","Щиты и кузница"],["bows","Лучники и укрепления"]]:
			sidebar.add_child(_button(entry[1],_mission_plan.bind(entry[0]),state.data.chapter.plan==entry[0]))
		if state.data.chapter.plan=="shields":
			_hint("Кузница + 2 щитоносца. Остальные места заполните мечниками или лучниками. Щиты принимают стрелы спереди.")
			if state.level("forge")==0:sidebar.add_child(_button("Поставить кузницу",_mission_place.bind("forge")))
			else:sidebar.add_child(_button("Нанять щитоносца · 16 монет",_recruit.bind("guard")))
		else:
			_hint("Всего 12 лучников и 3 секции стены. Ставьте стены на восточном направлении, оставляйте проход для своих.")
			sidebar.add_child(_button("Нанять лучника · 11 монет",_recruit.bind("archer")))
			sidebar.add_child(_button("Поставить секцию стены",_mission_place.bind("wall")))
		sidebar.add_child(_button("Нанять мечника · 7 монет",_recruit.bind("militia")))
		_hint("В гарнизоне %d/24 · %s"%[state.army_count(),"щитоносцев %d/2"%state.data.army.guard if state.data.chapter.plan=="shields" else "лучников %d/12"%state.data.army.archer])
		if phase!="ready":
			var begin=_button("Встретить разъезд · 6 провианта",_mission_commit,true);begin.disabled=not Chapter.ready_reason(state).is_empty();begin.tooltip_text=Chapter.ready_reason(state);sidebar.add_child(begin)
	elif phase in ["countdown","battle"]:
		_hint("Враг придёт СПРАВА. Пехоту держите перед лучниками; не уводите весь гарнизон от Штаба. Главарь отмечен на поле.")
		for entry in [["all","Выбрать всех"],["militia","Выбрать мечников"],["archer","Выбрать лучников"],["hero","Выбрать командира"]]:sidebar.add_child(_button(entry[1],_world_group.bind(entry[0]),base.command_group==entry[0]))
		sidebar.add_child(_button("Управление и приказы",_set_tab.bind("orders")))
	elif phase=="recover":
		_hint(state.data.personnel.last_report)
		sidebar.add_child(_button("Пополнить гарнизон",_set_tab.bind("army")))
		sidebar.add_child(_button("Строительство и ремонт",_set_tab.bind("build")))
		sidebar.add_child(_button("Повторить оборону · 6 провианта",_mission_commit,true))
	elif phase in ["won","free"]:
		sidebar.add_child(_label("Дорога остаётся вашей",22))
		_hint("Хозяйство обеспечило подготовку, гарнизон выдержал столкновение. Награда главы уже зачислена: 200 монет, 30 дерева, 15 камня, 10 провианта и 60 опыта.")
		if world.paused:_hint("Игра на паузе. «Продолжить поселение» возобновит время.")
		_hint("Следующая цель — расширить поселение: склад, новые жители, исследования и разведка внешних запасов. Обычные набеги теперь возобновятся.")
		sidebar.add_child(_button("Открыть карту мира",_set_tab.bind("map")))
	if phase in ["supply","prepare","ready","recover"]:
		sidebar.add_child(_button("Не хватает монет? Поставки",_set_tab.bind("trade")))
	_update_live()

func _mission_place(id:String):
	_set_tab("build");_place(id)
func _mission_plan(plan:String):
	if state.data.chapter.phase not in ["supply","prepare","ready"]:return
	state.data.chapter.plan=plan;Chapter.tick(state,0);state.save_progress();_refresh()
func _mission_commit():
	_notice(Chapter.commit(state),12);world.sync_army();_refresh()
func _mission_formation():
	base.command_group="all";world.command_mode="advance"
	world.order("guard",world._nearest_open(Vector2(22.5,11.5)*32));world.order("militia",world._nearest_open(Vector2(21.5,12.5)*32))
	world.order("archer",world._nearest_open(Vector2(18.5,12.5)*32));world.order("hero",world._nearest_open(Vector2(22.0,13.5)*32))
	base.zoom=1;base.pan=Vector2.ZERO;_notice("Строй выдвигается. Можно изменить позиции ПКМ, выбрав нужную группу.");_refresh()
func _mission_continue():
	state.data.chapter.phase="free";world.paused=false;state.save_progress();_set_tab("goals")

func _mission_skill():
	_notice("Снимите паузу для применения техники." if world.paused else world.battle.skill());_update_live()

func _goals_ui():
	_heading("Рубежи поселения")
	_hint("Ваш отряд обустраивает поселение. Сначала наладьте лес, еду и жильё; затем получите доход от поставок и подготовьте гарнизон. Рубежи можно выполнять в разном порядке.")
	sidebar.add_child(_button("Перейти к строительству",_set_tab.bind("build"),true))
	sidebar.add_child(_button("Поставки и доход",_set_tab.bind("trade")))
	_hint("Это задачи обучающего среза, а не сюжетная кампания. Каждый рубеж даёт награду один раз.")
	for goal in Settlement.GOALS:
		var done=goal.id in state.data.achieved
		sidebar.add_child(_label(("✓ " if done else "○ ")+goal.title,19,ACCENT if not done else MUTED))
		_hint(goal.hint)
		_hint("Получено: %d монет."%goal.reward if done else "Награда: %d монет."%goal.reward);_line()
	_hint("Монеты также приходят за отражённые набеги. Потери армии остаются, а поселение продолжает работать между нападениями.")
	_hint(preload("res://scripts/world_rules.gd").forecast(state.data))

func _ask_demolish():
	if selected_building<0 or selected_building>=state.data.buildings.size():return
	var b=state.data.buildings[selected_building];demolition_uid=int(b.uid)
	dialog_was_paused=world.paused;world.paused=true
	demolition_dialog.dialog_text="Убрать «%s»? Вернётся %d древесины и %d камня. Монеты не возвращаются."%[state.catalog.building(b.id).name,int(b.paid_wood)/2,int(b.paid_stone)/2]
	demolition_dialog.popup_centered(Vector2i(460,220))

func _demolish():
	world.paused=dialog_was_paused
	for i in state.data.buildings.size():
		if int(state.data.buildings[i].uid)==demolition_uid:
			_notice(state.demolish(i));selected_building=-1;selected_building_uid=-1;world.rebuild_navigation();world._assign_jobs();state.save_progress();_refresh();return
	_notice("Постройка уже отсутствует.")

func _resolve_selected():
	if selected_building_uid<0:return
	selected_building=-1
	for i in state.data.buildings.size():
		if int(state.data.buildings[i].uid)==selected_building_uid:selected_building=i;return
	selected_building_uid=-1

func _update_live():
	if in_battle:return
	if live_labels.has("chapter_skill"):
		var button=live_labels.chapter_skill;var cooldown=world.battle.hero_cooldown
		button.text="Техника · %.1f с"%cooldown if cooldown>0 else "Техника командира · Пробел"
		button.disabled=world.paused or cooldown>0 or world.battle.units[0].hp<=0
	objective_panel.visible=Chapter.enabled(state.data) and state.data.chapter.phase!="free"
	if objective_panel.visible:objective_text.text=Chapter.title(state.data)+"\n"+Chapter.hint(state)
	if live_labels.has("chapter"):
		var leader_alive=false
		for unit in world.battle.units:
			if int(unit.uid)==int(state.data.chapter.leader) and unit.hp>0:leader_alive=true
		live_labels.chapter.text="Противников осталось: %d\nГлаварь: %s\nПрочность Штаба: %d%%"%[world.battle.alive(1),"в бою" if leader_alive else "повержен",roundi(world.battle.keep_hp/world.battle.keep_max*100)]
	if live_labels.has("expedition"):
		var e=state.data.regional.expedition
		if e.is_empty():live_labels.expedition.text="Отряд дома · завершено походов: %d"%state.data.regional.completed
		else:
			var phase={"outbound":"В пути к области","gather":"Выполняет поручение","return":"Возвращается","waiting":"Ожидает окончания нападения у дома"}[e.phase]
			live_labels.expedition.text="%s\nПозиция %d,%d · груз %d дерева / %d камня\nДва мечника вне гарнизона"%[phase,e.path[int(e.index)][0],e.path[int(e.index)][1],e.cargo.wood,e.cargo.stone]
	for post in Personnel.POSTS:
		if live_labels.has("post_"+post):
			var person=Personnel.holder(state.data,post)
			live_labels["post_"+post].text=person.name+" · "+("на службе" if Personnel.ready(state.data,post) else world.worker_status(int(person.id))) if not person.is_empty() else "Должность свободна"
	if live_labels.has("medical"):
		var p=state.data.personnel;var total=0
		for amount in p.wounded.values():total+=int(amount)
		var reason=Personnel.treatment_reason(state)
		live_labels.medical.text="Раненые: %d · возвращено в строй: %d\nПогибло: %d\n%s"%[total,p.treated,p.lost,reason if not reason.is_empty() else "Лечение: %d%%"%mini(100,roundi(100*p.treatment/Personnel.treatment_seconds(state)))]
	if live_labels.has("orders"):
		var total=0;var moving=0;var waiting=0
		for unit in world.battle.units:
			if unit.team!=0 or unit.hp<=0 or (base.command_group!="all" and unit.kind!=base.command_group):continue
			total+=1
			if unit.route_blocked:waiting+=1
			elif unit.goal!=Vector2.INF:moving+=1
		live_labels.orders.text="Выбрано: %d · с маршрутом: %d · ждут прохода: %d"%[total,moving,waiting]
	for worker in state.data.world.workers:
		var key="worker_"+str(int(worker.id))
		if live_labels.has(key):live_labels[key].text=world.worker_status(int(worker.id))
	if live_labels.has("food"):
		live_labels.food.text="Еды нет — скорость работы 60%." if state.data.food==0 else "Запас еды: %d. Следующая трапеза через %d с."%[state.data.food,ceili(60-state.data.world.food_clock)]
	if live_labels.has("building_progress") and selected_building>=0 and selected_building<state.data.buildings.size():
		var building=state.data.buildings[selected_building]
		if not building.repair.is_empty():live_labels.building_progress.text="Ремонт: %d%% · осталось восстановить %d"%[roundi(100*(1.0-building.repair.remaining/building.repair.total)),ceili(building.repair.remaining)]
		else:live_labels.building_progress.text="Работа: %d%% · к уровню %d"%[mini(100,roundi(building.work_done/world.required_work(building)*100)),building.target_level] if world.needs_work(building) else "Построено · прочность %d / %d"%[building.hp,state.catalog.building(building.id).hp*building.level]
		if building.id=="hq":live_labels.building_progress.text+="\nШтаб: %d / %d"%[world.battle.keep_hp,world.battle.keep_max]
	if live_labels.has("storage"):
		var lines=[]
		for entry in [["wood","Древесина"],["stone","Камень"],["food","Провиант"]]:
			var current=int(state.data[entry[0]]);var capacity=Logistics.capacity(state.data,entry[0])
			lines.append("%s: %d / %d%s"%[entry[1],current,capacity," · нет места" if current>=capacity else ""])
		live_labels.storage.text="\n".join(lines)
	if live_labels.has("trade"):
		var cargo=state.data.commerce.cargo
		live_labels.trade.text="Новые заказы через %d с\nЭкспортов: %d · доход: %d монет\n%s"%[ceili(180-state.data.commerce.window),state.data.commerce.orders,state.data.commerce.income,"Нет поставки в пути" if cargo.is_empty() else (Commerce.OFFERS[cargo.id].name+" · "+("ждёт конца нападения" if cargo.remaining<=0 else str(ceili(cargo.remaining))+" с"))]
	if live_labels.has("logistics"):
		var carriers=0;var cargo=0;var stalled=0
		for w in state.data.world.workers:
			if w.carry>0:carriers+=1;cargo+=int(w.carry)
			if "хранилищ" in world.worker_status(int(w.id)).to_lower():stalled+=1
		live_labels.logistics.text="Груз у людей: %d · носильщиков: %d\nОжидают места или пути: %d\nРасход еды: %d в минуту"%[cargo,carriers,stalled,world.food_need()]

func _logistics_ui():
	_heading("Снабжение поселения")
	_hint("Добыча даёт запас только после разгрузки. Рабочий выбирает ближайший доступный Штаб или склад по длине пути.")
	var stocks=_label("",18,ACCENT);live_labels.storage=stocks;sidebar.add_child(stocks)
	var details=_label("",15);live_labels.logistics=details;sidebar.add_child(details)
	_line();_hint("Полное хранилище останавливает добычу. Уже поднятый груз остаётся у людей. Трата запасов освобождает место; работа возобновляется.")
	sidebar.add_child(_button("Разместить склад",_place.bind("warehouse"),true))
	_hint("Склад 2×2: 45 монет / 35 дерева / 15 камня. Уровень: +180 дерева, +140 камня, +60 еды. Запасы общие для поселения.")
	_line();_hint("Снос или потеря склада уменьшают предел, но уже накопленное не исчезает. Новая разгрузка ждёт освобождения места.")
	for building in state.data.buildings:
		if building.id not in ["hq","warehouse"]:continue
		var uid=int(building.uid)
		sidebar.add_child(_button("%s · %d,%d · %s"%[state.catalog.building(building.id).name,building.x,building.y,"ур. "+str(building.level) if building.built else "стройка"],_inspect_building.bind(uid)))
	_update_live()

func _inspect_building(uid:int):
	selected_building_uid=uid;tab="build";placement="";selected_source=-1;_refresh()

func _trade_ui():
	_heading("Местные поставки")
	_hint("Хозяйство даёт доход независимо от побед. Один обоз в пути; каждый заказ доступен раз в три игровых минуты. Отправка расходует запас сразу, оплата приходит после возвращения.")
	var status=_label("",16,ACCENT);live_labels.trade=status;sidebar.add_child(status)
	_line()
	var names={"wood":"дерева","stone":"камня","food":"еды","coins":"монет"}
	for id in Commerce.OFFERS:
		var offer=Commerce.OFFERS[id]
		sidebar.add_child(_label(offer.name,18))
		_hint("Отдать %d %s → получить %d %s"%[offer.amount,names[offer.take],offer.reward,names[offer.give]])
		var button=_button("Отправить поставку",_send_trade.bind(id));button.tooltip_text=Commerce.reason(state,id);sidebar.add_child(button)
		_line()
	_hint("Обозы здесь считаются по времени, отдельной фигурки на карте пока нет. Покупка и награды могут временно превысить предел склада; новая добыча ждёт места.")
	_update_live()

func _atlas_ui():
	var model=world.regional;var point=map_view.selected
	_heading("Земли за поселением")
	_hint("Поселение продолжает работать, пока вы смотрите карту. Походный отряд временно уменьшает гарнизон.")
	var row=HFlowContainer.new();sidebar.add_child(row)
	row.add_child(_button("Карта мира",func():map_view.mode="overview";_refresh(),map_view.mode=="overview"))
	row.add_child(_button("Область",func():map_view.mode="region";_refresh(),map_view.mode=="region"))
	row.add_child(_button("Окрестности",func():map_view.mode="nearby";_refresh(),map_view.mode=="nearby"))
	if map_view.mode!="overview":
		var arrows=HBoxContainer.new();sidebar.add_child(arrows)
		for direction in [["←",Vector2i.LEFT],["↑",Vector2i.UP],["↓",Vector2i.DOWN],["→",Vector2i.RIGHT]]:arrows.add_child(_button(direction[0],_atlas_shift.bind(direction[1])))
	sidebar.add_child(_button("Найти поселение",func():map_view.selected=model.home();map_view.zoom=1;map_view.pan=Vector2.ZERO;map_view.mode="overview";_refresh()))
	_line()
	var index=model.atlas.index(point)
	_hint("Область %d,%d · %s%s"%[point.x,point.y,model.atlas.NAMES[model.atlas.biomes[index]]," · река" if model.atlas.river(point) else ""])
	if point==model.home():
		_hint("Ваше поселение. Его земля, постройки и люди сохранены без перегенерации.")
		sidebar.add_child(_button("К поселению",_set_tab.bind("build"),true))
	elif model.known(point):
		_hint("Изученные запасы: дерево %d · камень %d"%[model.remaining(point,"wood"),model.remaining(point,"stone")])
	else:_hint("Местность ещё не разведана. Подробные запасы откроются после прибытия отряда.")
	var path=model.route(point);map_view.preview_path=path
	if point!=model.home():
		if path.is_empty():_hint("Сухопутный путь не найден. Морские переходы пока недоступны.")
		else:_hint("Путь: %d переходов · около %d с туда и обратно + 12 с на месте."%[path.size()-1,(path.size()-1)*4])
		for entry in [["survey","Разведать область"],["wood","Вывезти до 25 дерева"],["stone","Вывезти до 25 камня"]]:
			var button=_button(entry[1],_send_expedition.bind(point,entry[0]),entry[0]=="survey")
			button.tooltip_text=model.reason(point,entry[0]);button.disabled=not button.tooltip_text.is_empty();sidebar.add_child(button)
		_hint("На поход нужны 2 мечника и 3 провианта. Запасы конечны; груз поступает только после возвращения.")
	_line();var status=_label("",15,ACCENT);live_labels.expedition=status;sidebar.add_child(status)
	if not state.data.regional.expedition.is_empty():sidebar.add_child(_button("Отозвать отряд",func():_notice(model.recall());_refresh()))
	_hint("Разведка открывает местные запасы. Отряд работает на обзорной карте; дом продолжает добычу и оборону. На время нападения возвращающийся отряд ждёт у поселения.")
	if map_view.mode=="nearby":map_view.prepare_nearby()
	_update_live()

func _send_expedition(point:Vector2i,operation:String):
	_notice(world.regional.send(point,operation));world.sync_army();state.save_progress();_refresh()

func _atlas_shift(direction:Vector2i):
	var point=map_view.selected+direction
	if not world.regional.atlas.inside(point):_notice("Достигнут край карты.");return
	map_view.selected=point;_refresh()

func _medical_ui():
	_heading("Лазарет гарнизона")
	_hint(state.data.personnel.last_report)
	var status=_label("",17,ACCENT);live_labels.medical=status;sidebar.add_child(status)
	for kind in ["guard","archer","militia"]:_hint("%s: раненых %d"%[state.catalog.troop(kind).name,state.data.personnel.wounded[kind]])
	_line()
	_hint("Один пациент за раз. Порядок: щитоносцы → лучники → мечники. Бойцу нужны 3 монеты, 2 провианта и место в армии. Лекарь занят службой, а не производством.")
	var toggle=CheckButton.new();toggle.text="Лечить автоматически";toggle.button_pressed=state.data.personnel.auto_treat
	toggle.toggled.connect(func(value):state.data.personnel.auto_treat=value;state.save_progress();_update_live());sidebar.add_child(toggle)
	if state.level("infirmary")==0:sidebar.add_child(_button("Разместить лазарет · 45 / 30 / 15",_place.bind("infirmary"),true))
	sidebar.add_child(_button("Назначить лекаря",_set_tab.bind("officers")))
	_hint("Базовое лечение 30 игровых секунд. Навык лекаря и уровень лазарета ускоряют его. Во время нападения, нехватки ресурсов или заполненного гарнизона лечение ждёт; прогресс не теряется.")
	_update_live()

func _send_trade(id:String):_notice(Commerce.send(state,id));_refresh()

func _open_main_menu():
	if start_menu==null:return
	var save_error=""
	if session_started and not state.save_progress():save_error=state.warning if not state.warning.is_empty() else "Не удалось сохранить текущую партию."
	combat_was_paused=combat.paused;combat.paused=true
	start_menu.open(profiles.entries(),state.save_path,session_started)
	if not save_error.is_empty():start_menu.show_error(save_error)

func _resume_game():
	if not session_started:return
	start_menu.hide();combat.paused=combat_was_paused

func _continue_profile(path:String):
	if session_started and path==state.save_path:_resume_game();return
	if path not in profiles.paths():start_menu.show_error("Сохранение больше не найдено.");return
	var next=State.new(path)
	if not next.load_progress() or next.read_only:start_menu.show_error(next.warning);return
	_activate_party(next)

func _new_party(seed_value:int,threat:String,title_text:String,guided:bool=false):
	var next=profiles.create(seed_value,threat,title_text,guided)
	if next==null:start_menu.show_error(profiles.error);return
	_activate_party(next)
	_set_tab("mission" if guided else "goals")

func _activate_party(next):
	state.before_save=Callable()
	for connection in base.order_requested.get_connections():base.order_requested.disconnect(connection.callable)
	state=next;world=World.new(state);base.state=state;base.world=world;base.order_requested.connect(world.order)
	map_view.model=null;map_view.texture=null
	world.notice.connect(_notice);world.raid_finished.connect(_on_home_raid_finished);world.settlement_changed.connect(func():call_deferred("_refresh"))
	combat.running=false;combat.hide();base.show();result_dialog.hide();retreat_dialog.hide()
	in_battle=false;benchmark_mode=false;session_started=true;autosave_clock=0;tab="mission" if Chapter.enabled(state.data) and state.data.chapter.phase!="free" else "build"
	selected_building=-1;selected_building_uid=-1;selected_source=-1;selected_worker=-1;placement="";base.zoom=1.0;base.pan=Vector2.ZERO
	base.command_group="hero"
	start_menu.hide();_refresh()
	if state.save_progress():
		if not profiles.remember(state.save_path):_notice("Партия сохранена, но последнюю выбранную партию запомнить не удалось.")
	else:_notice(state.warning)
	if not state.warning.is_empty():_notice(state.warning)
