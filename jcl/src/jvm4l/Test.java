package jvm4l;

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
    public static native void error();

    static void error_wrapper() {
        error();
    }

    static int get_1() {
        return 1;
    }

    public static void main() {
        try {
            calls_error_wrapper();
        } catch (LuauError test) {
            print_int(1);
        }
    }
}
