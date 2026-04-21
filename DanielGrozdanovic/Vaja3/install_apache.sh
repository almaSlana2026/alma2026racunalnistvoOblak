#!/bin/bash
apt-get update -y
apt-get install apache2 -y
systemctl start apache2
systemctl enable apache2
echo "<h1>Deluje! Instance: $(hostname)</h1>" > /var/www/html/index.html