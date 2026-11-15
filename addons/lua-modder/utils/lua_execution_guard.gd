@tool
class_name LuaExecutionGuard extends RefCounted

const DEFAULT_INSTRUCTION_LIMIT := 500_000
const DEFAULT_TIME_LIMIT_MS := 500
const DEFAULT_MEMORY_LIMIT_BYTES := 32 * 1024 * 1024
const DEFAULT_SOURCE_LIMIT_BYTES := 1024 * 1024
const DEFAULT_HOOK_INTERVAL := 1000

var instruction_limit: int = DEFAULT_INSTRUCTION_LIMIT
var time_limit_ms: int = DEFAULT_TIME_LIMIT_MS
var memory_limit_bytes: int = DEFAULT_MEMORY_LIMIT_BYTES
var source_limit_bytes: int = DEFAULT_SOURCE_LIMIT_BYTES
var hook_interval: int = DEFAULT_HOOK_INTERVAL

var last_error: String = ""

var _lua_state: LuaState
var _instruction_count: int = 0
var _started_at_ms: int = 0
var _limit_error: String = ""


func execute(lua_state: LuaState, source: String, chunk_name: String = "") -> bool:
	last_error = ""
	_limit_error = ""

	var buffer := source.to_utf8_buffer()

	if buffer.size() > source_limit_bytes:
		last_error = "Lua source exceeds maximum size of %d bytes." % source_limit_bytes
		return false

	if lua_state.get_memory_used() > memory_limit_bytes:
		last_error = "Lua memory limit exceeded before execution."
		return false

	# Accept Lua source only, never compiled bytecode.
	var loaded: Variant = lua_state.load_buffer(buffer, chunk_name, LuaState.LOAD_MODE_TEXT)

	if loaded is LuaError:
		last_error = str(loaded)
		return false

	if not loaded is LuaFunction:
		last_error = "Failed to compile Lua source."
		return false

	var coroutine := LuaCoroutine.create(loaded)

	if coroutine == null:
		last_error = "Failed to create Lua coroutine."
		return false

	_lua_state = lua_state
	_instruction_count = 0
	_started_at_ms = Time.get_ticks_msec()

	coroutine.set_hook(_on_hook, LuaThread.HOOK_MASK_COUNT, hook_interval)

	var result: Variant = coroutine.resume()
	var status: int = coroutine.status

	coroutine.set_hook(null, 0)

	_lua_state = null

	if not _limit_error.is_empty():
		last_error = _limit_error
		return false

	if result is LuaError:
		last_error = str(result)
		return false

	if status != LuaThread.STATUS_DEAD:
		last_error = "Lua execution did not complete normally. Status: %d." % status
		return false

	if lua_state.get_memory_used() > memory_limit_bytes:
		last_error = "Lua memory limit exceeded after execution."
		return false

	return true


func _on_hook(_debug: LuaDebug) -> int:
	_instruction_count += hook_interval

	if _instruction_count >= instruction_limit:
		_limit_error = "Lua instruction limit exceeded (%d instructions)." % instruction_limit
		return LuaThread.HOOK_YIELD

	var elapsed := Time.get_ticks_msec() - _started_at_ms

	if elapsed >= time_limit_ms:
		_limit_error = "Lua execution time limit exceeded (%d ms)." % time_limit_ms
		return LuaThread.HOOK_YIELD

	if _lua_state.get_memory_used() > memory_limit_bytes:
		_limit_error = "Lua memory limit exceeded (%d bytes)." % memory_limit_bytes
		return LuaThread.HOOK_YIELD

	return LuaThread.HOOK_OK


static func restrict_base_functions(lua_state: LuaState) -> void:
	for function_name in [
		"dofile",
		"loadfile",
		"load",
		"collectgarbage"
	]:
		lua_state.globals.rawset(function_name, null)
