extends RefCounted

const VERSION=1
const SEA=0.23
const NAMES=["Море","Озеро","Луг","Лес","Сухие земли","Холмы","Горы","Тундра"]
const COLORS=[Color("233a45"),Color("416774"),Color("748368"),Color("344f43"),Color("a29268"),Color("72736a"),Color("b6b7ae"),Color("929f99")]
const DIRS=[Vector2i(-1,-1),Vector2i(0,-1),Vector2i(1,-1),Vector2i(-1,0),Vector2i(1,0),Vector2i(-1,1),Vector2i(0,1),Vector2i(1,1)]
var side=128
var seed_value=1
var heights=PackedFloat32Array()
var filled=PackedFloat32Array()
var flow=PackedInt32Array()
var accumulation=PackedInt32Array()
var biomes=PackedByteArray()
var rivers=PackedByteArray()
var moisture=PackedFloat32Array()
var home=Vector2i.ZERO
var elapsed_ms=0.0
var heap:Array=[]

func build(value:int,width:int=128):
	var started=Time.get_ticks_usec();seed_value=value;side=width
	var count=side*side
	heights.resize(count);filled.resize(count);flow.resize(count);accumulation.resize(count);biomes.resize(count);rivers.resize(count);moisture.resize(count)
	flow.fill(-1);rivers.fill(0);accumulation.fill(1);heap.clear()
	var terrain=FastNoiseLite.new();terrain.seed=value;terrain.frequency=4.5/side;terrain.fractal_octaves=4
	var wet=FastNoiseLite.new();wet.seed=value^0x5a5a;wet.frequency=3.1/side
	for y in side:
		for x in side:
			var index=y*side+x;var edge=Vector2(float(x)/(side-1)*2-1,float(y)/(side-1)*2-1).length_squared()
			heights[index]=clampf(0.56+terrain.get_noise_2d(x,y)*0.62-pow(edge,0.85)*0.26,0,1)
			if x==0 or y==0 or x==side-1 or y==side-1:heights[index]=0
			moisture[index]=clampf(0.5+wet.get_noise_2d(x,y)*0.8,0,1)
	var visited=PackedByteArray();visited.resize(count);visited.fill(0)
	var order=PackedInt32Array()
	for i in count:
		if heights[i]<=SEA:visited[i]=1;filled[i]=heights[i];_push(Vector2(i,filled[i]))
	while not heap.is_empty():
		var item=_pop();var index=int(item.x);order.append(index)
		var point=Vector2i(index%side,index/side)
		for direction in DIRS:
			var next=point+direction
			if not inside(next):continue
			var id=next.y*side+next.x
			if visited[id]!=0:continue
			visited[id]=1;filled[id]=maxf(heights[id],filled[index]+0.00001);flow[id]=index;_push(Vector2(id,filled[id]))
	for k in range(order.size()-1,-1,-1):
		var index=order[k]
		if flow[index]>=0:accumulation[flow[index]]+=accumulation[index]
	var best=INF
	for i in count:
		var p=Vector2i(i%side,i/side);var height=heights[i]
		if height<=SEA:biomes[i]=0
		elif filled[i]-height>0.035:biomes[i]=1
		elif height>0.72:biomes[i]=6
		elif height>0.59:biomes[i]=5
		elif float(p.y)/side<0.15:biomes[i]=7
		elif moisture[i]<0.37:biomes[i]=4
		elif moisture[i]>0.54:biomes[i]=3
		else:biomes[i]=2
		if biomes[i]>=2 and accumulation[i]>=40:rivers[i]=1
		if biomes[i] in [2,3,5] and rivers[i]==0:
			var distance=Vector2(p).distance_squared_to(Vector2(side,side)*0.5)
			if distance<best:best=distance;home=p
	elapsed_ms=(Time.get_ticks_usec()-started)/1000.0

func inside(point:Vector2i)->bool:return point.x>=0 and point.y>=0 and point.x<side and point.y<side
func index(point:Vector2i)->int:return point.y*side+point.x
func land(point:Vector2i)->bool:return inside(point) and biomes[index(point)]>=2
func river(point:Vector2i)->bool:return inside(point) and rivers[index(point)]!=0

func _less(a:Vector2,b:Vector2)->bool:return a.y<b.y or (a.y==b.y and a.x<b.x)
func _push(value:Vector2):
	heap.append(value);var i=heap.size()-1
	while i>0:
		var parent=(i-1)/2
		if not _less(heap[i],heap[parent]):break
		var item=heap[i];heap[i]=heap[parent];heap[parent]=item;i=parent
func _pop()->Vector2:
	var result:Vector2=heap[0];var last=heap.pop_back()
	if heap.is_empty():return result
	heap[0]=last;var i=0
	while i*2+1<heap.size():
		var child=i*2+1
		if child+1<heap.size() and _less(heap[child+1],heap[child]):child+=1
		if not _less(heap[child],heap[i]):break
		var item=heap[i];heap[i]=heap[child];heap[child]=item;i=child
	return result
