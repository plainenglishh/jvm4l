package java.lang;

public class Throwable /* implements Serializable */ {
    String message;
    Throwable cause;

    public Throwable() {
        fillInBacktrace(1);
    }

    public Throwable(String message) {
        fillInBacktrace(1);
        this.message = message;
    }

    public Throwable(String message, Throwable cause) {
        fillInBacktrace(1);
        this.message = message;
        this.cause = cause;
    }
    
    public Throwable getCause() {
        return this.cause;
    }

    public String getMessage() {
        return this.message;
    }

    public native Throwable fillInStackTrace();
    private native void fillInBacktrace(int skip);
}
