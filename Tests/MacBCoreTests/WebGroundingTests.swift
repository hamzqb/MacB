import XCTest
@testable import MacBCore

final class WebGroundingTests: XCTestCase {
    private let resultsFixture = """
    <div class="result results_links"><h2 class="result__title"><a rel="nofollow" class="result__a" \
    href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fhaber&amp;rut=1">Bir <b>haber</b> başlığı</a></h2></div>
    <div class="result results_links"><h2><a class="result__a" href="https://ikinci.example.org/sayfa">İkinci sonuç</a></h2></div>
    """

    private let pageFixture = """
    <html><head><title>x</title><style>.a{color:red}</style></head><body><script>var a = 1;</script>\
    <h1>Başlık</h1><p>Birinci paragraf.</p><p>İkinci &amp; paragraf</p></body></html>
    """

    func testOnlyQuestionsAboutNowGoToTheWeb() {
        XCTAssertTrue(WebGrounding.needsSearch("dolar bugün kaç TL"))
        XCTAssertTrue(WebGrounding.needsSearch("https://example.com nedir"))
        XCTAssertFalse(WebGrounding.needsSearch("bu metni düzelt"))
        XCTAssertFalse(WebGrounding.needsSearch("ok"))
    }

    func testQueryDropsWhatOnlyAddressesMacB() {
        let query = WebGrounding.query(from: "MacB lütfen bana dolar kuru bugün ne kadar?")
        XCTAssertFalse(query.lowercased().contains("macb"))
        XCTAssertTrue(query.contains("dolar kuru"))
    }

    func testResultsComeBackAsRealAddresses() {
        let results = WebGrounding.parseResults(resultsFixture)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.first?.url.absoluteString, "https://example.com/haber")
        XCTAssertEqual(results.first?.title, "Bir haber başlığı")
        XCTAssertEqual(results.last?.url.host, "ikinci.example.org")
    }

    func testPageBecomesTextWithoutItsScripts() {
        let text = WebGrounding.readableText(from: pageFixture)
        XCTAssertFalse(text.contains("var a"))
        XCTAssertFalse(text.contains("color:red"))
        XCTAssertTrue(text.contains("Birinci paragraf."))
        XCTAssertTrue(text.contains("İkinci & paragraf"))
    }

    func testPromptCarriesSourcesAndTheRuleAboutThem() {
        let result = WebResult(title: "Kaynak", url: URL(string: "https://example.com/a")!,
                               snippet: "kısa", text: "uzun metin")
        let prompt = WebGrounding.prompt(question: "soru nedir", results: [result])
        XCTAssertTrue(prompt.contains("[1] Kaynak — https://example.com/a"))
        XCTAssertTrue(prompt.contains("uzun metin"))
        XCTAssertTrue(prompt.contains("Soru: soru nedir"))
    }
}
