import java.nio.file.Files;
import java.nio.file.Path;
import java.util.jar.JarFile;
import java.util.jar.JarOutputStream;
import java.util.zip.ZipEntry;
import org.objectweb.asm.ClassReader;
import org.objectweb.asm.ClassVisitor;
import org.objectweb.asm.ClassWriter;
import org.objectweb.asm.FieldVisitor;
import org.objectweb.asm.MethodVisitor;
import org.objectweb.asm.Opcodes;
import org.objectweb.asm.Type;
import org.objectweb.asm.commons.GeneratorAdapter;
import org.objectweb.asm.commons.Method;

/** Applies compatibility fixes to the checksum-pinned upstream v16 runtime. */
public final class BytecodeOverlay {
    private static final String CLASS_HIERARCHY = "mextensionserver/util/BytecodeEditor$ClassHierarchy.class";
    private static final String ANALYZER = "org/objectweb/asm/tree/analysis/Analyzer";
    private static final String ANALYZE_SIGNATURE =
            "(Ljava/lang/String;Lorg/objectweb/asm/tree/MethodNode;)[Lorg/objectweb/asm/tree/analysis/Frame;";
    private static final Type COMPRESSION = Type.getObjectType("okhttp3/CompressionInterceptor");
    private static final Type ALGORITHM =
            Type.getObjectType("okhttp3/CompressionInterceptor$DecompressionAlgorithm");
    private static final Type ALGORITHMS = Type.getType("[" + ALGORITHM.getDescriptor());
    private static final String CONSTRUCTOR_SIGNATURE = "(" + ALGORITHMS.getDescriptor() + ")V";
    private static final Method SUPPORTED_ALGORITHMS =
            new Method("kuchieSupportedAlgorithms", ALGORITHMS, new Type[] {ALGORITHMS});
    private static final String IMAGE_PROXY = "mextensionserver/impl/MihonImageProxy";
    private static final String IMAGE_SECRET = "kuchieImageTokenSecret";

    public static void main(String[] arguments) throws Exception {
        if (arguments.length != 2) {
            throw new IllegalArgumentException("Provide the upstream JAR and overlay destination");
        }
        try (var input = new JarFile(arguments[0]);
             var output = new JarOutputStream(Files.newOutputStream(Path.of(arguments[1])))) {
            writeClass(output, CLASS_HIERARCHY, fixDexAnalysis(readClass(input, CLASS_HIERARCHY)));
            String compressionClass = COMPRESSION.getInternalName() + ".class";
            writeClass(output, compressionClass, fixCompression(readClass(input, compressionClass)));
            String imageProxyClass = IMAGE_PROXY + ".class";
            writeClass(output, imageProxyClass, protectImageTokens(readClass(input, imageProxyClass)));
        }
    }

    private static ClassReader readClass(JarFile input, String name) throws Exception {
        var entry = input.getJarEntry(name);
        if (entry == null) {
            throw new IllegalArgumentException("Missing pinned runtime class: " + name);
        }
        try (var bytecode = input.getInputStream(entry)) {
            return new ClassReader(bytecode);
        }
    }

    private static void writeClass(JarOutputStream output, String name, byte[] bytecode) throws Exception {
        output.putNextEntry(new ZipEntry(name));
        output.write(bytecode);
        output.closeEntry();
    }

    private static byte[] fixDexAnalysis(ClassReader input) {
        // DEX translation can undercount the operand stack slots. Upstream routes every
        // analysis through one helper that retries with a larger bound; computing the
        // exact limits first lets the allocation repair reach the method on the first pass.
        int[] replaced = {0};
        var writer = new ClassWriter(0);
        input.accept(new ClassVisitor(Opcodes.ASM9, writer) {
            @Override
            public MethodVisitor visitMethod(int access, String name, String descriptor,
                    String signature, String[] exceptions) {
                var delegate = super.visitMethod(access, name, descriptor, signature, exceptions);
                return new MethodVisitor(Opcodes.ASM9, delegate) {
                    @Override
                    public void visitMethodInsn(int opcode, String owner, String name,
                            String descriptor, boolean isInterface) {
                        if (opcode == Opcodes.INVOKEVIRTUAL && ANALYZER.equals(owner)
                                && "analyze".equals(name) && ANALYZE_SIGNATURE.equals(descriptor)) {
                            name = "analyzeAndComputeMaxs";
                            replaced[0]++;
                        }
                        super.visitMethodInsn(opcode, owner, name, descriptor, isInterface);
                    }
                };
            }
        }, 0);
        if (replaced[0] != 1) {
            throw new IllegalArgumentException("Expected 1 runtime ASM analysis call. Found " + replaced[0]);
        }
        return writer.toByteArray();
    }

    private static byte[] fixCompression(ClassReader input) {
        // The iOS runtime has no Zstandard JNI library. Keep the remaining codecs
        // in their original order for both negotiation and decompression.
        int[] replaced = {0};
        var writer = new ClassWriter(ClassWriter.COMPUTE_FRAMES);
        input.accept(new ClassVisitor(Opcodes.ASM9, writer) {
            @Override
            public MethodVisitor visitMethod(int access, String name, String descriptor,
                    String signature, String[] exceptions) {
                var delegate = super.visitMethod(access, name, descriptor, signature, exceptions);
                if (!name.equals("<init>") || !descriptor.equals(CONSTRUCTOR_SIGNATURE)) {
                    return delegate;
                }
                return new MethodVisitor(Opcodes.ASM9, delegate) {
                    @Override
                    public void visitFieldInsn(int opcode, String owner, String name, String descriptor) {
                        if (opcode == Opcodes.PUTFIELD && owner.equals(COMPRESSION.getInternalName())
                                && name.equals("algorithms") && descriptor.equals(ALGORITHMS.getDescriptor())) {
                            super.visitMethodInsn(Opcodes.INVOKESTATIC, owner,
                                    SUPPORTED_ALGORITHMS.getName(), SUPPORTED_ALGORITHMS.getDescriptor(), false);
                            replaced[0]++;
                        }
                        super.visitFieldInsn(opcode, owner, name, descriptor);
                    }
                };
            }
        }, ClassReader.SKIP_FRAMES);
        if (replaced[0] != 1) {
            throw new IllegalArgumentException("Expected 1 runtime compression initialization. Found " + replaced[0]);
        }
        addSupportedAlgorithms(writer);
        return writer.toByteArray();
    }

    private static void addSupportedAlgorithms(ClassWriter writer) {
        var method = new GeneratorAdapter(Opcodes.ACC_PRIVATE | Opcodes.ACC_STATIC,
                SUPPORTED_ALGORITHMS, null, null, writer);
        Type list = Type.getType(java.util.ArrayList.class);
        Type string = Type.getType(String.class);
        method.newInstance(list);
        method.dup();
        method.invokeConstructor(list, Method.getMethod("void <init>()"));
        int supported = method.newLocal(list);
        method.storeLocal(supported);
        int index = method.newLocal(Type.INT_TYPE);
        method.push(0);
        method.storeLocal(index);
        var next = method.mark();
        method.loadLocal(index);
        method.loadArg(0);
        method.arrayLength();
        var complete = method.newLabel();
        method.ifICmp(GeneratorAdapter.GE, complete);
        method.loadArg(0);
        method.loadLocal(index);
        method.arrayLoad(ALGORITHM);
        int codec = method.newLocal(ALGORITHM);
        method.storeLocal(codec);
        method.push("zstd");
        method.loadLocal(codec);
        method.invokeInterface(ALGORITHM, Method.getMethod("String getEncoding()"));
        method.invokeVirtual(string, Method.getMethod("boolean equalsIgnoreCase(String)"));
        var skip = method.newLabel();
        method.ifZCmp(GeneratorAdapter.NE, skip);
        method.loadLocal(supported);
        method.loadLocal(codec);
        method.invokeVirtual(list, Method.getMethod("boolean add(Object)"));
        method.pop();
        method.mark(skip);
        method.iinc(index, 1);
        method.goTo(next);
        method.mark(complete);
        method.loadLocal(supported);
        method.push(0);
        method.newArray(ALGORITHM);
        method.invokeVirtual(list, Method.getMethod("Object[] toArray(Object[])"));
        method.checkCast(ALGORITHMS);
        method.returnValue();
        method.endMethod();
    }

    private static byte[] protectImageTokens(ClassReader input) {
        // The loopback image route uses bearer URLs. Hash each key followed by
        // a process-local secret so public comic identifiers cannot reconstruct a URL.
        int[] initialized = {0};
        int[] protectedTokens = {0};
        var writer = new ClassWriter(ClassWriter.COMPUTE_MAXS);
        input.accept(new ClassVisitor(Opcodes.ASM9, writer) {
            @Override
            public FieldVisitor visitField(int access, String name, String descriptor,
                    String signature, Object value) {
                if (name.equals(IMAGE_SECRET)) {
                    throw new IllegalArgumentException("Unexpected runtime image token field");
                }
                return super.visitField(access, name, descriptor, signature, value);
            }

            @Override
            public MethodVisitor visitMethod(int access, String name, String descriptor,
                    String signature, String[] exceptions) {
                var delegate = super.visitMethod(access, name, descriptor, signature, exceptions);
                if (name.equals("<clinit>")) {
                    return new MethodVisitor(Opcodes.ASM9, delegate) {
                        @Override
                        public void visitCode() {
                            super.visitCode();
                            super.visitTypeInsn(Opcodes.NEW, "java/security/SecureRandom");
                            super.visitInsn(Opcodes.DUP);
                            super.visitMethodInsn(Opcodes.INVOKESPECIAL,
                                    "java/security/SecureRandom", "<init>", "()V", false);
                            super.visitIntInsn(Opcodes.BIPUSH, 32);
                            super.visitIntInsn(Opcodes.NEWARRAY, Opcodes.T_BYTE);
                            super.visitInsn(Opcodes.DUP_X1);
                            super.visitMethodInsn(Opcodes.INVOKEVIRTUAL,
                                    "java/security/SecureRandom", "nextBytes", "([B)V", false);
                            super.visitFieldInsn(Opcodes.PUTSTATIC, IMAGE_PROXY, IMAGE_SECRET, "[B");
                            initialized[0]++;
                        }
                    };
                }
                if (name.equals("tokenForKey") && descriptor.equals("(Ljava/lang/String;)Ljava/lang/String;")) {
                    return new MethodVisitor(Opcodes.ASM9, delegate) {
                        @Override
                        public void visitMethodInsn(int opcode, String owner, String name,
                                String descriptor, boolean isInterface) {
                            if (opcode == Opcodes.INVOKEVIRTUAL && owner.equals("java/security/MessageDigest")
                                    && name.equals("digest") && descriptor.equals("([B)[B")) {
                                super.visitInsn(Opcodes.DUP2);
                                super.visitMethodInsn(Opcodes.INVOKEVIRTUAL,
                                        owner, "update", "([B)V", false);
                                super.visitInsn(Opcodes.POP);
                                super.visitFieldInsn(Opcodes.GETSTATIC, IMAGE_PROXY, IMAGE_SECRET, "[B");
                                protectedTokens[0]++;
                            }
                            super.visitMethodInsn(opcode, owner, name, descriptor, isInterface);
                        }
                    };
                }
                return delegate;
            }
        }, 0);
        if (initialized[0] != 1 || protectedTokens[0] != 1) {
            throw new IllegalArgumentException("Missing pinned runtime image token initialization");
        }
        writer.visitField(Opcodes.ACC_PRIVATE | Opcodes.ACC_STATIC | Opcodes.ACC_FINAL,
                IMAGE_SECRET, "[B", null, null).visitEnd();
        return writer.toByteArray();
    }
}
