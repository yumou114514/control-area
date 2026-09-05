<?php
/**
 * players_api.php — MariaDB 的 HTTP→SQL 网关（供 Godot 标准版调用）。
 *
 * Godot 标准版 GDScript 无法直连 MySQL/MariaDB 协议，故用本脚本充当 REST 接口：
 * 把本文件放到 MariaDB 同站点（phpMyAdmin 所在）的 web 根目录，Godot 通过
 *   http://192.168.10.96/<路径>/players_api.php?action=...
 * 访问。表结构与 Supabase 的 public.players 完全一致（见 players_schema.sql）。
 *
 * 支持的 action：
 *   GET  ?action=get_by_username&username=X   -> { ok, rows:[玩家行] }
 *   GET  ?action=get_by_id&id=N               -> { ok, rows:[玩家行] }
 *   POST ?action=create   body=JSON(可含 id)  -> { ok, rows:[新行] } 用户名冲突返回 409
 *   POST ?action=update   body=JSON(含 id)    -> { ok }
 *
 * 安全：全部使用预处理语句；仅允许白名单列；生产环境请置于内网并加访问控制。
 */

// ===== MariaDB 连接配置（按你的 wstoolbox 部署实际情况修改）=====
const DB_HOST = '127.0.0.1';   // PHP 与 MariaDB 同机时用 127.0.0.1；跨机填内网地址
const DB_PORT = 3306;
const DB_NAME = 'control_area';
const DB_USER = 'root';
const DB_PASS = '';
const DB_CHARSET = 'utf8mb4';

// 允许写入的列白名单（id 单独处理）
const COLUMN_WHITELIST = [
    'username', 'password_hash', 'failed_attempts',
    'last_attempt_date', 'last_login', 'first_entered',
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
        $pdo = new PDO($dsn, DB_USER, DB_PASS, [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ]);
        return $pdo;
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

function rows_to_out(array $rows): array {
    // 规范化类型：id/failed_attempts -> int，first_entered -> bool，其余保持字符串
    $result = [];
    foreach ($rows as $r) {
        if (array_key_exists('id', $r))              $r['id'] = (int)$r['id'];
        if (array_key_exists('failed_attempts', $r)) $r['failed_attempts'] = (int)$r['failed_attempts'];
        if (array_key_exists('first_entered', $r))   $r['first_entered'] = (bool)$r['first_entered'];
        $result[] = $r;
    }
    return $result;
}

$action = $_GET['action'] ?? '';

try {
    $pdo = db();

    switch ($action) {
        case 'get_by_username': {
            $username = $_GET['username'] ?? '';
            $stmt = $pdo->prepare('SELECT * FROM players WHERE username = ? LIMIT 1');
            $stmt->execute([$username]);
            out(['ok' => true, 'rows' => rows_to_out($stmt->fetchAll())]);
        }

        case 'get_by_id': {
            $id = (int)($_GET['id'] ?? 0);
            $stmt = $pdo->prepare('SELECT * FROM players WHERE id = ? LIMIT 1');
            $stmt->execute([$id]);
            out(['ok' => true, 'rows' => rows_to_out($stmt->fetchAll())]);
        }

        case 'create': {
            $body = read_body();
            $username = $body['username'] ?? null;
            $hash = $body['password_hash'] ?? null;
            if (!$username || !$hash) {
                out(['ok' => false, 'error' => '缺少 username / password_hash'], 400);
            }
            $hasId = isset($body['id']) && $body['id'] !== null && $body['id'] !== '';
            if ($hasId) {
                // 带 id：upsert，用于与 Supabase 保持 id 一致（重复 id 时覆盖为最新内容）
                $stmt = $pdo->prepare(
                    'INSERT INTO players (id, username, password_hash, failed_attempts, last_attempt_date, last_login, first_entered)
                     VALUES (?, ?, ?, ?, ?, ?, ?)
                     ON DUPLICATE KEY UPDATE
                        username = VALUES(username),
                        password_hash = VALUES(password_hash),
                        failed_attempts = VALUES(failed_attempts),
                        last_attempt_date = VALUES(last_attempt_date),
                        last_login = VALUES(last_login),
                        first_entered = VALUES(first_entered)'
                );
                $stmt->execute([
                    (int)$body['id'],
                    $username,
                    $hash,
                    (int)($body['failed_attempts'] ?? 0),
                    $body['last_attempt_date'] ?? null,
                    $body['last_login'] ?? null,
                    (int)(bool)($body['first_entered'] ?? false),
                ]);
                $newId = (int)$body['id'];
            } else {
                // 无 id：交给 MariaDB 自增（Supabase 不可用时的降级路径）
                $stmt = $pdo->prepare(
                    'INSERT INTO players (username, password_hash, failed_attempts, last_attempt_date, last_login, first_entered)
                     VALUES (?, ?, ?, ?, ?, ?)'
                );
                $stmt->execute([
                    $username,
                    $hash,
                    (int)($body['failed_attempts'] ?? 0),
                    $body['last_attempt_date'] ?? null,
                    $body['last_login'] ?? null,
                    (int)(bool)($body['first_entered'] ?? false),
                ]);
                $newId = (int)$pdo->lastInsertId();
            }
            $sel = $pdo->prepare('SELECT * FROM players WHERE id = ? LIMIT 1');
            $sel->execute([$newId]);
            out(['ok' => true, 'rows' => rows_to_out($sel->fetchAll())], 201);
        }

        case 'update': {
            $body = read_body();
            $id = (int)($body['id'] ?? 0);
            if ($id <= 0) {
                out(['ok' => false, 'error' => '缺少有效 id'], 400);
            }
            $sets = [];
            $types = '';
            $params = [];
            foreach (COLUMN_WHITELIST as $col) {
                if (array_key_exists($col, $body)) {
                    $sets[] = "$col = ?";
                    $val = $body[$col];
                    if ($col === 'first_entered') {
                        $types .= 'i';
                        $params[] = (int)(bool)$val;
                    } elseif ($col === 'failed_attempts') {
                        $types .= 'i';
                        $params[] = (int)$val;
                    } else {
                        $types .= 's';
                        $params[] = $val === null ? null : (string)$val;
                    }
                }
            }
            if (empty($sets)) {
                out(['ok' => true, 'affected' => 0]);
            }
            $types .= 'i';
            $params[] = $id;
            $sql = 'UPDATE players SET ' . implode(', ', $sets) . ' WHERE id = ?';
            $stmt = $pdo->prepare($sql);
            $stmt->execute($params);
            out(['ok' => true, 'affected' => $stmt->rowCount()]);
        }

        default:
            out(['ok' => false, 'error' => '未知 action: ' . $action], 400);
    }
} catch (PDOException $e) {
    // 1062 = 唯一键冲突（用户名已存在）
    if ((int)$e->errorInfo[1] === 1062) {
        out(['ok' => false, 'error' => '用户名已存在', 'code' => 'duplicate'], 409);
    }
    out(['ok' => false, 'error' => 'SQL 错误: ' . $e->getMessage()], 500);
} catch (Throwable $e) {
    out(['ok' => false, 'error' => $e->getMessage()], 500);
}
