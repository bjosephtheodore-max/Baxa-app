// Lance, sur l'émulateur Firestore local, les tests des règles de sécurité
// ET ceux de la fonction serveur de réservation, puis arrête l'émulateur.
// Usage (depuis la racine du projet) :
//   node test/firestore_rules/run.mjs
// Les fichiers s'exécutent l'un après l'autre (--test-concurrency=1) : ils
// partagent la même base d'émulateur, remise à zéro avant chaque test.
//
// firebase-tools est épinglé en 13.x : c'est la dernière version dont
// l'émulateur Firestore accepte Java 17 (les suivantes exigent Java 21).
import {spawnSync} from "node:child_process";
import {fileURLToPath} from "node:url";
import path from "node:path";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const testFiles = [
  "test/firestore_rules/rules.test.mjs",
  "test/server/booking.test.mjs",
].join(" ");

const result = spawnSync(
  "npx",
  [
    "-y", "firebase-tools@13.35.1", "emulators:exec",
    "--only", "firestore",
    "--project", "demo-baxa-rules",
    `"node --test --test-concurrency=1 --test-reporter=spec ${testFiles}"`,
  ],
  {cwd: root, stdio: "inherit", shell: true},
);

// Sous Windows, l'émulateur (processus Java) survit à emulators:exec et
// bloquerait le port au lancement suivant : on l'arrête explicitement.
if (process.platform === "win32") {
  spawnSync("powershell", [
    "-NoProfile", "-Command",
    "Get-CimInstance Win32_Process -Filter \"Name='java.exe'\" | " +
    "Where-Object { $_.CommandLine -like '*cloud-firestore-emulator*' } | " +
    "ForEach-Object { Stop-Process -Id $_.ProcessId -Force }",
  ], {stdio: "ignore"});
}

process.exit(result.status ?? 1);
