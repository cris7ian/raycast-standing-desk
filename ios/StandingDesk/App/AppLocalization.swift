import Foundation

func appString(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

func appFormat(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: appString(key), locale: .current, arguments: arguments)
}

func localizedAppError(_ error: Error) -> String {
    guard let error = error as? DeskConfigurationError else {
        return error.localizedDescription
    }

    switch error {
    case .emptyDeskName:
        return appString("Desk Bluetooth Name cannot be empty.")
    case let .notFinite(label):
        return appFormat("%@ must be a number.", localizedConfigurationLabel(label))
    case .nonPositiveHeight:
        return appString("Base, Minimum, and Maximum Height must be above 0 cm.")
    case .invalidHeightRange:
        return appString("Minimum Height must be lower than Maximum Height.")
    case .baseExceedsMinimum:
        return appString("Base Height cannot exceed Minimum Height.")
    case .invalidStepHeight:
        return appString("Raise and Lower Step must be between 0 and 20 cm.")
    case .invalidTarget:
        return appString("Target height must be a number.")
    case let .targetOutsideRange(minimumHeight, maximumHeight):
        let minimum = minimumHeight.formatted(.number.precision(.fractionLength(1)))
        let maximum = maximumHeight.formatted(.number.precision(.fractionLength(1)))
        return appFormat("Target height must be between %@ and %@ cm.", minimum, maximum)
    }
}

private func localizedConfigurationLabel(_ label: String) -> String {
    switch label {
    case "Base Height": appString("Base Height")
    case "Minimum Height": appString("Minimum Height")
    case "Maximum Height": appString("Maximum Height")
    case "Raise and Lower Step": appString("Raise and Lower Step")
    default: label
    }
}
