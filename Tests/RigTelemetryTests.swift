import Foundation

@main struct RigTelemetryTests {
    static func main() {
        guard RigTelemetry.number("5\n") == 5,
              RigTelemetry.number("get_level: RFPOWER\n0.15\nRPRT 0\n") == 0.15,
              RigTelemetry.number("get_ptt:\nPTT: 1\nRPRT 0\n") == 1,
              RigTelemetry.number("power2mW: 0.15 7100000 PKTUSB\nPower mW: 15000\nRPRT 0\n") == 15000,
              RigTelemetry.number("0\nRPRT -11\n") == nil,
              RigTelemetry.number("nan\n") == nil,
              RigTelemetry.powerConversion(fraction: 0.15, frequency: "7.100000 MHz", mode: "PKTUSB") == "+\\power2mW 0.15 7100000 PKTUSB",
              RigTelemetry.powerConversion(fraction: 0.15, frequency: "Unavailable", mode: "PKTUSB") == nil,
              RigTelemetry.powerConversion(fraction: 0.15, frequency: "7.100000 MHz", mode: "USB\nT 1") == nil else { fatalError("CAT meter parsing/conversion checks failed") }
        print("PASS: plain/extended CAT readings, failure and NaN rejection, read-only power conversion and argument validation")
    }
}
