package java.util.logging;

import java.util.function.Supplier;

public final class Logger {
    private static final Logger DISABLED = new Logger();

    private Logger() {}

    public static Logger getLogger(String name) {
        return DISABLED;
    }

    public boolean isLoggable(Level level) {
        return false;
    }

    public void log(Level level, String message) {}
    public void log(Level level, String message, Throwable cause) {}
    public void log(Level level, Supplier<String> message) {}
}
