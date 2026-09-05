-- schema.sql
-- 在内网 MariaDB 上创建 ControlArea 的数据库表结构。
-- phpMyAdmin 友好版：不用 USE（批量执行时 USE 不会作用于后续语句，会报 #1046），
-- 表名全限定为 control_area.<表名>，整个文件可直接粘贴到 SQL 面板一次执行（可重复执行）。
-- 数据库名需与 db_api.php 中的 DB_NAME 一致（默认 control_area）。

CREATE DATABASE IF NOT EXISTS `control_area`
    DEFAULT CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

-- 认证表：注册/登录、登录限流、首次进入标记
CREATE TABLE IF NOT EXISTS `control_area`.`players` (
    `id`                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `username`          VARCHAR(64)     NOT NULL,
    `password_hash`     VARCHAR(255)    NOT NULL DEFAULT '',
    `failed_attempts`   INT UNSIGNED    NOT NULL DEFAULT 0,
    `last_attempt_date` DATE                     DEFAULT NULL,
    `last_login`        DATETIME                 DEFAULT NULL,
    `first_entered`     TINYINT(1)      NOT NULL DEFAULT 0,
    `created_at`        DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`        DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_players_username` (`username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 通用键值业务数据表：一人多行，随玩家删除级联清理。
-- 后续玩法（进度、背包、设置等）以 data_key 区分，data_value 存字符串/数字/JSON 文本。
CREATE TABLE IF NOT EXISTS `control_area`.`player_data` (
    `player_id`  BIGINT UNSIGNED NOT NULL,
    `data_key`   VARCHAR(128)    NOT NULL,
    `data_value` LONGTEXT                 DEFAULT NULL,
    `updated_at` DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`player_id`, `data_key`),
    CONSTRAINT `fk_player_data_player` FOREIGN KEY (`player_id`)
        REFERENCES `control_area`.`players` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
