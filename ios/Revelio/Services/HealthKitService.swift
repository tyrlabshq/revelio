import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

/// Opt-in Apple Health integration.
///
/// v1 scope: request WRITE-only permission for `HKQuantityType.dietaryEnergyConsumed`.
/// Read access is intentionally refused — Revelio does not read any data back
/// from Health, and Apple doesn't offer a "clean score" category so we can
/// only log energy from scans as a nutritional signal.
///
/// The actual write pathway is **stubbed** for v1 with a detailed TODO. Apple
/// Health typing is persnickety (HKQuantitySample construction, start/end
/// dates, metadata keys) and getting it wrong silently logs zero samples.
/// We'd rather ship the permission flow + settings toggle and wire the write
/// up behind a fixture-backed test than ship something that looks like it
/// works but writes nothing.
@MainActor
final class HealthKitService: ObservableObject {
    static let shared = HealthKitService()

    /// Persisted user preference — source of truth for the settings toggle.
    /// We mirror this into UserDefaults so the toggle survives relaunches
    /// without hitting HealthKit at startup.
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.preferenceKey) }
    }

    private static let preferenceKey = "healthKitSyncEnabled"

    #if canImport(HealthKit)
    private let store = HKHealthStore()
    #endif

    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.preferenceKey)
    }

    /// Whether Apple Health is even available on this device (iPad lacks it).
    var isHealthDataAvailable: Bool {
        #if canImport(HealthKit)
        return HKHealthStore.isHealthDataAvailable()
        #else
        return false
        #endif
    }

    /// Request write-only permission for dietary energy. Returns `true` if the
    /// user granted it (or the system returns `.sharingAuthorized`). Call from
    /// the settings toggle when the user flips it on.
    func requestPermission() async -> Bool {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        guard let energy = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) else {
            return false
        }
        let writeTypes: Set<HKSampleType> = [energy]
        // Empty read set — we do NOT want Health authorisation to unlock any
        // personal history on our side.
        let readTypes: Set<HKObjectType> = []
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            // HealthKit's authorization status for write returns .notDetermined
            // when the user has granted permission (Apple's privacy design), so
            // we can't reliably check it here. Treat a thrown error as failure
            // and a clean return as success.
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }

    /// Log the kcal from a successful food scan into Apple Health as a
    /// `dietaryEnergyConsumed` sample.
    ///
    /// TODO(HK-write-stub): Implement the actual HKQuantitySample construction.
    ///   - Use `HKQuantity(unit: .kilocalorie(), doubleValue: kcal)`
    ///   - Build an `HKQuantitySample(type:, quantity:, start: Date(), end: Date())`
    ///     with a metadata dictionary containing the barcode for dedup.
    ///   - Call `store.save(sample)` and propagate failures via logger.
    ///   - Add a fixture-backed unit test that verifies the sample round-trips
    ///     through HKHealthStore in a simulator.
    /// Parked intentionally: shipping a no-op is safer than shipping a write
    /// path we can't verify end-to-end without device testing.
    func logDietaryEnergy(kilocalories kcal: Double, barcode: String?) async {
        guard isEnabled else { return }
        // Intentionally left as stub — see TODO(HK-write-stub) above.
        _ = kcal
        _ = barcode
    }

    /// User-initiated toggle. Handles the permission dance so callers don't
    /// have to — if the user turns the switch on but declines the system
    /// prompt, we flip the switch back off.
    func setEnabled(_ enabled: Bool) async {
        if enabled {
            let granted = await requestPermission()
            self.isEnabled = granted
        } else {
            self.isEnabled = false
        }
    }
}
