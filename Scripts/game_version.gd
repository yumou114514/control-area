extends Node
## 游戏版本管理（Autoload 单例）。
## 版本格式：数字 + 渠道字母，如 "1r"（release 正式版）/ "1b"（beta 测试版）。
## 同一版本号下 b < r；版本号数字优先比较。

## 当前客户端版本，发版时在这里更新
const CURRENT_VERSION := "1r"
## 远程版本信息 JSON：{"latestversion": "1r", "minversion": "1r"}
const VERSION_URL := "https://yumou.cc.cd/project/ControlArea/version.json"
## 更新下载地址（弹窗「前往更新」时打开），按实际渠道修改
const UPDATE_URL := "https://yumou.cc.cd/project/ControlArea/"

const _CHANNEL_RANK := {"b": 0, "r": 1}


## 解析版本字符串，如 "1r" → {"num": 1, "channel": "r"}
static func parse(version: String) -> Dictionary:
	var v := version.strip_edges().to_lower()
	var channel := "r"
	if v.ends_with("b") or v.ends_with("r"):
		channel = v.right(1)
		v = v.left(v.length() - 1)
	return {"num": v.to_int(), "channel": channel}


## 比较两个版本：a<b 返回 -1，相等返回 0，a>b 返回 1
static func compare(a: String, b: String) -> int:
	var pa := parse(a)
	var pb := parse(b)
	if pa.num != pb.num:
		return -1 if pa.num < pb.num else 1
	var ra: int = _CHANNEL_RANK.get(pa.channel, 0)
	var rb: int = _CHANNEL_RANK.get(pb.channel, 0)
	if ra != rb:
		return -1 if ra < rb else 1
	return 0
