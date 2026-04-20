<?php
// VAJA-07 — Skupna konfiguracija povezave do MariaDB baze na EC2-2.
// $host je zasebni IP naslov EC2-2 znotraj VPC 192.168.0.0/24 (substitucija v deploy skripti).

$host = "__DB_HOST__";
$dbname = "AlmaMater";
$username = "urban";
$password = "urban";

$conn = new mysqli($host, $username, $password, $dbname);
if ($conn->connect_error) {
    die("Povezava na bazo ni uspela: " . $conn->connect_error);
}
$conn->set_charset("utf8mb4");
?>
