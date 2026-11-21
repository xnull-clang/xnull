// 0.x wrote fields into the message; 1.0 keeps them structured.
import xdk.log

static Int main() {
    Logger logger = new Logger("migration", Level.Info)
    Logger fielded = logger.withField("version", "1.0")
    fielded.info("ready")
    return 0
}
