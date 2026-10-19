import Foundation
import Testing
@testable import MovieNight

struct ClassifierTests {
    private func classify(_ paths: [String], folder: FolderContent = .filmsAndTV, duration: Double? = 3600) -> [String: Classification] {
        ContentClassifier.classify(paths.map { ClassifierInput(key: $0, relativePath: $0, fileName: String($0.split(separator: "/").last!), duration: duration) }, folder: folder)
    }

    @Test func cleansFilmTitlesAndReadsYearsOnlyWhenTheyAreYears() {
        #expect(ContentClassifier.cleanTitle("Interstellar ") == ("Interstellar", nil))
        #expect(ContentClassifier.cleanTitle("Dr No (1962)") == ("Dr No", 1962))
        #expect(ContentClassifier.cleanTitle("Blade Runner 2049") == ("Blade Runner 2049", nil))       // part of the title
        #expect(ContentClassifier.cleanTitle("Heat.1995.1080p.BluRay.x264") == ("Heat", 1995))
        #expect(ContentClassifier.cleanTitle("The Matrix (1999) [YTS] (1080p BluRay x265)") == ("The Matrix", 1999))
        #expect(ContentClassifier.cleanTitle("Top Gun Maverick ") == ("Top Gun Maverick", nil))
    }

    @Test func readsEveryEpisodeNamingStyle() {
        let short = ContentClassifier.parseEpisode("Succession S1E10")
        #expect(short == .init(show: "Succession", season: 1, episode: 10, title: nil, year: nil))
        #expect(ContentClassifier.parseEpisode("The White Lotus S01E01")?.episode == 1)
        let long = ContentClassifier.parseEpisode("Invincible (2021) - S01E03 - Who Are You Calling Ugly (1080p WEB-DL x265 SAMPA)")
        #expect(long == .init(show: "Invincible", season: 1, episode: 3, title: "Who Are You Calling Ugly", year: 2021))
        #expect(ContentClassifier.parseEpisode("the.wire.s02e05.720p")?.season == 2)
        #expect(ContentClassifier.parseEpisode("Fargo 2x03")?.episode == 3)
        #expect(ContentClassifier.parseEpisode("Ocean's Eleven") == nil)
        #expect(ContentClassifier.seasonNumber("The White Lotus Season 3") == 3)
    }

    @Test func sortsAFilmsFolderIntoFilmsFranchisesShowsAndExtras() {
        let results = classify([
            "Inception.mkv", "Blade Runner 2049.mkv", "007/Dr No (1962).mp4", "Dune/Dune 2.mp4",
            "Succession/Succession Season 2/Succession S2E1.mkv",
            "Invincible (2021)/Invincible (2021) - S01E01 - It's About Time (1080p WEB-DL x265 SAMPA).mkv",
            "The Wire/Season 1/The Wire S1E1.mkv", "The Wire/Featurettes/Season 4/The Game Is Real.mkv",
        ])
        #expect(results["Inception.mkv"]?.kind == .film)
        #expect(results["Inception.mkv"]?.franchise == nil)
        #expect(results["Blade Runner 2049.mkv"]?.title == "Blade Runner 2049")
        #expect(results["007/Dr No (1962).mp4"] == Classification(kind: .film, title: "Dr No", year: 1962, franchise: "007"))
        #expect(results["Dune/Dune 2.mp4"]?.franchise == "Dune")
        let succession = results["Succession/Succession Season 2/Succession S2E1.mkv"]
        #expect(succession?.kind == .episode && succession?.show == "Succession" && succession?.season == 2)
        let invincible = results["Invincible (2021)/Invincible (2021) - S01E01 - It's About Time (1080p WEB-DL x265 SAMPA).mkv"]
        #expect(invincible?.show == "Invincible" && invincible?.episodeTitle == "It's About Time" && invincible?.year == 2021)
        let extra = results["The Wire/Featurettes/Season 4/The Game Is Real.mkv"]
        #expect(extra?.kind == .extra && extra?.show == "The Wire")
    }

    @Test func folderChoiceDecides() {
        let paths = ["IMG_1234.MOV", "Birthday.mp4", "Holiday S1E1.mp4"]
        let home = classify(paths, folder: .homeVideos)
        #expect(home.values.allSatisfy { $0.kind == .homeVideo })
        let guessed = classify(paths, folder: .auto, duration: 120)
        #expect(guessed["IMG_1234.MOV"]?.kind == .homeVideo)
        #expect(guessed["Birthday.mp4"]?.kind == .homeVideo)        // short, so a clip
        #expect(guessed["Holiday S1E1.mp4"]?.kind == .episode)
        let films = classify(paths, folder: .filmsAndTV, duration: 120)
        #expect(films["Birthday.mp4"]?.kind == .film)               // the user said films
    }
}

struct SectionShelfTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func episode(_ show: String, _ season: Int, _ number: Int, finished: Bool = false, progress: Double = 0,
                         played: TimeInterval? = nil, added: TimeInterval = 0) -> BrowseEntry {
        BrowseEntry(key: "\(show)-\(season)-\(number)", title: show, fileName: "", collection: show, sourceID: nil, sourceName: "",
                    isFileSource: false, date: nil, addedAt: now.addingTimeInterval(-added), duration: 3000,
                    progressFraction: progress, isFinished: finished, kind: .episode, show: show, season: season, episode: number,
                    lastPlayedAt: played.map { now.addingTimeInterval(-$0) })
    }

    private func film(_ title: String, year: Int? = nil, franchise: String? = nil, added: TimeInterval = 0, length: Double = 6000) -> BrowseEntry {
        BrowseEntry(key: title, title: title, fileName: title, collection: franchise ?? "", sourceID: nil, sourceName: "",
                    isFileSource: false, date: year.map { DateComponents(calendar: .init(identifier: .gregorian), year: $0).date! },
                    addedAt: now.addingTimeInterval(-added), duration: length, progressFraction: 0, isFinished: false,
                    kind: .film, franchise: franchise)
    }

    @Test func nextEpisodeFollowsWhereYouAre() {
        let fresh = [episode("S", 1, 1), episode("S", 1, 2)]
        #expect(TVLibrary.nextEpisode(fresh) == "S-1-1")
        let partway = [episode("S", 1, 1, finished: true, played: 100), episode("S", 1, 2, progress: 0.3, played: 10), episode("S", 1, 3)]
        #expect(TVLibrary.nextEpisode(partway) == "S-1-2")
        let between = [episode("S", 1, 1, finished: true, played: 100), episode("S", 1, 2, finished: true, played: 50),
                       episode("S", 2, 1)]
        #expect(TVLibrary.nextEpisode(between) == "S-2-1")
        #expect(TVLibrary.nextEpisode([episode("S", 1, 1, finished: true, played: 5)]) == nil)
    }

    @Test func groupsShowsInWatchingOrder() {
        let shows = TVLibrary.shows([episode("B", 2, 1), episode("B", 1, 10), episode("B", 1, 2), episode("A", 1, 1)])
        #expect(shows.map(\.name) == ["A", "B"])
        #expect(shows[1].episodeKeys == ["B-1-2", "B-1-10", "B-2-1"])
        #expect(shows[1].seasons == [1, 2])
    }

    @Test func franchisesInReleaseOrderWhenKnown() {
        let shelves = FilmShelves.build([
            film("Skyfall", year: 2012, franchise: "007"), film("Dr No", year: 1962, franchise: "007"),
            film("Rocky II", franchise: "Rocky"), film("Rocky", year: 1976, franchise: "Rocky"), film("Inception"),
        ], now: now)
        #expect(shelves.first { $0.kind == .franchise("007") }?.itemKeys == ["Dr No", "Skyfall"])
        #expect(shelves.first { $0.kind == .franchise("Rocky") }?.itemKeys == ["Rocky", "Rocky II"])   // a year missing: by title
    }

    @Test func homeCountsANewSeasonOnceAndPutsShowsInNextUp() {
        let entries = [
            episode("Show", 1, 2, added: 10), episode("Show", 1, 1, added: 10), episode("Show", 1, 3, added: 5),
            episode("Other", 1, 1, finished: true, played: 60, added: 90 * 86_400), episode("Other", 1, 2, added: 90 * 86_400),
            film("Old film", added: 90 * 86_400),
        ]
        let shelves = HomeShelves.build(entries, homeVideos: [], now: now)
        #expect(shelves.first { $0.kind == .nextUp }?.itemKeys == ["Other-1-2"])
        #expect(shelves.first { $0.kind == .recentlyAdded }?.itemKeys == ["Show-1-1"])
        #expect(shelves.first { $0.kind == .continueWatching } == nil)     // episodes live in Next Up
    }
}
