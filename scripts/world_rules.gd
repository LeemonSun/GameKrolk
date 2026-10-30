extends RefCounted
const Chapter=preload("res://scripts/chapter.gd")

const MODES={
	"calm":{"name":"Спокойный","hint":"Первый набег через 6 минут, затем каждые 6 минут. Небольшие слабые отряды: больше времени на строительство.","first":360.0,"interval":360.0,"base":6,"growth":2,"extra":26,"hp":0.75,"damage":0.5},
	"standard":{"name":"Обычный","hint":"Первый набег через 2,5 минуты, затем каждые 3 минуты. Знакомый темп прототипа; отряды растут после побед.","first":150.0,"interval":180.0,"base":12,"growth":4,"extra":50,"hp":0.85,"damage":0.7},
	"harsh":{"name":"Опасный","hint":"Первый набег через 1,5 минуты, затем каждые 2 минуты. Врагов больше, они сильнее и быстрее наращивают численность.","first":90.0,"interval":120.0,"base":18,"growth":6,"extra":72,"hp":1.0,"damage":1.0}
}

static func mode(data:Dictionary)->String:return data.get("rules",{}).get("threat","standard")
static func settings(data:Dictionary)->Dictionary:return MODES[mode(data)]

static func forecast(data:Dictionary)->String:
	if data.has("chapter") and Chapter.active(data):
		var count=Chapter.enemy_count(data);var archers=(count-1)/3
		return "Разъезд с востока: %d противника — главарь со щитом, %d лучников, %d мечников. Начало после подготовки и подтверждения обороны."%[count,archers,count-archers-1]
	var index=int(data.world.raid_number)%3
	var count=int(settings(data).base)+mini(int(settings(data).extra),int(data.world.raids_defeated)*int(settings(data).growth))
	return ["Налётчики: %d. Смешанный отряд, основа — ближний бой.","Стрелковый отряд: %d. Большинство — лучники; используйте укрытия и сближение.","Тяжёлый отряд: %d. Щитоносцы в первой линии; подготовьте поддержку и запас прочности."][index]%count
