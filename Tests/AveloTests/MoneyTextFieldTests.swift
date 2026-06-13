import XCTest
import SwiftUI
@testable import Avelo

final class MoneyTextFieldTests: XCTestCase {

    func testLabelBindingSkipsRedundantFormattedWrites() {
        final class Box {
            var value: String
            var writes = 0
            init(_ value: String) { self.value = value }
        }

        let box = Box("1234.00")
        let binding = Binding<String>(
            get: { box.value },
            set: { newValue in
                box.writes += 1
                box.value = newValue
            }
        )

        let paiseBinding = Binding<Int64>(
            get: { Currency.parseRupeeInput(binding.wrappedValue) ?? 0 },
            set: { newValue in
                if newValue == 0 {
                    if binding.wrappedValue != "" { binding.wrappedValue = "" }
                } else {
                    let formatted = Currency.formatAmountInput(paise: newValue)
                    if binding.wrappedValue != formatted { binding.wrappedValue = formatted }
                }
            }
        )

        paiseBinding.wrappedValue = 123_400
        XCTAssertEqual(box.value, "1234.00")
        XCTAssertEqual(box.writes, 0, "The binding should not rewrite identical formatted text")
    }

    func testLabelBindingWritesWhenFormattedValueChanges() {
        final class Box {
            var value: String
            var writes = 0
            init(_ value: String) { self.value = value }
        }

        let box = Box("")
        let binding = Binding<String>(
            get: { box.value },
            set: { newValue in
                box.writes += 1
                box.value = newValue
            }
        )

        let paiseBinding = Binding<Int64>(
            get: { Currency.parseRupeeInput(binding.wrappedValue) ?? 0 },
            set: { newValue in
                if newValue == 0 {
                    if binding.wrappedValue != "" { binding.wrappedValue = "" }
                } else {
                    let formatted = Currency.formatAmountInput(paise: newValue)
                    if binding.wrappedValue != formatted { binding.wrappedValue = formatted }
                }
            }
        )

        paiseBinding.wrappedValue = 500
        XCTAssertEqual(box.value, Currency.formatAmountInput(paise: 500))
        XCTAssertEqual(box.writes, 1)
    }
}
