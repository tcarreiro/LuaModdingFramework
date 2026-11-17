class_name RuntimeStorage extends RefCounted

const FORMAT_VERSION := 1
const MAX_TABLES := 2048
const MAX_ENTRIES := 50_000
const MAX_DEPTH := 48

var errors: Array[String] = []

var _lua_state: LuaState
var _table_ids: Dictionary = {}
var _nodes: Array = []
var _entry_count: int = 0

# Creates a snapshot of the storage
func capture(lua_state: LuaState, storage: LuaTable) -> Dictionary:
	errors.clear()
	_lua_state = lua_state
	_table_ids.clear()
	_nodes.clear()
	_entry_count = 0
	
	if lua_state == null or storage == null:
		errors.append("Cannot capture an invalid Lua storage.")
		return {}
	
	var root_id := _capture_table(storage, 0)
	if root_id < 0 or not errors.is_empty():
		return {}
	
	return {
		"version": FORMAT_VERSION,
		"root": root_id,
		"tables": _nodes.duplicate(true)
	}


# Rebuilds LuaTable from storage snapshot
func restore(lua_state: LuaState, snapshot: Dictionary) -> LuaTable:
	errors.clear()
	
	if lua_state == null:
		errors.append("Cannot restore storage without a LuaState.")
		return null
	
	if snapshot.is_empty():
		return lua_state.create_table()
	
	if _read_index(snapshot.get("version")) != FORMAT_VERSION:
		errors.append("Unsupported storage snapshot version.")
		return null
	
	var raw_nodes: Variant = snapshot.get("tables")
	if not raw_nodes is Array:
		errors.append("Storage snapshot must contain a tables array.")
		return null
	
	var nodes: Array = raw_nodes
	if nodes.is_empty() or nodes.size() > MAX_TABLES:
		errors.append("Invalid number of storage tables.")
		return null
	
	var root_id := _read_index(snapshot.get("root"))
	if root_id < 0 or root_id >= nodes.size():
		errors.append("Invalid storage root reference.")
		return null
	
	var tables: Array[LuaTable] = []
	var entry_count := 0
	
	# Create all tables. Empty at first
	for node in nodes:
		if not node is Dictionary:
			errors.append("Invalid storage table definition.")
			return null
	
		var entries: Variant = node.get("entries")
		if not entries is Array:
			errors.append("Invalid storage table entries.")
			return null
	
		entry_count += entries.size()
		if entry_count > MAX_ENTRIES:
			errors.append("Storage entry limit exceeded.")
			return null
	
		tables.append(lua_state.create_table())
	
	# Connect values and references
	for i in range(nodes.size()):
		var entries: Array = nodes[i]["entries"]
		for entry in entries:
			if not entry is Array or entry.size() != 2:
				errors.append("Invalid storage entry.")
				return null
	
			var key: Variant = entry[0]
			var encoded: Variant = entry[1]
			if not _is_atom(key):
				errors.append("Invalid storage key.")
				return null
	
			if not encoded is Dictionary or encoded.size() != 1:
				errors.append("Invalid encoded storage value.")
				return null
	
			var value: Variant
			if encoded.has("ref"):
				var reference := _read_index(encoded["ref"])
				if reference < 0 or reference >= tables.size():
					errors.append("Invalid storage table reference.")
					return null
				value = tables[reference]
			elif encoded.has("value"):
				value = encoded["value"]
				if not _is_atom(value):
					errors.append("Invalid storage scalar value.")
					return null
			else:
				errors.append("Unknown storage value encoding.")
				return null
	
			tables[i].rawset(key, value)
	return tables[root_id]


func release() -> void:
	_table_ids.clear()
	_nodes.clear()
	_entry_count = 0
	_lua_state = null


func _capture_table(table: LuaTable, depth: int) -> int:
	if depth > MAX_DEPTH:
		errors.append("Storage nesting depth exceeded.")
		return -1
	
	if table.get_lua_state() != _lua_state:
		errors.append("Storage contains a table from another LuaState.")
		return -1
	
	var pointer: int = table.get_pointer_value()
	if _table_ids.has(pointer):
		return _table_ids[pointer]
	
	if _nodes.size() >= MAX_TABLES:
		errors.append("Storage table limit exceeded.")
		return -1
	
	var table_id := _nodes.size()
	_table_ids[pointer] = table_id
	_nodes.append({"entries": []})
	
	var source: Dictionary = table.to_dictionary()
	var entries: Array = _nodes[table_id]["entries"]
	
	for key in source:
		if not _is_atom(key):
			errors.append("Storage table contains an unsupported key.")
			return -1
	
		_entry_count += 1
		if _entry_count > MAX_ENTRIES:
			errors.append("Storage entry limit exceeded.")
			return -1
	
		var encoded := _capture_value(source[key], depth + 1)
		if not errors.is_empty():
			return -1
	
		entries.append([key, encoded])
	return table_id


func _capture_value(value: Variant, depth: int) -> Dictionary:
	if value is LuaTable:
		var reference := _capture_table(value, depth)
	
		if reference < 0:
			return {}
		return {"ref": reference}
	
	if _is_atom(value):
		return {"value": value}
	errors.append("Storage contains an unsupported value: %s." % type_string(typeof(value)))
	return {}


func _is_atom(value: Variant) -> bool:
	match typeof(value):
		TYPE_BOOL, TYPE_STRING, TYPE_INT:
			return true
		TYPE_FLOAT:
			return is_finite(value)
	return false


func _read_index(value: Variant) -> int:
	if typeof(value) == TYPE_INT:
		return value if value >= 0 else -1
	if typeof(value) == TYPE_FLOAT:
		if is_finite(value) and value >= 0.0 and value <= LuaUtils.MAX_FLOAT and value == floorf(value):
			return int(value)
	return -1
