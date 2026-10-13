import Foundation

struct QSO73SettingsProfile: Codable, Equatable {
    var format = "QSO73"
    var version = 1
    var station: StationSettings
    var modem: Modem73Settings
    var radio: RigSettings
    var macros: RadioMacroSettings? = nil
    var beacon: BeaconSettings? = nil

    func validate() throws {
        guard format == "QSO73", version == 1 else { throw RadioError.invalid("Select a supported QSO73 settings file.") }
        try modem.validate(station: station)
        try beacon?.validate(station: station)
        guard radio.model > 0, [4800,9600,19200,38400,57600,115200].contains(radio.baud) else {
            throw RadioError.invalid("Invalid radio model or CAT baud rate in settings file.")
        }
    }
    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
    static func decoded(_ bytes: Data) throws -> QSO73SettingsProfile {
        let profile = try JSONDecoder().decode(Self.self, from: bytes)
        try profile.validate()
        return profile
    }
}
