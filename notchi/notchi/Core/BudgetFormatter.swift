import Foundation

nonisolated enum BudgetFormatter {
    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "en_US")
        f.currencyCode = "USD"
        f.currencySymbol = "$"
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    static func usd(_ amount: Double) -> String {
        currencyFormatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }

    /// Whole dollars for figures the user typed themselves, which are rarely fractional.
    static func usdRounded(_ amount: Double) -> String {
        amount == amount.rounded() ? "$\(Int(amount))" : usd(amount)
    }

    /// Whole dollars for the notch, where space is short; cents only under a dollar.
    static func usdCompact(_ amount: Double) -> String {
        amount < 1 ? usd(amount) : "$\(Int(amount.rounded()))"
    }

    static func plain(_ amount: Double) -> String {
        amount == amount.rounded() ? String(Int(amount)) : String(format: "%.2f", amount)
    }
}
