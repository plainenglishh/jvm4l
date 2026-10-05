package java.lang;

public class LuauError extends Error {
    public LuauError() { super(); }
    public LuauError(String message) { super(message); }
    public LuauError(String message, Throwable cause) { super(message, cause); }
}
