package jvm4l;

public class Luau {
    static native void print(Object message);

    static native void error(Object message, int level);
}
