import Foundation

@main struct RadioModelTests {
    @MainActor static func main() async throws {
        let sample = """
         Rig #  Mfg                    Model                   Version         Status      Macro
          1049  Yaesu                  FT-710                  20241118.7      Stable      RIG_MODEL_FT710
          3073  Icom                   IC-7300                 20250517.14     Stable      RIG_MODEL_IC7300
            10  N2ADR James Ahlstrom   Quisk                   20230709.0      Stable      RIG_MODEL_QUISK
        malformed data
        """
        let models = RadioModel.parse(sample)
        guard models.count == 3, models.first?.brand == "Icom",
              models.first?.label == "3073 · Icom IC-7300",
              models.first(where: { $0.id == 10 })?.brand == "N2ADR James Ahlstrom",
              models.first(where: { $0.id == 1049 })?.model == "FT-710" else { fatalError("Radio model parsing failed") }
        if RigController.executable != nil {
            let catalog = RadioModelCatalog()
            await catalog.refresh()
            guard !catalog.models.isEmpty, !catalog.busy else { fatalError("Installed Hamlib model lookup failed: \(catalog.message)") }
            print("PASS: installed Hamlib catalog: \(catalog.models.count) brand/model/number entries")
        }
        print("PASS: radio catalog parsing, multiword brands, sorted model labels and malformed rows")
    }
}
