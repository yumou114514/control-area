<?php
/**
 * db_api.php — MariaDB 的多表通用 HTTP→SQL 网关（供 Godot 标准版调用）。
 *
 * Godot 标准版 GDScript 无法直连 MySQL/MariaDB 协议，故用本脚本充当 REST 接口：
 * 把本文件放到 MariaDB 同站点（phpMyAdmin 所在）的 web 根目录，Godot 通过
 *   POST http://192.168.10.96:8081/db_api.php
 * 访问。表结构见 schema.sql。
 *
 * 请求体（JSON）：
 *   {
 *     "table": "players" | "player_data",
 *     "op":    "select" | "insert" | "update" | "upsert" | "delete",
 *     "where": { 列: 值, ... },   // 等值过滤（AND），select/update/delete 用
 *     "data":  { 列: 值, ... },   // insert/update/upsert 的列值
 *     "limit": n                  // 可选，仅 select 生效
 *   }
 *
 * 响应（JSON）：
 *   { "ok": bool, "rows": [...], "affected": n, "insertId": n, "error": str, "code": str }
 *
 * 安全：仅允许白名单表与列；全部使用预处理语句；生产环境请置于内网并加访问控制。
 */

// ===== MariaDB 连接配置（按你的 wstoolbox 部署实际情况修改）=====
const DB_HOST = '127.0.0.1';   // PHP 与 MariaDB 同机时用 127.0.0.1；跨机填内网地址
const DB_PORT = 3306;
const DB_NAME = 'control_area';
const DB_USER = 'root';
const DB_PASS = '';
const DB_CHARSET = 'utf8mb4';

// ===== 表定义白名单 =====
// pk      : 主键列（update/upsert/delete 定位用）
// columns : 允许写入/过滤的列（不含自增主键 id，id 仅在带值时特殊处理）
// ints    : 读取时需规整为 int 的列
// bools   : 读取时需规整为 bool 的列
const TABLES = [
    'players' => [
        'pk'      => ['id'],
        'columns' => ['username', 'password_hash', 'failed_attempts', 'last_attempt_date', 'last_login', 'first_entered'],
        'ints'    => ['id', 'failed_attempts'],
        'bools'   => ['first_entered'],
    ],
    'player_data' => [
        'pk'      => ['player_id', 'data_key'],
        'columns' => ['player_id', 'data_key', 'data_value'],
        'ints'    => ['player_id'],
        'bools'   => [],
    ],
];

header('Content-Type: application/json; charset=utf-8');

function out(array $payload, int $code = 200): void {
    http_response_code($code);
    echo json_encode($payload, JSON_UNESCAPED_UNICODE);
    exit;
}

function db(): PDO {
    try {
        $dsn = sprintf('mysql:host=%s;port=%d;dbname=%s;charset=%s', DB_HOST, DB_PORT, DB_NAME, DB_CHARSET);
        return new PDO($dsn, DB_USER, DB_PASS, [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ]);
    } catch (Throwable $e) {
        out(['ok' => false, 'error' => '数据库连接失败: ' . $e->getMessage()], 500);
    }
}

function read_body(): array {
    $raw = file_get_contents('php://input');
    if ($raw === false || $raw === '') {
        return [];
    }
    $data = json_decode($raw, true);
    return is_array($data) ? $data : [];
}

/** 取表定义；不在白名单则报错退出。 */
function table_def(string $table): array {
    if (!isset(TABLES[$table])) {
        out(['ok' => false, 'error' => '未知表: ' . $table], 400);
    }
    return TABLES[$table];
}

/** 判断某列是否可写/可过滤（白名单，含主键列）。 */
function is_allowed_column(array $def, string $col): bool {
    return in_array($col, $def['columns'], true) || in_array($col, $def['pk'], true);
}

/** 按表定义规整单个列值类型（int/bool），其余保持字符串或 null。 */
function normalize_value(array $def, string $col, $val) {
    if ($val === null) {
        return null;
    }
    if (in_array($col, $def['bools'], true)) {
        return (int)(bool)$val;
    }
    if (in_array($col, $def['ints'], true)) {
        return (int)$val;
    }
    return is_string($val) ? $val : (string)$val;
}

/** 规整输出行的类型（id/failed_attempts/player_id -> int，first_entered -> bool）。 */
function rows_to_out(array $def, array $rows): array {
    $result = [];
    foreach ($rows as $r) {
        foreach ($def['ints'] as $col) {
            if (array_key_exists($col, $r) && $r[$col] !== null) {
                $r[$col] = (int)$r[$col];
            }
        }
        foreach ($def['bools'] as $col) {
            if (array_key_exists($col, $r)) {
                $r[$col] = (bool)$r[$col];
            }
        }
        $result[] = $r;
    }
    return $result;
}

/**
 * 构建 WHERE 子句与参数；只接受白名单列，空 where 返回 ['', []]。
 * 若 $requirePk 为真，则 where 必须覆盖全部主键列。
 */
function build_where(array $def, array $where, bool $requirePk = false): array {
    if ($requirePk) {
        foreach ($def['pk'] as $pk) {
            if (!array_key_exists($pk, $where)) {
                out(['ok' => false, 'error' => 'where 缺少主键列: ' . $pk], 400);
            }
        }
    }
    $conds = [];
    $params = [];
    foreach ($where as $col => $val) {
        if (!is_allowed_column($def, (string)$col)) {
            out(['ok' => false, 'error' => '非法过滤列: ' . $col], 400);
        }
        $conds[] = "`$col` = ?";
        $params[] = normalize_value($def, (string)$col, $val);
    }
    return [$conds, $params];
}

/** 从 data 中挑出白名单列，返回 [列名数组, 规整后的值数组]。 */
function pick_columns(array $def, array $data): array {
    $cols = [];
    $vals = [];
    foreach ($def['columns'] as $col) {
        if (array_key_exists($col, $data)) {
            $cols[] = $col;
            $vals[] = normalize_value($def, $col, $data[$col]);
        }
    }
    return [$cols, $vals];
}

/** 按主键查询单行（用于 insert/upsert 后回读）。 */
function fetch_by_pk(PDO $pdo, array $def, string $table, array $pkValues): array {
    $conds = [];
    $params = [];
    foreach ($def['pk'] as $pk) {
        $conds[] = "`$pk` = ?";
        $params[] = normalize_value($def, $pk, $pkValues[$pk] ?? null);
    }
    $sql = "SELECT * FROM `$table` WHERE " . implode(' AND ', $conds) . ' LIMIT 1';
    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    return rows_to_out($def, $stmt->fetchAll());
}

$body = read_body();
$table = (string)($body['table'] ?? '');
$op = (string)($body['op'] ?? '');
$where = is_array($body['where'] ?? null) ? $body['where'] : [];
$data = is_array($body['data'] ?? null) ? $body['data'] : [];

try {
    $def = table_def($table);
    $pdo = db();

    switch ($op) {
        case 'select': {
            [$conds, $params] = build_where($def, $where);
            $sql = "SELECT * FROM `$table`";
            if (!empty($conds)) {
                $sql .= ' WHERE ' . implode(' AND ', $conds);
            }
            $limit = isset($body['limit']) ? (int)$body['limit'] : 0;
            if ($limit > 0) {
                $sql .= ' LIMIT ' . $limit;
            }
            $stmt = $pdo->prepare($sql);
            $stmt->execute($params);
            out(['ok' => true, 'rows' => rows_to_out($def, $stmt->fetchAll())]);
        }

        case 'insert': {
            [$cols, $vals] = pick_columns($def, $data);
            // 允许显式携带主键 id 做对齐写入（仅单列自增主键场景）
            $hasExplicitId = isset($data['id']) && $data['id'] !== null && $data['id'] !== ''
                && in_array('id', $def['pk'], true) && !in_array('id', $cols, true);
            if ($hasExplicitId) {
                array_unshift($cols, 'id');
                array_unshift($vals, (int)$data['id']);
            }
            if (empty($cols)) {
                out(['ok' => false, 'error' => '缺少可写入的列'], 400);
            }
            $placeholders = implode(', ', array_fill(0, count($cols), '?'));
            $colSql = implode(', ', array_map(fn($c) => "`$c`", $cols));
            $stmt = $pdo->prepare("INSERT INTO `$table` ($colSql) VALUES ($placeholders)");
            $stmt->execute($vals);
            // 回读新行：单列自增主键用 lastInsertId，复合主键用 data 中的 pk 值
            if (count($def['pk']) === 1 && !$hasExplicitId) {
                $pkValues = [$def['pk'][0] => $pdo->lastInsertId()];
            } else {
                $pkValues = [];
                foreach ($def['pk'] as $pk) {
                    $pkValues[$pk] = $data[$pk] ?? null;
                }
            }
            $rows = fetch_by_pk($pdo, $def, $table, $pkValues);
            out(['ok' => true, 'rows' => $rows, 'insertId' => (int)$pdo->lastInsertId()], 201);
        }

        case 'update': {
            [$cols, $vals] = pick_columns($def, $data);
            if (empty($cols)) {
                out(['ok' => true, 'affected' => 0]);
            }
            [$conds, $wparams] = build_where($def, $where, true);
            $setSql = implode(', ', array_map(fn($c) => "`$c` = ?", $cols));
            $sql = "UPDATE `$table` SET $setSql WHERE " . implode(' AND ', $conds);
            $stmt = $pdo->prepare($sql);
            $stmt->execute(array_merge($vals, $wparams));
            out(['ok' => true, 'affected' => $stmt->rowCount()]);
        }

        case 'upsert': {
            [$cols, $vals] = pick_columns($def, $data);
            // 主键列也允许出现在 data 中（如 player_data 的 player_id/data_key）
            foreach ($def['pk'] as $pk) {
                if (array_key_exists($pk, $data) && !in_array($pk, $cols, true)) {
                    array_unshift($cols, $pk);
                    array_unshift($vals, normalize_value($def, $pk, $data[$pk]));
                }
            }
            if (empty($cols)) {
                out(['ok' => false, 'error' => '缺少可写入的列'], 400);
            }
            // ON DUPLICATE KEY UPDATE 只更新非主键列
            $updateCols = array_values(array_filter($cols, fn($c) => !in_array($c, $def['pk'], true)));
            $placeholders = implode(', ', array_fill(0, count($cols), '?'));
            $colSql = implode(', ', array_map(fn($c) => "`$c`", $cols));
            $sql = "INSERT INTO `$table` ($colSql) VALUES ($placeholders)";
            if (!empty($updateCols)) {
                $dupSql = implode(', ', array_map(fn($c) => "`$c` = VALUES(`$c`)", $updateCols));
                $sql .= " ON DUPLICATE KEY UPDATE $dupSql";
            }
            $stmt = $pdo->prepare($sql);
            $stmt->execute($vals);
            $pkValues = [];
            foreach ($def['pk'] as $pk) {
                $pkValues[$pk] = $data[$pk] ?? (count($def['pk']) === 1 ? $pdo->lastInsertId() : null);
            }
            $rows = fetch_by_pk($pdo, $def, $table, $pkValues);
            out(['ok' => true, 'rows' => $rows, 'affected' => $stmt->rowCount()]);
        }

        case 'delete': {
            if (empty($where)) {
                out(['ok' => false, 'error' => 'delete 需要 where 条件'], 400);
            }
            [$conds, $params] = build_where($def, $where);
            if (empty($conds)) {
                out(['ok' => false, 'error' => 'delete 需要有效 where 条件'], 400);
            }
            $sql = "DELETE FROM `$table` WHERE " . implode(' AND ', $conds);
            $stmt = $pdo->prepare($sql);
            $stmt->execute($params);
            out(['ok' => true, 'affected' => $stmt->rowCount()]);
        }

        default:
            out(['ok' => false, 'error' => '未知 op: ' . $op], 400);
    }
} catch (PDOException $e) {
    // 1062 = 唯一键冲突（如用户名已存在）
    if ((int)$e->errorInfo[1] === 1062) {
        out(['ok' => false, 'error' => '记录已存在', 'code' => 'duplicate'], 409);
    }
    out(['ok' => false, 'error' => 'SQL 错误: ' . $e->getMessage()], 500);
} catch (Throwable $e) {
    out(['ok' => false, 'error' => $e->getMessage()], 500);
}
