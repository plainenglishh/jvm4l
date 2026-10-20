package java.lang;

public abstract class ClassLoader {
    private ClassLoader parent;

    protected ClassLoader() {
        this(null);
    }

    protected ClassLoader(ClassLoader parent) {
        this.parent = parent;
    }

    protected Class findClass(String name) throws ClassNotFoundException {
        throw new ClassNotFoundException(name);
    }

    public Class loadClass(String name) throws ClassNotFoundException {
        return findClass(name);
    }

    protected final Class defineClass(String name, byte[] b, int off, int len) {
        return null; 
    }
}
