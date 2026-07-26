import XCTest
@testable import PersonalToolbox

final class LegadoRuleEngineTests: XCTestCase {
    // MARK: - ##regex##replace

    func testRegexReplaceStripsPrefix() {
        let html = "<div class=\"author\">作者：张三</div>"
        let result = LegadoRuleEngine.getString(rule: ".author@text##作者：##", in: html, baseURL: nil)
        XCTAssertEqual(result, "张三")
    }

    // MARK: - `.N` index selection
    //
    // Regression anchor for the real bug found in the bundled 飘天文学 source: the search
    // rule used `td.odd.2` for "author" but that 0-based index actually landed on the
    // "date" column. These pin down the exact semantics so a future edit can't silently
    // reintroduce an off-by-one in a shipped rule.

    private let searchRow = """
        <tr>
            <td class="odd">Name</td>
            <td class="even">Chapter</td>
            <td class="odd">Author</td>
            <td class="even">Words</td>
            <td class="odd">Date</td>
        </tr>
        """

    func testIndexSelectionPicksCorrectColumnAmongSameClass() {
        // Among the three `td.odd` matches, index 0 = Name, 1 = Author, 2 = Date.
        XCTAssertEqual(LegadoRuleEngine.getString(rule: "td.odd.0@text", in: searchRow, baseURL: nil), "Name")
        XCTAssertEqual(LegadoRuleEngine.getString(rule: "td.odd.1@text", in: searchRow, baseURL: nil), "Author")
        XCTAssertEqual(LegadoRuleEngine.getString(rule: "td.odd.2@text", in: searchRow, baseURL: nil), "Date")
    }

    // MARK: - `!N` exclude-first

    func testExcludeFirstRowSkipsHeader() {
        let html = "<table><tr><td>header</td></tr><tr><td>row1</td></tr><tr><td>row2</td></tr></table>"
        let list = LegadoRuleEngine.getList(rule: "table tr!0", in: html)
        XCTAssertEqual(list.count, 2)
        XCTAssertTrue(list[0].contains("row1"))
        XCTAssertTrue(list[1].contains("row2"))
    }

    // MARK: - `&&` / `||`

    func testOrListReturnsFirstNonEmptyMatch() {
        let html = "<div class=\"b\">B-value</div>"
        let result = LegadoRuleEngine.getString(rule: ".a@text||.b@text", in: html, baseURL: nil)
        XCTAssertEqual(result, "B-value")
    }

    func testAndListJoinsAllNonEmptyParts() {
        let html = "<div class=\"a\">A</div><div class=\"b\">B</div>"
        let result = LegadoRuleEngine.getString(rule: ".a@text&&.b@text", in: html, baseURL: nil)
        XCTAssertEqual(result, "A B")
    }

    // MARK: - Attribute selector

    func testAttributeSelectorMatchesExactValue() {
        let html = "<a href=\"/x\">no</a><a data-id=\"7\" href=\"/y\">yes</a>"
        let result = LegadoRuleEngine.getString(rule: "a[data-id=7]@href", in: html, baseURL: nil)
        XCTAssertEqual(result, "/y")
    }

    // MARK: - JSON path

    func testJSONPathExtractsListItemsAndFields() {
        let json = #"{"data":{"list":[{"name":"A"},{"name":"B"}]}}"#
        let items = LegadoRuleEngine.getList(rule: "$.data.list[*]", in: json)
        XCTAssertEqual(items.count, 2)
        let names = items.map { LegadoRuleEngine.getString(rule: "$.name", in: $0, baseURL: nil) }
        XCTAssertEqual(names, ["A", "B"])
    }

    // MARK: - URL absolutization

    func testRelativeHrefIsAbsolutizedAgainstBaseURL() {
        let html = "<a href=\"/book/1\">t</a>"
        let base = URL(string: "https://example.com/")
        let result = LegadoRuleEngine.getString(rule: "a@href", in: html, baseURL: base)
        XCTAssertEqual(result, "https://example.com/book/1")
    }

    // MARK: - Empty / missing rule

    func testEmptyRuleReturnsEmptyString() {
        XCTAssertEqual(LegadoRuleEngine.getString(rule: "", in: "<div>x</div>", baseURL: nil), "")
        XCTAssertEqual(LegadoRuleEngine.getString(rule: nil, in: "<div>x</div>", baseURL: nil), "")
    }

    func testNoMatchReturnsEmptyList() {
        XCTAssertTrue(LegadoRuleEngine.getList(rule: ".nonexistent", in: "<div>x</div>").isEmpty)
    }
}
