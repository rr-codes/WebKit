function foo(o) {
    for (let p in o) {
        o[p];
    }
}

for (let i=0; i<testLoopCount; i++) {
    foo(new Uint32Array());
    foo({o:undefined});
}
