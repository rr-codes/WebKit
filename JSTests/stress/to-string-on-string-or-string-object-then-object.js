function foo(o) {
    return String(o);
}

noInline(foo);

for (var i = 0; i < testLoopCount; ++i) {
    var result = foo(new String("hello"));
    if (typeof result != "string") {
        describe(result);
        throw "Error: result isn't a string";
    }
    if (result != "hello")
        throw "Error: bad result: " + result;
    
    result = foo("world");
    if (typeof result != "string") {
        describe(result);
        throw "Error: result isn't a string";
    }
    if (result != "world")
        throw "Error: bad result: " + result;
}

function Foo() { }

Foo.prototype.toString = function() { return "hello" };

var result = foo(new Foo());
if (typeof result != "string") {
    describe(result);
    throw "Error: result isn't a string";
}
if (result != "hello")
    throw "Error: bad result: " + result;
