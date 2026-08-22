import Testing

@testable import MiraioDomain

@Suite("Immutable Catalogue queries")
struct SeriesQueryTests {
  @Test("search text is normalized without changing the provider-backed query identity")
  func normalizesSearchText() throws {
    let query = try #require(SeriesQuery(searchText: "  Frieren  ", pageSize: 50))

    #expect(query.searchText == "Frieren")
    #expect(query == SeriesQuery(searchText: "Frieren", pageSize: 50))
    #expect(SeriesQuery(searchText: "   ", pageSize: 50) == SeriesQuery(pageSize: 50))
    #expect(SeriesQuery(pageSize: 0) == nil)
    #expect(SeriesQuery(pageSize: 1_001) == nil)
  }
}

@Suite("Catalogue display values")
struct CatalogueDisplayValueTests {
  @Test("provider Series names remain unchanged while language preference selects a known value")
  func choosesKnownProviderTitle() throws {
    let series = Series(
      id: try #require(SeriesID(42)),
      titles: LocalizedSeriesTitles(["en": "Frieren", "ru": "Провожающая в последний путь Фрирен"])
    )

    #expect(series.title(preferredLanguages: ["ru-RU"]) == "Провожающая в последний путь Фрирен")
    #expect(series.title(preferredLanguages: ["en-US"]) == "Frieren")
    #expect(Series(id: series.id).title(preferredLanguages: ["en"]) == nil)
  }

  @Test("paged Catalogue reconciliation is identity-based and preserves known fields")
  func appendsPageByIdentity() throws {
    let firstID = try #require(SeriesID(41))
    let secondID = try #require(SeriesID(42))
    let firstPage = CataloguePage(
      series: [
        Series(
          id: firstID,
          titles: LocalizedSeriesTitles(["en": "Known title"]),
          year: 2023
        )
      ],
      nextCursor: nil
    )
    let nextPage = CataloguePage(
      series: [Series(id: firstID, isAiring: true), Series(id: secondID)],
      nextCursor: nil
    )

    let combined = firstPage.appending(nextPage)

    #expect(combined.series.map(\.id) == [firstID, secondID])
    #expect(combined.series[0].title(preferredLanguages: ["en"]) == "Known title")
    #expect(combined.series[0].year == 2023)
    #expect(combined.series[0].isAiring == true)
  }
}
