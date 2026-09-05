extends Node
## 数据库编排层（Autoload 单例）。
## 统一封装对玩家表的读写，屏蔽底层是 Supabase 还是 MariaDB，供 PlayerAuth 等业务调用。
##
## 策略：
## - 读：优先 Supabase，失败（网络/HTTP 错误）时回退 MariaDB。
## - 写：Supabase 与 MariaDB 都执行一遍，保持两库同步。
##   创建时以 Supabase 为主，把其分配的 id 一并写入 MariaDB，避免两库 id 错位；
##   仅当 Supabase 创建失败时才退回用 MariaDB 自增 id 创建。
##
## 返回结构沿用 SupabaseClient.request：{ "status": int, "ok": bool, "data": Variant, "raw": String }，
## 读操作 data 为行数组（Array）。

const SUPABASE_TABLE := "players"


## 是否有任一数据源就绪（用于「数据库未就绪」判断）。
func is_any_ready() -> bool:
	return SupabaseClient.is_ready or MariaDBClient.is_ready


## 按用户名查询玩家。
func get_player_by_username(username: String) -> Dictionary:
	if SupabaseClient.is_ready:
		var res := await SupabaseClient.request(
			"%s?username=eq.%s&select=*" % [SUPABASE_TABLE, username.uri_encode()])
		if res.ok:
			return res
		push_warning("[Database] Supabase 读取失败，回退 MariaDB：%s" % res.raw)
	if MariaDBClient.is_ready:
		return await MariaDBClient.get_by_username(username)
	return {"status": 0, "ok": false, "data": null, "raw": "无可用数据源"}


## 按主键 id 查询玩家。
func get_player_by_id(id: int) -> Dictionary:
	if SupabaseClient.is_ready:
		var res := await SupabaseClient.request("%s?id=eq.%d&select=*" % [SUPABASE_TABLE, id])
		if res.ok:
			return res
		push_warning("[Database] Supabase 读取失败，回退 MariaDB：%s" % res.raw)
	if MariaDBClient.is_ready:
		return await MariaDBClient.get_by_id(id)
	return {"status": 0, "ok": false, "data": null, "raw": "无可用数据源"}


## 创建玩家。[param fields] 至少含 username / password_hash。
func create_player(fields: Dictionary) -> Dictionary:
	if SupabaseClient.is_ready:
		var res := await SupabaseClient.request(
			SUPABASE_TABLE, HTTPClient.METHOD_POST, fields,
			PackedStringArray(["Prefer: return=representation"]))
		if res.ok:
			# 主库创建成功：用其分配的 id 同步写入 MariaDB，保持两库一致
			if MariaDBClient.is_ready and res.data is Array and (res.data as Array).size() > 0:
				var row: Dictionary = (res.data as Array)[0]
				var mirror := await MariaDBClient.create(row)
				if not mirror.ok:
					push_warning("[Database] MariaDB 同步创建失败：%s" % mirror.raw)
			return res
		# 用户名冲突等语义错误：以 Supabase 为准直接返回，不再写 MariaDB
		if res.status == 409:
			return res
		push_warning("[Database] Supabase 创建失败，回退 MariaDB：%s" % res.raw)
	if MariaDBClient.is_ready:
		return await MariaDBClient.create(fields)
	return {"status": 0, "ok": false, "data": null, "raw": "无可用数据源"}


## 按 id 更新玩家字段。[param patch] 为要更新的列。
func update_player(id: int, patch: Dictionary) -> Dictionary:
	var primary := {"status": 0, "ok": false, "data": null, "raw": "无可用数据源"}
	var any_ok := false

	if SupabaseClient.is_ready:
		primary = await SupabaseClient.request(
			"%s?id=eq.%d" % [SUPABASE_TABLE, id], HTTPClient.METHOD_PATCH, patch)
		any_ok = any_ok or primary.ok
		if not primary.ok:
			push_warning("[Database] Supabase 更新失败：%s" % primary.raw)

	if MariaDBClient.is_ready:
		var mres := await MariaDBClient.update(id, patch)
		any_ok = any_ok or mres.ok
		if not mres.ok:
			push_warning("[Database] MariaDB 更新失败：%s" % mres.raw)
		# Supabase 未成功时，用 MariaDB 的结果作为主结果返回
		if not primary.ok:
			primary = mres

	primary["ok"] = any_ok
	return primary
