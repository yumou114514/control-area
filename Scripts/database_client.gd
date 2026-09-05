extends Node
## 数据库编排层（Autoload 单例）。
## 统一封装对 MariaDB 的读写，供 PlayerAuth 等业务调用；MariaDB 为唯一数据源，
## 经 MariaDBClient（内网 PHP 网关 db_api.php）访问。
##
## 返回结构沿用 MariaDBClient：{ "status": int, "ok": bool, "data": Variant, "raw": String }，
## 读操作 data 为行数组（Array）。

const PLAYERS := "players"
const PLAYER_DATA := "player_data"


## 数据源是否就绪（用于「数据库未就绪」判断）。
func is_any_ready() -> bool:
	return MariaDBClient.is_ready


# ---------- players（认证） ----------

## 按用户名查询玩家。
func get_player_by_username(username: String) -> Dictionary:
	return await MariaDBClient.select(PLAYERS, {"username": username}, 1)


## 按主键 id 查询玩家。
func get_player_by_id(id: int) -> Dictionary:
	return await MariaDBClient.select(PLAYERS, {"id": id}, 1)


## 创建玩家。[param fields] 至少含 username / password_hash。
## 成功返回 data = [新行]、status 201；用户名冲突返回 status 409。
func create_player(fields: Dictionary) -> Dictionary:
	return await MariaDBClient.insert(PLAYERS, fields)


## 按 id 更新玩家字段。[param patch] 为要更新的列。
func update_player(id: int, patch: Dictionary) -> Dictionary:
	return await MariaDBClient.update(PLAYERS, {"id": id}, patch)


## 按 id 删除玩家（player_data 由外键级联清理）。
func delete_player(id: int) -> Dictionary:
	return await MariaDBClient.delete(PLAYERS, {"id": id})


# ---------- player_data（通用键值业务数据） ----------

## 读取单个键值；未找到返回 [param default]。值以文本存储（见 _stringify_value）。
func get_player_data(player_id: int, key: String, default: Variant = null) -> Variant:
	var res := await MariaDBClient.select(PLAYER_DATA, {"player_id": player_id, "data_key": key}, 1)
	if res.ok and res.data is Array and (res.data as Array).size() > 0:
		return (res.data as Array)[0].get("data_value", default)
	return default


## 读取某玩家全部键值，返回 { key: value }。
func get_all_player_data(player_id: int) -> Dictionary:
	var result := {}
	var res := await MariaDBClient.select(PLAYER_DATA, {"player_id": player_id})
	if res.ok and res.data is Array:
		for row in res.data:
			if row is Dictionary:
				var r: Dictionary = row
				result[str(r.get("data_key", ""))] = r.get("data_value", null)
	return result


## 写入（存在则更新）单个键值。
func set_player_data(player_id: int, key: String, value: Variant) -> Dictionary:
	var payload := {"player_id": player_id, "data_key": key, "data_value": _stringify_value(value)}
	return await MariaDBClient.upsert(PLAYER_DATA, payload)


## 删除单个键值。
func delete_player_data(player_id: int, key: String) -> Dictionary:
	return await MariaDBClient.delete(PLAYER_DATA, {"player_id": player_id, "data_key": key})


## data_value 列为 LONGTEXT：字典/数组序列化为 JSON 文本，其余转为字符串。
func _stringify_value(value: Variant) -> String:
	if value is Dictionary or value is Array:
		return JSON.stringify(value)
	return str(value)
