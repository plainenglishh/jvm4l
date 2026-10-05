local fs = require("@std/fs")
local EXCEPTIONS: { [string]: string } = {
    Exception = "Throwable",
    RuntimeException = "Exception",
    Error = "Throwable",
    VirtualMachineError = "Error",

    NullPointerException = "RuntimeException",
    ClassCastException = "RuntimeException",
    ArithmeticException = "RuntimeException",
    IllegalArgumentException = "RuntimeException",
    IndexOutOfBoundsException = "RuntimeException",
    ArrayIndexOutOfBoundsException = "IndexOutOfBoundsException",
    IllegalStateException = "RuntimeException",
    UnsupportedOperationException = "RuntimeException",

    StackOverflowError = "VirtualMachineError",
    OutOfMemoryError = "VirtualMachineError",
    InternalError = "VirtualMachineError",

    LinkageError = "Error",
    UnsatisfiedLinkError = "LinkageError",
    NoClassDefFoundError = "LinkageError",
}

local TEMPLATE = [[package java.lang;

public class $name extends $parent {
    public $name() { super(); }
    public $name(String message) { super(message); }
    public $name(String message, Throwable cause) { super(message, cause); }
}
]]

for name, parent in EXCEPTIONS do
    local src = TEMPLATE:gsub("%$name", name):gsub("%$parent", parent)
    fs.writeStringToFile(`jcl/src/java/lang/exceptions/{name}.java`, src)
end
