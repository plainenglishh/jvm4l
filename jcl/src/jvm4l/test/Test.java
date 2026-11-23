package jvm4l.test;

import static jvm4l.luau.Globals.error;
import static jvm4l.luau.Globals.print;

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
        int value = loop();
        print_int(value);
    }
}
