import XCTest
@testable import PLACore

final class AmountParserAndMoneyTests: XCTestCase {
    func testParsePlainInteger() {
        XCTAssertEqual(AmountParser.parse("50000"), .success(Money(50_000)))
        XCTAssertEqual(AmountParser.parse("1"), .success(Money(1)))
        XCTAssertEqual(AmountParser.parse("0005000"), .success(Money(5_000)))
    }

    func testParseIndonesianThousandsSeparatorAndRpPrefix() {
        XCTAssertEqual(AmountParser.parse("Rp 1.500.000"), .success(Money(1_500_000)))
        XCTAssertEqual(AmountParser.parse("Rp.50.000"), .success(Money(50_000)))
        XCTAssertEqual(AmountParser.parse("rp 250.000"), .success(Money(250_000)))
        XCTAssertEqual(AmountParser.parse("IDR 12.345.678"), .success(Money(12_345_678)))
        XCTAssertEqual(AmountParser.parse("Rp\u{00A0}75.000"), .success(Money(75_000)))
    }

    func testParseCommaThousandsSeparator() {
        XCTAssertEqual(AmountParser.parse("1,500,000"), .success(Money(1_500_000)))
        XCTAssertEqual(AmountParser.parse("Rp 50,000"), .success(Money(50_000)))
    }

    func testParseMaximumAllowedBoundary() {
        XCTAssertEqual(AmountParser.parse("999.999.999.999"), .success(Money(999_999_999_999)))
        XCTAssertEqual(AmountParser.parse("1.000.000.000.000"), .failure(.exceedsMaximum))
        XCTAssertEqual(AmountParser.parse("9999999999999"), .failure(.exceedsMaximum))
    }

    func testRejectEmptyAndZeroAndNegative() {
        XCTAssertEqual(AmountParser.parse(""), .failure(.empty))
        XCTAssertEqual(AmountParser.parse("   "), .failure(.empty))
        XCTAssertEqual(AmountParser.parse("Rp"), .failure(.empty))
        XCTAssertEqual(AmountParser.parse("0"), .failure(.negativeOrZero))
        XCTAssertEqual(AmountParser.parse("000"), .failure(.negativeOrZero))
        XCTAssertEqual(AmountParser.parse("-50000"), .failure(.negativeOrZero))
        XCTAssertEqual(AmountParser.parse("Rp -10.000"), .failure(.negativeOrZero))
    }

    func testRejectDecimalsForWholeRupiah() {
        XCTAssertEqual(AmountParser.parse("50000,75"), .failure(.decimalsNotAllowed))
        XCTAssertEqual(AmountParser.parse("50000.75"), .failure(.decimalsNotAllowed))
        XCTAssertEqual(AmountParser.parse("1.500,50"), .failure(.decimalsNotAllowed))
        XCTAssertEqual(AmountParser.parse("1,500.50"), .failure(.decimalsNotAllowed))
        XCTAssertEqual(AmountParser.parse("10,5"), .failure(.decimalsNotAllowed))
    }

    func testRejectNonNumericEmojiAndMalformedGrouping() {
        XCTAssertEqual(AmountParser.parse("abc"), .failure(.invalidFormat))
        XCTAssertEqual(AmountParser.parse("Rp 50🔥"), .failure(.invalidFormat))
        XCTAssertEqual(AmountParser.parse("1.23.45"), .failure(.invalidFormat))
        XCTAssertEqual(AmountParser.parse(".500"), .failure(.invalidFormat))
        XCTAssertEqual(AmountParser.parse("500."), .failure(.invalidFormat))
    }

    func testAmountParseErrorUserMessagesNonEmpty() {
        let all: [AmountParseError] = [.empty, .negativeOrZero, .decimalsNotAllowed, .invalidFormat, .exceedsMaximum]
        for err in all {
            XCTAssertFalse(err.userMessage.isEmpty)
        }
    }

    func testMoneyArithmeticAndBounds() {
        let a = Money(100_000)
        let b = Money(40_000)
        XCTAssertEqual(a + b, Money(140_000))
        XCTAssertEqual(a - b, Money(60_000))
        XCTAssertEqual(-b, Money(-40_000))
        XCTAssertTrue(a.isPositive)
        XCTAssertTrue((-b).isNegative)
        XCTAssertTrue(Money.zero.isZero)
        XCTAssertTrue(a.isWithinTransactionBounds)
        XCTAssertFalse(Money(0).isWithinTransactionBounds)
        XCTAssertFalse(Money(Money.maxAllowedRupiah + 1).isWithinTransactionBounds)
        XCTAssertLessThan(b, a)
        XCTAssertEqual(a.description, "100000")
    }

    func testTransactionValidation() {
        let accA = UUID()
        let accB = UUID()
        let cat = UUID()
        let date = LocalDate(year: 2026, month: 11, day: 26)!

        let validExpense = PLATransaction(type: .expense, amount: 50_000, accountId: accA, categoryId: cat, dateLocal: date)
        XCTAssertNoThrow(try validExpense.validate())

        let validTransfer = PLATransaction(type: .transfer, amount: 500_000, accountId: accA, destinationAccountId: accB, dateLocal: date)
        XCTAssertNoThrow(try validTransfer.validate())

        let sameAccountTransfer = PLATransaction(type: .transfer, amount: 500_000, accountId: accA, destinationAccountId: accA, dateLocal: date)
        XCTAssertThrowsError(try sameAccountTransfer.validate()) { err in
            XCTAssertEqual(err as? TransactionValidationError, .sameSourceAndDestination)
        }

        let missingCat = PLATransaction(type: .expense, amount: 50_000, accountId: accA, categoryId: nil, dateLocal: date)
        XCTAssertThrowsError(try missingCat.validate()) { err in
            XCTAssertEqual(err as? TransactionValidationError, .missingCategory)
        }

        let zeroAmt = PLATransaction(type: .income, amount: 0, accountId: accA, categoryId: cat, dateLocal: date)
        XCTAssertThrowsError(try zeroAmt.validate()) { err in
            XCTAssertEqual(err as? TransactionValidationError, .nonPositiveAmount)
        }

        let overLimit = PLATransaction(type: .income, amount: Money.maxAllowedRupiah + 1, accountId: accA, categoryId: cat, dateLocal: date)
        XCTAssertThrowsError(try overLimit.validate()) { err in
            XCTAssertEqual(err as? TransactionValidationError, .amountExceedsLimit)
        }

        let transferWithCat = PLATransaction(type: .transfer, amount: 10_000, accountId: accA, destinationAccountId: accB, categoryId: cat, dateLocal: date)
        XCTAssertThrowsError(try transferWithCat.validate()) { err in
            XCTAssertEqual(err as? TransactionValidationError, .categoryNotAllowedForTransfer)
        }
    }

    func testTaskTitleValidation() {
        XCTAssertFalse(PLATask.isValidTitle(""))
        XCTAssertFalse(PLATask.isValidTitle("   \n\t  "))
        XCTAssertTrue(PLATask.isValidTitle("Bayar listrik"))
        XCTAssertTrue(PLATask.isValidTitle(String(repeating: "a", count: 200)))
        XCTAssertFalse(PLATask.isValidTitle(String(repeating: "a", count: 201)))
    }
}
