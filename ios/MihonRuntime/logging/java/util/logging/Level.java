package java.util.logging;

// The Zero image includes java.base only. OkHttp and NanoHTTPD resolve these
// logging levels while running with platform logging disabled.
public final class Level {
    public static final Level OFF = new Level();
    public static final Level SEVERE = new Level();
    public static final Level WARNING = new Level();
    public static final Level INFO = new Level();
    public static final Level CONFIG = new Level();
    public static final Level FINE = new Level();
    public static final Level FINER = new Level();
    public static final Level FINEST = new Level();
    public static final Level ALL = new Level();

    private Level() {}
}
