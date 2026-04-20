<?php
// VAJA-07 — izpis.php
// Prikaže vse elemente nakupnega seznama iz tabele AlmaMater.nakup.

require_once 'db.php';
$sql = "SELECT id, element, kolicina FROM nakup ORDER BY id";
$result = $conn->query($sql);
?>
<!DOCTYPE html>
<html lang="sl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Nakupni seznam — pregled</title>
    <link rel="stylesheet" href="styles.css">
</head>
<body>
    <main class="container">
        <div class="card">
            <h1>Nakupni seznam</h1>
            <p class="subtitle">Pregled vseh elementov v bazi.</p>

            <?php if ($result && $result->num_rows > 0): ?>
                <table>
                    <thead>
                        <tr>
                            <th style="width: 56px">ID</th>
                            <th>Element</th>
                            <th style="width: 92px; text-align:right;">Količina</th>
                        </tr>
                    </thead>
                    <tbody>
                    <?php while ($row = $result->fetch_assoc()): ?>
                        <tr>
                            <td class="num"><?= (int)$row["id"] ?></td>
                            <td><?= htmlspecialchars($row["element"]) ?></td>
                            <td class="num" style="text-align:right;"><?= (int)$row["kolicina"] ?></td>
                        </tr>
                    <?php endwhile; ?>
                    </tbody>
                </table>
            <?php else: ?>
                <p class="empty">Seznam je prazen.</p>
            <?php endif; ?>

            <div class="links">
                <a href="index.html">← Nov vnos</a>
            </div>
        </div>
    </main>
</body>
</html>
<?php $conn->close(); ?>
