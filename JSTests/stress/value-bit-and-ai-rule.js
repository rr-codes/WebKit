function assert(a, e) {
    if (a !== e)
        throw new Error("Expected: " + e + " bug got: " + a);
}

let predicate = true;
function foo(a) {
    let v = a;
    if (predicate)
        v = 0b1010;

    let c = v & 0b11;
    return c;
}
noInline(foo);

for (let i = 0; i < testLoopCount; i++) {
    assert(foo(0b1010n), 0b10);
}

