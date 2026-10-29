extends RefCounted

# JSON parsing can round a binary float by one ULP. Integers, keys and array
# lengths must still match exactly; this tolerance cannot hide gameplay drift.
static func same(a:Variant,b:Variant)->bool:
	if typeof(a)!=typeof(b):return false
	if a is Dictionary:
		if a.size()!=b.size():return false
		for key in a:
			if not b.has(key) or not same(a[key],b[key]):return false
		return true
	if a is Array:
		if a.size()!=b.size():return false
		for i in a.size():
			if not same(a[i],b[i]):return false
		return true
	if a is float:return absf(a-b)<=maxf(1.0,maxf(absf(a),absf(b)))*1e-14
	return a==b

static func first_difference(a:Variant,b:Variant,path:String="$")->String:
	if same(a,b):return ""
	if a is Dictionary and b is Dictionary:
		for key in a:
			if not b.has(key):return path+"/"+str(key)+": missing"
			if not same(a[key],b[key]):return first_difference(a[key],b[key],path+"/"+str(key))
	if a is Array and b is Array:
		for i in mini(a.size(),b.size()):
			if not same(a[i],b[i]):return first_difference(a[i],b[i],path+"/"+str(i))
	return path+": "+var_to_str(a)+" => "+var_to_str(b)
