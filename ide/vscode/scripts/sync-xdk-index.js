const fs = require("fs");
const path = require("path");

const source = path.join(__dirname, "..", "..", "xdk", "index.json");
const targetDir = path.join(__dirname, "..", "xdk");
const target = path.join(targetDir, "index.json");

try {
  fs.mkdirSync(targetDir, { recursive: true });
  fs.copyFileSync(source, target);
} catch (err) {
  console.error(`sync-xdk-index: 无法同步 ${source} -> ${target}: ${err.message}`);
  process.exit(1);
}
