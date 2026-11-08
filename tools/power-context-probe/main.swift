// power-context-probe
//
// Standalone macOS diagnostic: reports the *type* of the currently providing
// power source and whether public adapter details are available.
//
// API surface is deliberately limited to the official public IOKit.ps calls:
//   - IOPSCopyPowerSourcesInfo()
//   - IOPSGetProvidingPowerSourceType(info)
//   - IOPSCopyExternalPowerAdapterDetails()
//
// No IORegistry private calls, no sensor start, no device settings changed.
// This tool only *reads* public power-source metadata.

import Foundation
import IOKit.ps

// MARK: - Output helpers

/// Maps a power source type constant (or nil/unexpected value) to a stable,
/// human-readable label. Unknown values are reported as "unknown" rather than
/// being coerced to a false/zero value.
func describePowerSourceType(_ raw: CFString?) -> String {
    guard let raw = raw else { return "unknown" }
    switch raw as String {
    case kIOPSACPowerValue:
        return "AC"
    case kIOPSBatteryPowerValue:
        return "Battery"
    case "UPSPower":
        return "UPS"
    default:
        return "unknown(\(raw as String))"
    }
}

/// Resolves an optional numeric public key from the adapter details dictionary.
///
/// The dictionary values are typed as CFNumber; anything else (absent, wrong
/// type, non-numeric) is reported as "unknown" — never as 0.
func optionalNumericKey(_ dictionary: [String: Any], key: CFString) -> String {
    guard let value = dictionary[key as String] else { return "unknown" }
    guard let number = value as? NSNumber else { return "unknown" }
    return number.stringValue
}

// MARK: - Query

/// Collects and prints the power-source summary.
///
/// Always prints the power source type. Adapter details are reported as
/// available/unavailable; when available, only the documented optional public
/// keys are read. Absence of any *public* detail is reported as unknown because
/// this generic API cannot distinguish "no adapter" from "query error".
func runDefaultReport() {
    // NOTE on ambiguity: IOPSCopyExternalPowerAdapterDetails() returns a
    // retained CFDictionary on success and NULL when there is no adapter OR on
    // error. We must keep that ambiguity intact and never claim a definite
    // absence from a NULL result.
    let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()

    let providingType: CFString? = snapshot.flatMap {
        IOPSGetProvidingPowerSourceType($0)?.takeUnretainedValue()
    }

    print("Power source type: \(describePowerSourceType(providingType))")

    let adapterDetails = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue()

    guard let details = adapterDetails as? [String: Any] else {
        // NULL: cannot distinguish "no adapter" from a query error.
        print("Adapter details available: unknown")
        print("Watts: unknown")
        print("Current: unknown")
        print("FamilyCode: unknown")
        return
    }

    print("Adapter details available: yes")

    // Public fields report adapter wattage/current, not measured outlet draw or battery amperage.
    // They may reflect the negotiated supply; don't assume the adapter's printed maximum rating.
    // kIOPSPowerAdapterFamilyKey
    // is a family code, not a brand name.
    print("Watts: \(optionalNumericKey(details, key: kIOPSPowerAdapterWattsKey as CFString))")
    print("Current: \(optionalNumericKey(details, key: kIOPSPowerAdapterCurrentKey as CFString))")
    print("FamilyCode: \(optionalNumericKey(details, key: kIOPSPowerAdapterFamilyKey as CFString))")

    // Brand/model and physical USB port mapping are not obtainable from this
    // generic public API. We do not guess them.
    print("Brand: unavailable from this generic public API")
    print("Physical port mapping: unavailable from this generic public API")
}

/// Prints only the sorted key names of the adapter details dictionary.
///
/// This mode is for studying the *shape* of the dictionary. It never prints any
/// values (no names, model, serial, AdapterID) and never dumps the dictionary.
func runKeysReport() {
    let adapterDetails = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue()

    guard let details = adapterDetails as? [String: Any] else {
        // NULL: cannot distinguish "no adapter" from a query error.
        print("Adapter details available: unknown")
        return
    }

    print("Adapter details available: yes")
    for key in details.keys.sorted() {
        print(key)
    }
}

// MARK: - Entry point

let arguments = Array(CommandLine.arguments.dropFirst())

switch arguments {
case []:
    runDefaultReport()
    // Normal query: even when type/details are unknown, absence is reported
    // as unknown and this is a successful diagnostic.
    exit(0)

case ["--keys"]:
    runKeysReport()
    exit(0)

case ["--help"]:
    print("""
    Usage: power-context-probe [--keys | --help]

      (no args)  Print the providing power source type and whether public
                 adapter details are available; when available, the optional
                 public keys Watts (reported adapter wattage), Current (reported
                 adapter current, mA) and FamilyCode (family code).
      --keys     Print ONLY the sorted key names present in the public adapter
                 details dictionary, to study its shape. No values are shown.
      --help     Show this message.
    """)
    exit(0)

default:
    // Reject unknown or multiple arguments.
    FileHandle.standardError.write(
        Data("power-context-probe: unexpected arguments: \(arguments.joined(separator: " "))\n".utf8))
    FileHandle.standardError.write(
        Data("usage: power-context-probe [--keys | --help]\n".utf8))
    exit(1)
}
