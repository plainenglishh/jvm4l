package jvm4l.luau;

public class Globals {
    private Globals() {
        throw new AssertionError();
    }

    public static native void print(Object... message);
    
    public static native void error(Object message, int level);
    public static void error(Object message) {
        error(message, 1);
    }
    public static void error() {
        error("", 1);
    }
}
