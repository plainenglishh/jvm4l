package jvm4l;

import static jvm4l.luau.Globals.error;

/**
 * Used for testing execution before application class loader is in a usable 
 * state.
 */
public class Test {
    private Test() {
        throw new AssertionError();
    }

    public static void main() {
        error("Hello, World!");
    }
}
