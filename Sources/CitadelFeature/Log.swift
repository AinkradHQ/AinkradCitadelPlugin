import AinkradAppKit
import os

/// The module's loggers. They all build on `AinkradLog`, so one Console filter
/// on the `com.ainkrad.app` subsystem covers the host and every plugin. The app
/// id is a literal because `CitadelApp.id` is main-actor isolated and these are not.
/// Nothing here ever logs a device key.
enum Log {
    static let persistence = AinkradLog.logger(app: "citadel", area: "persistence")
    static let connection = AinkradLog.logger(app: "citadel", area: "connection")
    static let events = AinkradLog.logger(app: "citadel", area: "events")
}
