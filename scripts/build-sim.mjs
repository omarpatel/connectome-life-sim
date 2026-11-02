// Build the engine with Rust on PATH, on Windows, macOS or Linux.
// Native tests share the static world and must run single-threaded.
//   node scripts/build-sim.mjs
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const sim = path.join(root, "sim");
const target = path.resolve(sim, process.env.CARGO_TARGET_DIR ?? "target");
const run = (cmd, args) => execFileSync(cmd, args, { cwd: sim, stdio: "inherit" });
run("cargo", ["test", "--profile", "ci", "--", "--test-threads=1"]);
run("rustup", ["target", "add", "wasm32-unknown-unknown"]);
run("cargo", ["build", "--release", "--target", "wasm32-unknown-unknown"]);
fs.mkdirSync(path.join(root, "site"), { recursive: true });
fs.copyFileSync(path.join(target, "wasm32-unknown-unknown", "release", "instar_sim.wasm"), path.join(root, "site", "instar_sim.wasm"));
console.log("SIM_BUILD_OK");
