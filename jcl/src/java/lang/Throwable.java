package java.lang;

public class Throwable /* implements Serializable */ {
    String message;
    Throwable cause;

    public Throwable() {}

    public Throwable(String message) {
        this.message = message;
    }

    public Throwable(String message, Throwable cause) {
        this.message = message;
        this.cause = cause;
    }
    
    public Throwable getCause() {
        return this.cause;
    }

    public String getMessage() {
        return this.message;
    }
}
