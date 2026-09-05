-- players_schema.sql
-- 在内网 MariaDB 上创建与 Supabase public.players 完全一致的表结构。
-- 用 phpMyAdmin 的 SQL 面板执行本文件即可。
-- 数据库名需与 players_api.php 中的 DB_NAME 一致（默认 control_area）。

CREATE DATABASE IF NOT EXISTS `control_area`
    DEFAULT CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE `control_area`;

CREATE TABLE IF NOT EXISTS `players` (
    `id`                BIGINT       NOT NULL AUTO_INCREMENT,
    `username`          VARCHAR(64)  NOT NULL,
    `password_hash`     VARCHAR(255) NOT NULL DEFAULT '',
    `failed_attempts`   INT          NOT NULL DEFAULT 0,
    `last_attempt_date` DATE                  DEFAULT NULL,
    `last_login`        DATETIME              DEFAULT NULL,
    `first_entered`     TINYINT(1)   NOT NULL DEFAULT 0,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_players_username` (`username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
