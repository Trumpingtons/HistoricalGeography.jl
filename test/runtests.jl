using HistoricalGeography, Test

@testset "HistoricalGeography" begin
	@testset "The maps of historical-basemaps" begin
		years = basemap_years()
		@test (length(years), first(years), last(years), issorted(years)) == (37, 100, 2010, true)
		# each map stands for its year until the year before the next: 1492 until 1499, 1500 until 1529, 2010 alone
		@test HistoricalGeography.basemap_spans(1495, 1530) == [(1492, 1499), (1500, 1529), (1530, 1599)]
		@test HistoricalGeography.basemap_spans(2005, 2024) == [(2000, 2009), (2010, 2010)]
		@test_throws ArgumentError HistoricalGeography.basemap_spans(-500, 50)
		@test_throws ArgumentError historical_basemaps(; folder = mktempdir(), since = 2011, upto = 2024)  # before any download
	end

	@testset "Counts, centuries and findspots of records" begin
		@test tally(["b", "a", "b", "c", "a", "b"]) == ["b" => 3, "a" => 2, "c" => 1]
		@test tally(["b", "a", "b", "c", "a", "b"]; top = 2) == ["b" => 3, "a" => 2]
		@test tallied([1900, 1800, 1900]) == "1900 (2), 1800 (1)"
		@test tallied([1900, 1800, 1900]; ordered = true) == "1800 (1), 1900 (2)"
		@test century.([-250, -101, -100, -1, 1, 100, 101, 1999]) == [-3, -2, -1, -1, 1, 1, 2, 20]
		rows = [(place = "Roma", modern = "", lon = 12.5, lat = 41.9), (place = "", modern = "", lon = 12.5, lat = 41.9),
			(place = "", modern = "Ostia Antica", lon = 12.3, lat = 41.75), (place = "Lost", modern = "", lon = missing, lat = missing)]
		features = HistoricalGeography.JSON.parse(read(findspots_geojson(rows; name = :place, fallback = :modern), String))["features"]
		@test [(f["geometry"]["coordinates"], f["properties"]["place"], f["properties"]["inscriptions"]) for f in features] ==
			[([12.5, 41.9], "Roma", 2), ([12.3, 41.75], "Ostia Antica", 1)]
	end

	@testset "Queries of words and the texts of books" begin
		q = text_query("tobacco OR (\"long s\" AND NOT pipe*)")
		@test [q("Of Tobacco"), q("the long  s here"), q("long s pipes"), q("tobacconist")] == [true, true, false, false]
		@test text_query("")("anything") && isempty(text_query("").patterns)
		@test_throws ErrorException text_query("(comet OR star")
		# as the printers of the time, u and v, i and j, and s and the long s are the same letter; OCR reads the long s as f
		@test [text_query("loue"; early_modern = true)("Of Love"), text_query("ioy"; early_modern = true)("joy"),
			text_query("telescope"; f_for_s = true)("a Telefcope")] == [true, true, true]
		@test query_hits(text_query("rail*"), "Railway, rail road, a rail.") == 3
		@test [occursin(r, "spoorwegen") for r in query_patterns("spoorweg"; prefix = true)] == [true]
		@test period_counts([1863, 1864, 1864], 1863, 1865) == ["1863" => 1, "1864" => 2, "1865" => 0]
		@test period_counts(Dict(1859 => 1, 1861 => 2), 1800, 1870)[end-2:end] == ["1850s" => 1, "1860s" => 2, "1870s" => 0]
		@test period_counts([1775, 1799, 1800], 1775, 1824; each = 25) == ["1775–1799" => 2, "1800–1824" => 1]
		rows = [(year = 2, hits = 1), (year = missing, hits = 5), (year = 1, hits = 3)]
		@test [(r.number, r.hits) for r in ranked(rows, "newest")] == [(1, 1), (2, 3), (3, 5)]
		@test [r.hits for r in ranked(rows, "relevance"; at_most = 2)] == [5, 3]
		@test HistoricalGeography.csv_rows("a,\"b,\"\"c\"\"\nd\"\r\ne,f") == [["a", "b,\"c\"\nd"], ["e", "f"]]
		@test plain_name("Spoorweg AND \"Den Haag\"") == "spoorweg-and-den-haag"
		@test HistoricalGeography.tcp_plain_text("<teiHeader>x</teiHeader><p>to<g ref=\"char:EOLhyphen\"/>bacco <gap reason=\"illegible\"/> and</p><l>a <note>n</note> line</l>") ==
			"tobacco 〈…〉 and\na [n] line"
		@test HistoricalGeography.gutenberg_life("Austen, Jane, 1775-1817; Other, 1800-1850") == (born = 1775, died = 1817)
		page = reading_page("A & B", ["a tobacco b", "none"]; marks = q.patterns, file = tempname() * ".html")
		@test page.passages == [1] && occursin("<p id=\"p1\">a <mark>tobacco</mark> b</p>", read(page.file, String))
	end

	@testset "The text of an EpiDoc edition" begin
		tei = """<TEI xmlns="http://www.tei-c.org/ns/1.0"><text><body><div type="edition"><head>Text</head><ab><lb n="1"/>Dis
			<expan>Manibus</expan><lb n="2"/>Ze<lb n="3" break="no"/>thi <choice><sic>vixt</sic><corr>vixit</corr></choice></ab></div>
			<origDate notBefore="-0049" notAfter="0050"/><geo>37.49025, 14.06216</geo></body></text></TEI>"""
		doc = HistoricalGeography.EzXML.parsexml(tei)
		@test HistoricalGeography.edition_text(HistoricalGeography.element(doc, "//t:div[@type='edition']")) == "Dis Manibus Zethi vixt"
		@test HistoricalGeography.origin_years(doc) == (-49, 50)
		@test HistoricalGeography.latlon(HistoricalGeography.field(doc, "//t:geo")) == (14.06216, 37.49025)
		@test HistoricalGeography.field(doc, "//t:title") == ""
	end

	@testset "Arrays of NumPy files" begin
		header = "{'descr': '|u1', 'fortran_order': False, 'shape': (2, 3), }"
		header = rpad(header, 64 - 10 - 1) * "\n"
		bytes = [0x93; codeunits("NUMPY"); 0x01; 0x00; UInt8(length(header)); 0x00; codeunits(header); UInt8[1, 2, 3, 4, 5, 6]]
		@test HistoricalGeography.npy(bytes) == UInt8[1 2 3; 4 5 6]
		header = "{'descr': '<i8', 'fortran_order': False, 'shape': (2,), }"
		header = rpad(header, 64 - 10 - 1) * "\n"
		bytes = [0x93; codeunits("NUMPY"); 0x01; 0x00; UInt8(length(header)); 0x00; codeunits(header); reinterpret(UInt8, Int64[7, -1])]
		@test HistoricalGeography.npy(bytes) == [7, -1]
	end

	@testset "Requests refused before any download" begin
		@test_throws ArgumentError cliopatria(; folder = mktempdir(), units = :provinces)
		@test_throws ArgumentError historical_borders(nothing, :seshat; folder = mktempdir())
		@test_throws ArgumentError historical_borders(nothing, :cshapes; folder = mktempdir(), box = (0, 0, 1))
		@test_throws ArgumentError historical_borders(nothing, :cshapes; folder = mktempdir(), since = 1950, upto = 1900)
	end

	@testset "The maps of France of IGN" begin
		cassini = ign_layer(:cassini)
		@test (cassini.minzoom, cassini.maxzoom, cassini.years) == (6, 14, "1756-1815")
		@test cassini.url == "https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=BNF-IGNF_GEOGRAPHICALGRIDSYSTEMS.CASSINI" *
			"&STYLE=normal&TILEMATRIXSET=PM_6_14&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&FORMAT=image/png"
		# IGN's terms ask the maps of Cassini to name the copy whose sheets were scanned
		@test (occursin("BIBLIOTHEQUE NATIONALE DE FRANCE", cassini.attribution), occursin("Archives nationales", ign_layer(:cassini_king).attribution),
			ign_layer(:plan).attribution) == (true, true, "IGN, Géoplateforme")
		@test length(ign_layers().id) == 10
		@test_throws ArgumentError ign_layer(:scan25)
	end

	@testset "Titles and years of IIIF manifests" begin
		@test HistoricalGeography.label_text(Dict("fr" => ["Plan de Paris"], "none" => ["x"])) in ("Plan de Paris", "x")
		@test HistoricalGeography.label_text(Dict("en" => String[], "nl" => ["Kaart van Leiden"])) == "Kaart van Leiden"
		@test HistoricalGeography.label_text([Dict("@value" => " Plan of London ", "@language" => "en")]) == "Plan of London"
		@test HistoricalGeography.label_text(nothing) == ""
		@test HistoricalGeography.manifest_year(Dict("navDate" => "1739-01-01T00:00:00Z")) == 1739
		dated = Dict("metadata" => [Dict("label" => Dict("en" => ["Scale"]), "value" => Dict("en" => ["1:5000, 1860"])),
			Dict("label" => Dict("en" => ["Date"]), "value" => Dict("none" => ["circa 1777"]))])
		@test HistoricalGeography.manifest_year(dated) == 1777
		@test ismissing(HistoricalGeography.manifest_year(Dict("metadata" => [Dict("label" => "Title", "value" => "Bologna 1702")])))
	end
	@testset "The pages of an e-codices manuscript, from the web or a saved copy" begin
		# A manifest of two canvases, already in the folder of downloads, so that nothing is downloaded
		folder, saved = mktempdir(), mktempdir()
		manifest = "https://e-codices.ch/metadata/iiif/kba-Test0001/manifest.json"
		mkpath(joinpath(folder, "e-codices"))
		cached = joinpath(folder, "e-codices", "kba-Test0001-manifest.json")
		write(cached, """{"sequences": [{"canvases": [
			{"label": "1r", "images": [{"resource": {"@id": "https://e-codices.ch/loris/kba/1r.jp2/full/full/0/default.jpg"}}]},
			{"label": "Front cover/back", "images": [{"resource": {"@id": "https://e-codices.ch/loris/kba/fc.jp2/full/full/0/default.jpg"}}]}]}]}""")
		web = (images = ["https://e-codices.ch/loris/kba/1r.jp2/full/2000,/0/default.jpg",
			"https://e-codices.ch/loris/kba/fc.jp2/full/2000,/0/default.jpg"], labels = ["1r", "Front cover/back"])
		@test ecodices_pages(manifest; folder) == web
		# A copy without its record is unfinished, and the pages still come from the web
		copy = joinpath(saved, "e-codices", "kba-Test0001")
		mkpath(copy)
		@test (ecodices_saved(manifest, saved), ecodices_pages(manifest; folder, saved)) == (nothing, web)
		# A whole copy, with its manifest and record as ecodices_save writes them, is read without the downloads
		cp(cached, joinpath(copy, "manifest.json"))
		rm(cached)
		write(joinpath(copy, "record.toml"), """
			manuscript = "MsTest 1"
			title = "A Test Psalter"
			date = "around 1300"
			citation = "Aarau, Aargauer Kantonsbibliothek, MsTest 1: A Test Psalter (https://e-codices.ch/en/list/one/kba/Test0001)."
			page = "https://e-codices.ch/en/list/one/kba/Test0001"
			images = 2
			""")
		local_pages = (images = [joinpath(copy, "0001 1r.jpg"), joinpath(copy, "0002 Front cover_back.jpg")], labels = web.labels)
		@test (ecodices_saved(manifest, saved), ecodices_pages(manifest; folder, saved), ecodices_copy_pages(saved, "kba-Test0001")) ==
			(copy, local_pages, local_pages)
		@test ecodices_copies(saved) == [(manuscript = "MsTest 1", title = "A Test Psalter", date = "around 1300",
			library = "Aarau, Aargauer Kantonsbibliothek", images = 2,
			citation = "Aarau, Aargauer Kantonsbibliothek, MsTest 1: A Test Psalter (https://e-codices.ch/en/list/one/kba/Test0001).",
			folder = "kba-Test0001", page = "https://e-codices.ch/en/list/one/kba/Test0001")]
		@test isempty(ecodices_copies(mktempdir()))
		# Ctrl+C during a download comes inside a TaskFailedException, and stops the save as Ctrl+C elsewhere does
		failed(e) = try wait(schedule(Task(() -> throw(e)))) catch caught caught end
		@test HistoricalGeography.interrupted.([InterruptException(), failed(InterruptException()), failed(ErrorException("x")), ErrorException("x")]) ==
			[true, true, false, false]
	end

	@testset "Allmaps and the famous maps" begin
		@test_throws ArgumentError allmaps(nothing; folder = mktempdir())  # neither at nor box, before any download
		@test_throws ArgumentError allmaps(nothing; at = (2.35, 48.86, 0), folder = mktempdir())
		maps = famous_maps()
		@test (length(maps.id), all(maps.west .< maps.east), all(maps.south .< maps.north)) == (8, true, true)
		mercator = famous_map(:mercator)
		@test (mercator.year, mercator.library) == (1569, "Universitätsbibliothek Basel")
		@test_throws ArgumentError famous_map(:piri_reis)
	end

	@testset "Names written into SQL" begin
		@test HistoricalGeography.quoted("Jacques' maps/x.geojson") == "Jacques'' maps/x.geojson"
	end

	@testset "Dates, points and queries of Wikidata" begin
		# Wikidata writes 490 BCE as -0489 (year 0 is 1 BCE)
		@test (HistoricalGeography.wikidata_year("-0489-09-12T00:00:00Z"), HistoricalGeography.wikidata_year("1863-07-01T00:00:00Z"),
			HistoricalGeography.wikidata_year("unknown")) == (-490, 1863, nothing)
		@test (HistoricalGeography.wikidata_point("Point(23.9667 38.1167)"), HistoricalGeography.wikidata_point("Point(1 2"),
			HistoricalGeography.wikidata_point(nothing)) == ((23.9667, 38.1167), nothing, nothing)
		@test HistoricalGeography.query_escape("wd:Q8676 é'~") == "wd%3AQ8676%20%C3%A9%27~"
		# an item that is part of a war and also a war is one of its battles
		@test HistoricalGeography.event_kind.(["war|battle", "war", "siege|naval battle", "naval battle|siege", "", nothing], ["Battle of Ilerda", "Gallic War", "Battle of Tauris", "Siege of Massilia", "", nothing]) ==
			["battle", "war", "naval battle", "siege", "", ""]
		@test HistoricalGeography.wikidata_corrections()["Q21008973"]["starts"] == -49
		@test_throws ArgumentError war_events(nothing, ["Q1238338", "Caesar"]; folder = mktempdir())
		@test_throws ArgumentError war_events(nothing, String[]; folder = mktempdir())
	end

	@testset "Routes across the antimeridian" begin
		# from 170 E to 170 W the short way: 10 degrees to the line, 10 beyond it, the latitude halfway between
		@test HistoricalGeography.route_lines([[170.0, 10.0], [-170.0, 20.0], [-160.0, 20.0]]) ==
			[Any[[170.0, 10.0], [180.0, 15.0]], Any[[-180.0, 15.0], [-170.0, 20.0], [-160.0, 20.0]]]
		@test HistoricalGeography.route_lines([[0.0, 0.0], [10.0, 5.0]]) == [Any[[0.0, 0.0], [10.0, 5.0]]]
	end

	@testset "Places named in a Perseus text" begin
		xml = """<div type="textpart" subtype="book" n="1"><div type="textpart" subtype="chapter" n="2">
			<placeName key="tgn,7001289">Argos</placeName> and <name type="place" key="perseus,Phoenicia"><reg>Phoenicia [35.5,34.0] (Perseus)</reg>the Phoenicians</name>
			<note>a note naming <placeName key="tgn,7010720">Athens</placeName></note></div></div>"""
		mentions, located = HistoricalGeography.perseus_mentions(xml)
		@test (mentions, located) == ([(key = "tgn,7001289", name = "Argos", passage = "1.2"), (key = "perseus,Phoenicia", name = "the Phoenicians", passage = "1.2")],
			Dict("perseus,Phoenicia" => (35.5, 34.0)))
	end

	@testset "The topic data written by hand" begin
		@test HistoricalGeography.topic_names() == [:amundsen, :bly, :burckhardt, :columbus, :darwin, :decameron, :faxian, :genji, :humboldt, :magellan, :meghaduta, :nights,
			:nikitin, :odysseus, :periplus, :peter, :petrie, :polo, :qin, :samudragupta, :stark, :vangogh, :xuanzang, :zhenghe]
		# every event, stage and mention names a place of its file, and every place is named
		for name in HistoricalGeography.topic_names()
			data = HistoricalGeography.topic_data(name)
			items = [get(data, "events", []); get(data, "stages", []); get(data, "mentions", [])]
			named = Set(item["place"] for item in items)
			@test (name, issubset(named, keys(data["places"])), length(named) == length(data["places"]), all(item -> !isempty(item["passage"]), items)) ==
				(name, true, true, true)
		end
		# a painting of a stage has a caption and the address of its image at Wikimedia Commons
		@test (HistoricalGeography.painting_caption(Dict("title" => "Irises", "year" => 1889, "collection" => "J. Paul Getty Museum")),
			HistoricalGeography.painting_caption(Dict("title" => "Portrait of Alfred Bruyas", "painter" => "Eugène Delacroix", "year" => 1853)),
			HistoricalGeography.commons_image("Vincent van Gogh - Portrait of Doctor Félix Rey (F500).jpg")) ==
			("Irises (1889), J. Paul Getty Museum", "Portrait of Alfred Bruyas (1853), Eugène Delacroix",
			"https://commons.wikimedia.org/wiki/Special:FilePath/Vincent_van_Gogh_-_Portrait_of_Doctor_F%C3%A9lix_Rey_(F500).jpg?width=640")
		@test all(item -> !haskey(item, "painting") || (!isempty(item["painting"]["title"]) && !isempty(item["painting"]["file"])),
			[HistoricalGeography.topic_data(:vangogh)["stages"]; HistoricalGeography.topic_data(:decameron)["mentions"]])
		@test_throws ArgumentError HistoricalGeography.topic_data(:iliad)
		@test_throws ArgumentError journey(nothing, :iliad; folder = mktempdir())
		@test_throws ArgumentError text_places(nothing, :iliad; folder = mktempdir())
		@test_throws ArgumentError battlefields(nothing, :korea; folder = mktempdir())
	end
end
