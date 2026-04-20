-- VAJA-07 — setup-db.sql
-- Ustvari bazo AlmaMater, tabelo nakup (nakupni seznam), uporabnika urban
-- in dva testna podatka.
--
-- Avtor: Urban Ambrožič

DROP DATABASE IF EXISTS AlmaMater;
CREATE DATABASE AlmaMater CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE AlmaMater;

CREATE TABLE nakup (
    id INT AUTO_INCREMENT PRIMARY KEY,
    element VARCHAR(100) NOT NULL,
    kolicina INT NOT NULL
);

INSERT INTO nakup (element, kolicina) VALUES
    ('kruh',  2),
    ('mleko', 1);

-- Uporabnik 'urban' s pravicami admina nad bazo AlmaMater.
-- Host '%' dovoli povezavo iz kateregakoli naslova znotraj VPC-ja (npr. EC2-1 po privatnem IP).
DROP USER IF EXISTS 'urban'@'%';
CREATE USER 'urban'@'%' IDENTIFIED BY 'urban';
GRANT ALL PRIVILEGES ON AlmaMater.* TO 'urban'@'%';
FLUSH PRIVILEGES;
