package java.lang;

public class Class<T> {
    private Class() {
        throw new AssertionError();
    }

    public native String getName();
}
