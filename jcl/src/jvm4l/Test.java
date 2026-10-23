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

    public static native void calls_error_wrapper();
    public static native void print_int(int value);

    static void error_wrapper() {
        Globals.error();
    }

    static int get_1() {
        return 1;
    }

    public static void main() {
        calls_error_wrapper();
    }
}
