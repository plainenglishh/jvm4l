package sun.misc;

import java.lang.ClassLoader;
import java.lang.Class;
import java.lang.String;
import java.lang.ClassNotFoundException;

public class Launcher {
    private static Launcher launcher = new Launcher();
    private ClassLoader appClassLoader;

    public static Launcher getLauncher() {
        return launcher;
    }

    public Launcher() {
        this.appClassLoader = new AppClassLoader(null);
    }

    public ClassLoader getClassLoader() {
        return this.appClassLoader;
    }

    public static class AppClassLoader extends ClassLoader {
        
        public AppClassLoader(ClassLoader parent) {
            super(parent);
        }

        protected Class findClass(String name) throws ClassNotFoundException {
            byte[] classBytes = fetchAppClassBytes(name);
            
            if (classBytes == null) {
                throw new ClassNotFoundException(name);
            }

            return defineClass(name, classBytes, 0, classBytes.length);
        }

        private static native byte[] fetchAppClassBytes(String className);
    }
}
