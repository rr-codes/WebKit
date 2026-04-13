//@ skip if !$isWasmPlatform
//@ runDefault("--useWasmMultiMemory=1", "--useWasmFastMemory=0")

function leb128(v) {
    const r = [];
    do { let b = v & 0x7F; v >>>= 7; if (v) b |= 0x80; r.push(b); } while (v);
    return r;
}

function buildModule() {
    const b = [];
    const push = (...x) => b.push(...x);
    const pushSec = (id, content) => {
        push(id); push(...leb128(content.length)); push(...content);
    };

    push(0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00);
    pushSec(1, [1, 0x60, 1, 0x7F, 1, 0x7F]);
    pushSec(3, [1, 0]);
    pushSec(5, [2, 0x00, 10, 0x00, 1]);
    pushSec(7, [1, 5, 0x6C, 0x6F, 0x61, 0x64, 0x31, 0x00, 0x00]);
    const f0 = [0x00, 0x20, 0x00, 0x28, 0x42, 0x01, 0x00, 0x0B];
    pushSec(10, [1, ...leb128(f0.length), ...f0]);
    return new Uint8Array(b);
}

const mod = new WebAssembly.Module(buildModule());
const inst = new WebAssembly.Instance(mod);

// Memory 1 = 65536 bytes. i32.load = 4 bytes.
// Max valid address = 65532 (65532 + 4 = 65536).
inst.exports.load1(65532);

// Address 65533: bounds check should fail because 65533 + 3 >= 65536.
// Bug: IPInt checks 65533 >= 65536 (passes) instead of 65536 >= 65536 (fails).
let trapped = false;
try {
    inst.exports.load1(65533);
} catch(e) {
    trapped = true;
}

if (!trapped)
    throw new Error("expected trap");
