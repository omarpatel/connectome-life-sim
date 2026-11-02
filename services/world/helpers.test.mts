import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { formatSol, parseSol } from "../chain/solana.mts";
import { readJsonWithBackup, writeAtomic, writeAtomicAsync } from "./journal.mts";
import { parseCategory, ROLE, roleFor, rolesFor, type CensusNode } from "./roles.mts";

const node = (category: string | null, side: string | null = null, source_type: string | null = null): CensusNode => ({ id: "sample", category, side, source_type });

test("census categories preserve values containing equals and ignore malformed fields", () => {
  assert.deepEqual(parseCategory(null), {});
  assert.deepEqual(parseCategory("bad;=ignored;type=a=b;superclass=sensory"), { type: "a=b", superclass: "sensory" });
});

test("motor roles preserve leg segment, side, and wing power distinctions", () => {
  assert.equal(roleFor(node("superclass=vnc_motor;subclass=ml", "L")), ROLE.MN_LEG_L2);
  assert.equal(roleFor(node("superclass=vnc_motor;subclass=hl", "R")), ROLE.MN_LEG_R3);
  assert.equal(roleFor(node("superclass=vnc_motor;subclass=fl")), ROLE.NONE);
  assert.equal(roleFor(node("superclass=vnc_motor;subclass=wm;type=DLMn1", "R")), ROLE.MN_WING_POWER_R);
  assert.equal(roleFor(node("superclass=vnc_motor;subclass=wm;type=steer", "L")), ROLE.MN_WING_STEER_L);
});

test("sensory and descending classifications retain laterality and input order", () => {
  const nodes = [node("superclass=sensory;type=R1-R6", "R", "visual"), node("superclass=descending_neuron"), node(null)];
  assert.deepEqual(rolesFor(nodes), Uint8Array.of(ROLE.PR_R1_6_R, ROLE.DN_C, ROLE.NONE));
  assert.equal(roleFor(node("superclass=sensory;type=LB1a", null, "gustatory")), ROLE.GRN_BITTER);
  assert.equal(roleFor(node("superclass=sensory;type=LB3b", null, "gustatory")), ROLE.GRN_SWEET);
});

test("lamport parsing and formatting are exact through u64-sized values", () => {
  for (const amount of [0n, 1n, 999_999_999n, 1_000_000_000n, 18_446_744_073_709_551_615n]) {
    assert.equal(parseSol(formatSol(amount)), amount);
  }
  assert.equal(parseSol(" 1.000000001 "), 1_000_000_001n);
  for (const invalid of ["-1", "1e3", "1.0000000001", "NaN", "1.2SOL"]) {
    assert.throws(() => parseSol(invalid), /not a SOL amount/);
  }
});

test("journal replacement preserves previous JSON and recovers it after corruption", () => {
  const dir = mkdtempSync(join(tmpdir(), "instar-journal-"));
  try {
    const file = join(dir, "journal.json");
    writeAtomic(file, JSON.stringify({ tick: 10 }));
    writeAtomic(file, JSON.stringify({ tick: 20 }));
    assert.deepEqual(JSON.parse(readFileSync(file, "utf8")), { tick: 20 });
    assert.deepEqual(JSON.parse(readFileSync(file + ".bak", "utf8")), { tick: 10 });
    writeFileSync(file, "{torn");
    const messages: string[] = [];
    assert.deepEqual(readJsonWithBackup(file, message => messages.push(message)), { tick: 10 });
    assert.equal(messages.length, 2);
    assert.equal(readJsonWithBackup(join(dir, "absent.json"), () => undefined), null);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("asynchronous snapshot replacement keeps complete binary contents", async () => {
  const dir = mkdtempSync(join(tmpdir(), "instar-snapshot-"));
  try {
    const file = join(dir, "snapshot.bin");
    await writeAtomicAsync(file, Buffer.from([0, 255, 1]));
    await writeAtomicAsync(file, Buffer.from([2, 0, 254, 3]));
    assert.deepEqual(readFileSync(file), Buffer.from([2, 0, 254, 3]));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
