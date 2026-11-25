package jvm4l;

public final class Debug {
    private Debug() {
        throw new AssertionError();
    }

    public native static void dumpStack();
}
