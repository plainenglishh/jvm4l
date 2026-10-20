package jvm4l;

/**
 * Used for testing execution before application class loader is in a usable 
 * state.
 */
public class Test {
    private Test() {
        throw new AssertionError();
    }

    public static void main() {
        try {
            jvm4l.Luau.error("Hello, World!");
        } catch (Exception e) {
            jvm4l.Luau.print("whoops");
        }
    }
}
