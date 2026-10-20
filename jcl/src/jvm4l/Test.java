package jvm4l;

/**
 * Used for testing execution before application class loader is in a usable 
 * state.
 */
public class Test {
    private Test() {
        throw new AssertionError();
    }

    public static native void print_int(int value);
    public static native void error();

    public static int get_1() {
        return 1;
    }

    public static void main() {
        try {
            print_int(1);
            error();
        } catch(jvm4l.LuauError e) {
            print_int(2);
        }

        print_int(3);
    }
}
