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

    public static void main() {
        print_int(1);
    }
}
