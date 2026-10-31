import os

public enum Log {
    static let subsystem = "app.afterglow"
    public static let settings = Logger(subsystem: subsystem, category: "settings")
    public static let music = Logger(subsystem: subsystem, category: "music")
    public static let artwork = Logger(subsystem: subsystem, category: "artwork")
}
