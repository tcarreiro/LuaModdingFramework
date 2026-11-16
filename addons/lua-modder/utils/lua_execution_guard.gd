class_name LuaExecutionGuard extends RefCounted

const DEFAULT_MAX_INSTRUCTIONS := 500_000
const DEFAULT_MAX_DURATION_MS := 500
const DEFAULT_MAX_MEMORY_BYTES := 32 * 1024 * 1024
const DEFAULT_MAX_SOURCE_BYTES := 1024 * 1024
const DEFAULT_HOOK_INTERVAL := 1000

var max_instructions: int = DEFAULT_MAX_INSTRUCTIONS
var max_duration_ms: int = DEFAULT_MAX_DURATION_MS
var max_memory_bytes: int = DEFAULT_MAX_MEMORY_BYTES
var max_source_bytes: int = DEFAULT_MAX_SOURCE_BYTES
var hook_interval: int = DEFAULT_HOOK_INTERVAL

var last_error: String = ""
var last_result: Variant = null

var _active_state: LuaState
var _started_at_ms: int = 0
var _executed_instructions: int = 0
var _abort_reason: String = ""
var _running: bool = false

var _active_coroutine: LuaCoroutine

static func restrict_base_functions(lua_state: LuaState) -> void:
	for function_name in ["dofile", "loadfile", "load", "collectgarbage"]:
		lua_state.globals.rawset(function_name, null)


func execute(lua_state: LuaState, source: String, chunk_name: String = "") -> bool:
	last_error = ""
	last_result = null

	if _running:
		return _fail("LuaExecutionGuard is already executing.")

	if lua_state == null:
		return _fail("LuaState is null.")

	var buffer := source.to_utf8_buffer()

	if buffer.size() > max_source_bytes:
		return _fail("Lua source exceeds maximum allowed size.")

	var loaded: Variant = lua_state.load_buffer(buffer,
		chunk_name, LuaState.LOAD_MODE_TEXT)

	if loaded is LuaError:
		return _fail("Lua compilation error: %s" % str(loaded))

	if not loaded is LuaFunction:
		return _fail("Lua compilation did not return a function.")

	return _run_protected(lua_state, loaded, [], chunk_name)


func invoke(lua_state: LuaState, callback: LuaFunction, arguments: Array = [], callback_name: String = "") -> bool:
	last_error = ""
	last_result = null

	if _running:
		return _fail("LuaExecutionGuard is already executing.")

	if lua_state == null or callback == null:
		return _fail("Invalid LuaState or callback.")

	if callback.get_lua_state() != lua_state:
		return _fail("Lua callback belongs to a different LuaState.")

	for argument in arguments:
		if argument is LuaObject and argument.get_lua_state() != lua_state:
			return _fail("Lua argument belongs to a different LuaState.")

	return _run_protected(lua_state, callback, arguments, callback_name)


func _run_protected(lua_state: LuaState, callback: LuaFunction, arguments: Array, context: String) -> bool:
	_running = true
	_active_state = lua_state
	_started_at_ms = Time.get_ticks_msec()
	_executed_instructions = 0
	_abort_reason = ""

	var success := false
	var coroutine := LuaCoroutine.create(callback)

	if coroutine == null:
		last_error = "Failed to create Lua coroutine."
	else:
		_active_coroutine = coroutine
		if lua_state.get_memory_used() > max_memory_bytes:
			last_error = "Lua memory limit exceeded."
		else:
			coroutine.set_hook(_on_hook, LuaThread.HOOK_MASK_COUNT,
				maxi(1, hook_interval))

			var result: Variant = coroutine.resumev(arguments)

			coroutine.set_hook(null, 0)

			if not _abort_reason.is_empty():
				last_error = _abort_reason
			elif result is LuaError:
				last_error = str(result)
			elif coroutine.status == LuaThread.STATUS_YIELD:
				last_error = "Lua coroutine yielded unexpectedly."
			elif coroutine.status != LuaThread.STATUS_DEAD:
				last_error = "Lua coroutine terminated with status %d." % coroutine.status
			else:
				last_result = result
				success = true

	#_active_coroutine = null
	_active_state = null
	_running = false

	if not success and not context.is_empty():
		last_error = "%s: %s" % [context, last_error]

	return success


func get_active_coroutine() -> LuaCoroutine:
	if not _running:
		return null
	return _active_coroutine


func _on_hook(_debug: LuaDebug) -> int:
	_executed_instructions += maxi(1, hook_interval)

	if _executed_instructions >= max_instructions:
		_abort_reason = "Lua instruction limit exceeded."
		return LuaThread.HOOK_YIELD

	if Time.get_ticks_msec() - _started_at_ms >= max_duration_ms:
		_abort_reason = "Lua execution time limit exceeded."
		return LuaThread.HOOK_YIELD

	if _active_state.get_memory_used() > max_memory_bytes:
		_abort_reason = "Lua memory limit exceeded."
		return LuaThread.HOOK_YIELD

	return LuaThread.HOOK_OK


func _fail(message: String) -> bool:
	last_error = message
	return false
