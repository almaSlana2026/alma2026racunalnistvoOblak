<?php
// VAJA-07 — vstavi.php
// Vstavi nov element nakupnega seznama v tabelo AlmaMater.nakup.

require_once 'db.php';

$element = trim($_POST['element'] ?? '');
$kolicina = $_POST['kolicina'] ?? '';

$error = null;
if ($element === '' || $kolicina === '' || !ctype_digit((string)$kolicina)) {
    $error = "Element in količina sta obvezna; količina mora biti celo število.";
} else {
    $kolicina = (int)$kolicina;
    $stmt = $conn->prepare("INSERT INTO nakup (element, kolicina) VALUES (?, ?)");
    if (!$stmt) {
        $error = "Priprava stavka ni uspela: " . $conn->error;
    } else {
        $stmt->bind_param("si", $element, $kolicina);
        if (!$stmt->execute()) {
            $error = "Napaka pri vstavljanju: " . $stmt->error;
        }
        $stmt->close();
    }
}
$conn->close();
?>
<!DOCTYPE html>
<html lang="sl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Nakupni seznam — vnos</title>
    <link rel="stylesheet" href="styles.css">
</head>
<body>
    <main class="container">
        <div class="card">
            <h1>Nakupni seznam</h1>
            <?php if ($error): ?>
                <p class="subtitle">Vnosa ni bilo mogoče shraniti.</p>
                <div class="notice error">
                    <?= htmlspecialchars($error) ?>
                </div>
            <?php else: ?>
                <p class="subtitle">Element je shranjen v bazo.</p>
                <div class="notice">
                    <strong><?= htmlspecialchars($element) ?></strong> &nbsp;·&nbsp; količina <?= (int)$kolicina ?>
                </div>
            <?php endif; ?>
            <div class="links">
                <a href="index.html">← Nov vnos</a>
                <a href="izpis.php">Prikaži seznam →</a>
            </div>
        </div>
    </main>
</body>
</html>
