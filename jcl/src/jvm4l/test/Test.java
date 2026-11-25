package jvm4l.test;

import static jvm4l.luau.Globals.error;
import static jvm4l.luau.Globals.print;

import jvm4l.Debug;

/**
 * Used for testing execution before application class loader is in a usable 
 * state.
 */
public class Test {
    private Test() {
        throw new AssertionError();
    }

    public static native void print_int(int value);
    public static native void print_string(String value);

    private static int loop() {
        int i = 0;
        while (i < 1_000_000) {
            i++;
        }
        return i;
    }

    public static void main() throws Exception {
        Object o = new Object();
        print_string(o.getClass().getName());

        try {
            int value = loop();
            print_int(value);
        } catch (Exception e) {
            print_string("Something horrible has happened!");
        }
    }
}
