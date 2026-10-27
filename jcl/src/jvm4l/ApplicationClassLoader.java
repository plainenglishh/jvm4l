package jvm4l;

public class ApplicationClassLoader extends ClassLoader {
    public ApplicationClassLoader(ClassLoader parent) {
        super(parent);
    }

    protected Class findClass(String name) throws ClassNotFoundException {
        String internalPath = name.replace(".", "/").concat(".class");
        
        byte[] bytecode = findClassBytes(internalPath);
        
        if (bytecode == null) {
            throw new ClassNotFoundException(("Class not found in virtual classpath: ").concat(name));
        }
        
        return defineClass(name, bytecode, 0, bytecode.length);
    }

    private native byte[] findClassBytes(String internalPath);
}
