package jvm4l;

public class Luau {
    private Luau() {
        throw new AssertionError();
    }

    public static native void print(Object... message);
    public static void error(Object message) {
        error(message, 1);
    }
    public static native void error(Object message, int level);
}
