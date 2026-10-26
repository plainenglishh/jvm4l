package jvm4l;

import jvm4l.luau.Globals;

/**
 * Used for testing execution before application class loader is in a usable 
 * state.
 */
public class Test {
    private Test() {
        throw new AssertionError();
    }

    public static void main() {
        Globals.error("Hello, World!");
    }
}
