# The sources of epigraphy: the databases and corpora of Latin, Greek and other inscriptions, of cuneiform texts and
# of runic inscriptions, each downloaded once into a folder

"""
	edh(con; folder, table = "edh")

The inscriptions of the Epigraphic Database Heidelberg (EDH), a CSV file of 60 MB downloaded once into `folder`,
written to the table `table` of `con`: a row per inscription with its number (`edh`), `province`, ancient and modern
findspot (`findspot`, `modern_findspot`), `type`, `material`, years (`year_from`, `year_to`), `text`, and the
coordinates of its findspot (`lon`, `lat`). Returns the number of inscriptions.
"""
function edh(con; folder::AbstractString, table::AbstractString = "edh")
	file = kept("https://edh.ub.uni-heidelberg.de/data/download/edh_data_text.csv", joinpath(folder, "edh_data_text.csv"))
	# The EDH gives the coordinates as latitude, longitude
	DBInterface.execute(con, """CREATE OR REPLACE TABLE "$(table)" AS
		SELECT hd_nr AS edh, provinz AS province, fo_antik AS findspot, fo_modern AS modern_findspot, i_gattung AS type, material,
			TRY_CAST(dat_jahr_a AS INTEGER) AS year_from, TRY_CAST(dat_jahr_e AS INTEGER) AS year_to, atext AS text,
			TRY_CAST(split_part(koordinaten1, ',', 2) AS DOUBLE) AS lon, TRY_CAST(split_part(koordinaten1, ',', 1) AS DOUBLE) AS lat
		FROM read_csv('$(quoted(file))', header = true, all_varchar = true) ORDER BY edh""")
	return only(rows(con, """SELECT count(*) AS n FROM "$(table)" """).n)
end

"""
	list_inscriptions(con; folder, table = "list")

Latin Inscriptions in Space and Time (LIST) 1.2, a Parquet file of 110 MB downloaded once into `folder`, written to
the table `table` of `con`: a row per inscription with its numbers in LIST, the EDCS and the EDH (`list`, `edcs`,
`edh`), its `province`, `findspot`, `type` (predicted by a model for the inscriptions of the EDCS alone), `material`,
years (`year_from`, `year_to`), `urban_context`, `text`, and coordinates (`lon`, `lat`). Returns the number of
inscriptions.
"""
function list_inscriptions(con; folder::AbstractString, table::AbstractString = "list")
	file = kept("https://zenodo.org/records/10473706/files/LIST_v1-2.parquet?download=1", joinpath(folder, "LIST_v1-2.parquet"))
	DBInterface.execute(con, """CREATE OR REPLACE TABLE "$(table)" AS
		SELECT "LIST-ID" AS list, "EDCS-ID" AS edcs, "EDH-ID" AS edh, province_label_clean AS province, findspot_ancient_clean AS findspot,
			coalesce(type_of_inscription_clean, type_of_inscription_auto) AS type, material_clean AS material,
			CAST(not_before AS INTEGER) AS year_from, CAST(not_after AS INTEGER) AS year_to, urban_context,
			clean_text_interpretive_word AS text, Longitude AS lon, Latitude AS lat
		FROM read_parquet('$(quoted(file))') ORDER BY list""")
	return only(rows(con, """SELECT count(*) AS n FROM "$(table)" """).n)
end

"""The records of the XML entries of a zip archive, read without unpacking it."""
zip_records(f, reader) =
	xml_records(f, filter(name -> endswith(name, ".xml"), zip_names(reader)); parse = name -> EzXML.parsexml(zip_readentry(reader, name, String)))

"""
	edr(; folder)

The inscriptions of the Epigraphic Database Roma (EDR), an archive of 268 MB downloaded once into `folder` from
Zenodo and read without unpacking it, which takes a few minutes: a row per inscription with its number (`edr`),
`region` (a province or a region of Italy), `place`, `findspot`, modern `country`, `type`, `object`, `material`,
years (`from`, `to`) and `text`, as written with its abbreviations expanded.
"""
function edr(; folder::AbstractString)
	reader = ZipReader(Mmap.mmap(kept("https://zenodo.org/records/18468635/files/EDR.zip?download=1", joinpath(folder, "EDR.zip"))))
	zip_records(reader) do doc
		(edr = field(doc, "//t:idno[@type='localID']"), region = field(doc, "//t:origPlace/t:placeName[@type='provinceItalicRegion']"),
			place = field(doc, "//t:origPlace/t:placeName[not(@type)]"),
			findspot = field(doc, "//t:provenance[@type='found']/t:placeName[@type='locus']"),
			country = field(doc, "//t:placeName[@type='modernCountry']"), type = field(doc, "//t:keywords/t:term"),
			object = field(doc, "//t:objectType"), material = field(doc, "//t:material"),
			from = year_of(field(doc, "//t:origDate/@notBefore-custom")), to = year_of(field(doc, "//t:origDate/@notAfter-custom")),
			text = edition_text(element(doc, "//t:div[@type='edition']")))
	end
end

"""
	irt(; folder)

The Inscriptions of Roman Tripolitania (IRT 2009), an archive of 3 MB downloaded once into `folder` and read without
unpacking it: a row per inscription with its number (`irt`), `title`, `type`, `language` (ISO 639: la Latin, grc
Ancient Greek, ber-Latn a Berber language in the Latin alphabet), `object`, `material`, ancient and modern findspot
(`findspot`, `modern_findspot`), years (`from`, `to`), `text` (the edition, not the reconstruction that follows it in
a few records) and English `translation`.
"""
function irt(; folder::AbstractString)
	reader = ZipReader(read(kept("https://inslib.kcl.ac.uk/irt2009/redist/inscr/irt2009-P5.zip", joinpath(folder, "irt2009-P5.zip"))))
	zip_records(reader) do doc
		edition = element(doc, "//t:div[@type='edition'][not(@subtype='reconstruction')]")
		from, to = origin_years(doc)
		(irt = field(doc, "//t:idno[@type='filename']"), title = join(split(field(doc, "//t:titleStmt/t:title")), " "),
			type = lowercase(field(doc, "//t:titleStmt/t:title/t:rs[@type='textType']")), language = language_of(edition),
			object = field(doc, "//t:rs[@type='objectType']"), material = field(doc, "//t:material"),
			findspot = field(doc, "//t:placeName[@type='ancientFindspot']"), modern_findspot = field(doc, "//t:placeName[@type='modernFindspot']"),
			from = from, to = to, text = edition_text(edition), translation = edition_text(element(doc, "//t:div[@type='translation']")))
	end
end

"""
	isicily(; folder)

The inscriptions of I.Sicily, an archive of 9 MB downloaded once into `folder` from GitHub: a row per inscription
with its number (`isicily`), `title`, `language` (ISO 639: grc Ancient Greek, la Latin, xly Elymian, scx Sicel, xpu
Punic, osc Oscan, he Hebrew), `type`, `object`, `material`, ancient and modern place (`place`, `modern_place`), years
(`from`, `to`), `text` (the primary edition, not the lemmatised one that follows it in some records), and the
coordinates of its findspot (`lon`, `lat`).
"""
function isicily(; folder::AbstractString)
	archive = kept("https://codeload.github.com/ISicily/ISicily/tar.gz/refs/heads/master", joinpath(folder, "ISicily.tar.gz"))
	xml_records(xml_files(extracted(archive, joinpath(folder, "ISicily"), "ISicily-master/inscriptions"))) do doc
		lon, lat = latlon(field(doc, "//t:origPlace/t:geo"))
		(isicily = field(doc, "//t:idno[@type='filename']"), title = field(doc, "//t:titleStmt/t:title"),
			language = field(doc, "//t:textLang/@mainLang"), type = field(doc, "//t:keywords/t:term"),
			object = field(doc, "//t:objectType"), material = field(doc, "//t:material"),
			place = field(doc, "//t:origPlace/t:placeName[@type='ancient']"), modern_place = field(doc, "//t:origPlace/t:placeName[@type='modern']"),
			from = year_of(field(doc, "//t:origDate/@notBefore-custom")), to = year_of(field(doc, "//t:origDate/@notAfter-custom")),
			text = edition_text(element(doc, "//t:div[@type='edition'][@subtype='primary']", "//t:div[@type='edition']")), lon = lon, lat = lat)
	end
end

"""
	iip(; folder)

The Inscriptions of Israel/Palestine (IIP), an archive of 7 MB downloaded once into `folder` from GitHub, without the
file on which the IIP tests its encoding: a row per inscription with its number (`iip`), `language` (ISO 639: grc
Ancient Greek, arc Aramaic, he Hebrew, la Latin, phn Phoenician), `type` and `religion` (classes of the IIP's
taxonomy), `region`, `place`, `site`, years (`from`, `to`), `text` (the transcription, else the transcription divided
into words, else the diplomatic edition), English `translation`, and the coordinates of its place (`lon`, `lat`).
"""
function iip(; folder::AbstractString)
	archive = kept("https://codeload.github.com/Brown-University-Library/iip-texts/tar.gz/refs/heads/master", joinpath(folder, "iip-texts.tar.gz"))
	files = xml_files(extracted(archive, joinpath(folder, "IIP"), "iip-texts-master/epidoc-files"); skip = ("aaTestFile.xml",))
	xml_records(files) do doc
		edition = element(doc, ("//t:div[@type='edition'][@subtype='$(s)']" for s in ("transcription", "transcription_segmented", "diplomatic"))...)
		lon, lat = latlon(field(doc, "//t:origin//t:settlement/t:geo"))
		(iip = field(doc, "//t:idno[@type='IIP']"), language = field(doc, "//t:textLang/@mainLang"),
			type = class_of(field(doc, "//t:msItem/@class")), religion = class_of(field(doc, "//t:msItem/@ana")),
			region = field(doc, "//t:origin//t:region"), place = field(doc, "//t:origin//t:settlement/text()"),
			site = field(doc, "//t:origin//t:geogName[@type='site']"),
			from = year_of(field(doc, "//t:origin/t:date/@notBefore")), to = year_of(field(doc, "//t:origin/t:date/@notAfter")),
			text = edition_text(edition), translation = edition_text(element(doc, "//t:div[@type='translation']")), lon = lon, lat = lat)
	end
end

"""
	usep(; folder)

The inscriptions of the U.S. Epigraphy Project (USEP), the Greek and Latin inscriptions kept in the United States, an
archive of 8 MB downloaded once into `folder` from GitHub: a row per inscription with its number (`usep`), `status`
(transcribed, metadata_only, described and not yet transcribed, or bib_only, known from the bibliography), where it
is kept (`state`, the US state or the country, `city` and `institution`), `summary`, `language` (ISO 639: lat Latin,
grc Ancient Greek, grc-Cprt Greek in the Cypriot syllabary, ett Etruscan, phn Phoenician, und undetermined), `type`,
`object`, `material`, `origin`, years (`from`, `to`) and `text`.
"""
function usep(; folder::AbstractString)
	archive = kept("https://codeload.github.com/Brown-University-Library/usep-data/tar.gz/refs/heads/master", joinpath(folder, "usep-data.tar.gz"))
	files = xml_files(extracted(archive, joinpath(folder, "USEP"), "usep-data-master/xml_inscriptions"))
	# The records are in three folders, by their status
	xml_records(files; parse = file -> (basename(dirname(file)), EzXML.readxml(file))) do (status, doc)
		(usep = field(doc, "//t:idno[@type='USEpigraphy']"), status = status, state = field(doc, "//t:msIdentifier/t:region"),
			city = field(doc, "//t:msIdentifier/t:settlement"), institution = field(doc, "//t:msIdentifier/t:institution"),
			summary = field(doc, "//t:msContents/t:summary"), language = field(doc, "//t:textLang/@mainLang"),
			type = class_of(field(doc, "//t:msItem/@class")), object = class_of(field(doc, "//t:objectDesc/@ana")),
			material = class_of(field(doc, "//t:supportDesc/@ana")), origin = field(doc, "//t:origin/t:placeName"),
			from = year_of(field(doc, "//t:origin/t:date/@notBefore")), to = year_of(field(doc, "//t:origin/t:date/@notAfter")),
			text = edition_text(element(doc, "//t:div[@type='edition']")))
	end
end

"""A field of a CSV file, between double quotes, its own doubled."""
csv_field(value) = "\"" * replace(string(value), "\"" => "\"\"") * "\""

"""
	cdli(con; folder, table = "cdli")

The catalogue and the transliterations of the Cuneiform Digital Library Initiative (CDLI), from its dump of August
2022 on GitHub, files of 155 MB and 87 MB downloaded once into `folder`, written to the table `table` of `con`: a row
per object with its CDLI number (`cdli`, as P000001), `designation`, `period`, `provenience`, `genre`, `subgenre`,
`language`, `material`, `object` type, `museum_number`, `collection` and `primary_publication`, its number of
transliterated `lines`, and the start (200 characters) of its `transliteration`, a line after another, and of its
English `translation`. Returns the number of objects.

In the transliterations, in ATF, an object starts with a line `&P000001 = ...`, and each line of its text starts with
its number, as `1.` or `2'.`; `#tr.en:` starts a line of English translation, and the lines that start with `@`, `\$`,
`#` and `>` describe the object or its lines.
"""
function cdli(con; folder::AbstractString, table::AbstractString = "cdli")
	dump = "https://media.githubusercontent.com/media/cdli-gh/data/master/"
	catalogue = kept(dump * "cdli_cat.csv", joinpath(folder, "cdli_cat.csv"))
	atf = kept(dump * "cdliatf_unblocked.atf", joinpath(folder, "cdliatf_unblocked.atf"))
	transliterated, english = Dict{String, Vector{String}}(), Dict{String, Vector{String}}()
	current = ""
	for line in eachline(atf)
		if startswith(line, "&P")
			current = line[2:8]
		elseif startswith(line, "#tr.en:")
			push!(get!(english, current, String[]), strip(line[8:end]))
		elseif !isempty(line) && !(line[1] in "@\$#>&")
			m = match(r"^\S+\.\s+(?<text>.+)$", line)
			m === nothing || push!(get!(transliterated, current, String[]), strip(m[:text]))
		end
	end
	texts = tempname() * ".csv"
	open(texts, "w") do io
		println(io, "cdli,lines,transliteration,translation")
		for id in union(keys(transliterated), keys(english))
			lines = get(transliterated, id, String[])
			println(io, join(csv_field.([id, length(lines), first(join(lines, " / "), 200), first(join(get(english, id, String[]), " "), 200)]), ","))
		end
	end
	DBInterface.execute(con, """CREATE OR REPLACE TABLE "$(table)" AS
		SELECT c.*, coalesce(t.lines, 0) AS lines, coalesce(t.transliteration, '') AS transliteration, coalesce(t.translation, '') AS translation
		FROM (SELECT 'P' || lpad(id_text, 6, '0') AS cdli, designation, period, provenience, genre, subgenre, language, material,
				object_type AS object, museum_no AS museum_number, collection, primary_publication
			FROM read_csv('$(quoted(catalogue))', header = true, all_varchar = true)) c
		LEFT JOIN read_csv('$(quoted(texts))', header = true, all_varchar = false,
			columns = {'cdli': 'VARCHAR', 'lines': 'INTEGER', 'transliteration': 'VARCHAR', 'translation': 'VARCHAR'}) t USING (cdli)
		ORDER BY cdli""")
	rm(texts)
	return only(rows(con, """SELECT count(*) AS n FROM "$(table)" """).n)
end

"""The words of a text of ORACC, the nodes `l` of its tree, each with its form as written, citation form, guide word and part of speech."""
function oracc_words!(found, node)
	node isa AbstractDict || return found
	if get(node, "node", "") == "l" && haskey(node, "f")
		f = node["f"]
		push!(found, (form = string(get(node, "frag", "")), cf = string(get(f, "cf", "")), gw = string(get(f, "gw", "")),
			pos = string(get(f, "pos", ""))))
	end
	foreach(child -> oracc_words!(found, child), get(node, "cdl", []))
	return found
end

"""
	oracc(project; folder)

The texts of a project of the Open Richly Annotated Cuneiform Corpus (ORACC), by its name on ORACC's JSON page
(oracc.museum.upenn.edu/json): `rinap`, the Royal Inscriptions of the Neo-Assyrian Period, or `riao`, `ribo`,
`etcsri`, `saao`, `dcclt` and others. The JSON archives of the project and of its subprojects are downloaded once
into `folder`. Returns `(; texts, glossary)`: a row per text of the catalogue with its number (`text`),
`designation`, `popular_name`, `ruler`, `period`, `genre`, `object`, `material`, `provenience`, `date`, number of
`words` (0 for a text without an edition), the start (200 characters) of its `transliteration`, and the coordinates of
its provenience from Pleiades (`lon`, `lat`); and a row per word of the glossary of the edited texts, by its
citation form (`cf`), guide word (`gw`, a short English meaning) and part of speech (`pos`: N noun, V verb, AJ
adjective, AV adverb; RN royal name, GN geographical name, DN divine name, PN personal name and others), with its
number of `occurrences`, the most frequent first.
"""
function oracc(project::AbstractString; folder::AbstractString)
	function archive(name)
		file = replace(name, "/" => "-") * ".zip"
		return ZipReader(read(kept("https://oracc.museum.upenn.edu/json/$(file)", joinpath(folder, "oracc", file))))
	end
	readjson(reader, name) = JSON.parse(zip_readentry(reader, name, String))
	main = archive(project)
	catalogue = readjson(main, "$(project)/catalogue.json")["members"]
	# A project with subprojects names them in its proxies, one without lists its texts in its members
	corpus = readjson(main, "$(project)/corpus.json")
	proxies = haskey(corpus, "proxies") ? Dict(string(k) => string(v) for (k, v) in corpus["proxies"]) :
		Dict(string(id) => project for id in keys(corpus["members"]))
	readers = Dict(sub => sub == project ? main : archive(sub) for sub in unique(values(proxies)))
	names = Dict(sub => Set(zip_names(reader)) for (sub, reader) in readers)
	Word = NamedTuple{(:form, :cf, :gw, :pos), NTuple{4, String}}
	words = Dict{String, Vector{Word}}()
	for (id, sub) in proxies
		name = "$(sub)/corpusjson/$(id).json"
		name in names[sub] || continue
		content = zip_readentry(readers[sub], name, String)
		isempty(content) || (words[id] = oracc_words!(Word[], JSON.parse(content)))
	end
	value(entry, key) = string(get(entry, key, ""))
	function coordinates(text)
		m = match(r"^\[(?<lon>-?[\d.]+),\s*(?<lat>-?[\d.]+)\]$", text)
		return m === nothing ? (missing, missing) : (parse(Float64, m[:lon]), parse(Float64, m[:lat]))
	end
	texts = map(sort!(string.(collect(keys(catalogue))))) do id
		entry = catalogue[id]
		these = get(words, id, Word[])
		lon, lat = coordinates(value(entry, "pleiades_coord"))
		(text = id, designation = value(entry, "designation"), popular_name = value(entry, "popular_name"), ruler = value(entry, "ruler"),
			period = value(entry, "period"), genre = value(entry, "genre"), object = value(entry, "object_type"),
			material = value(entry, "material"), provenience = value(entry, "provenience"), date = value(entry, "date_of_origin"),
			words = length(these), transliteration = first(join((w.form for w in these), " "), 200), lon = lon, lat = lat)
	end
	lemmas = [(w.cf, w.gw, w.pos) for these in values(words) for w in these if !isempty(w.cf)]
	glossary = [(cf = cf, gw = gw, pos = pos, occurrences = n) for ((cf, gw, pos), n) in tally(lemmas)]
	return (; texts, glossary)
end

"""
	dio(con; folder, table = "dio")

The articles of the German Inscriptions Online (Deutsche Inschriften Online, DIO), a dump of 2 MB downloaded once
into `folder` and unpacked into a JSON-LD file of 54 MB, written to the table `table` of `con`: a row per article with
its id (`article`), its `volume` and `number` in the series Die Deutschen Inschriften (DI) when it is printed in one
(the others are online only, or come from other projects), its `title`, years (`year_from`, `year_to`), the Wikidata
ids of its city or district and of some objects (`wikidata`), and its number of `images`, in the order of the
volumes and then of the articles. Returns the number of articles.
"""
function dio(con; folder::AbstractString, table::AbstractString = "dio")
	archive = kept("https://epigraf.inschriften.net/files/download/77936", joinpath(folder, "epigraf-public-cgif-001.zip"))
	file = joinpath(folder, "epigraf-public-cgif-001.jsonld")
	isfile(file) || write(file, zip_readentry(ZipReader(read(archive)), "epigraf-public-cgif-001.jsonld"))
	# The file is a single JSON object, larger than DuckDB reads by default
	DBInterface.execute(con, """CREATE OR REPLACE TABLE "$(table)" AS
		WITH articles AS (SELECT unnest("@reverse"."schema:isPartOf") AS a
			FROM read_json('$(quoted(file))', maximum_object_size = 200000000)),
		rows AS (SELECT regexp_extract(a."@id", '/([^/]+)#dfi\$', 1) AS article,
			'DI ' || TRY_CAST(regexp_extract(a."@id", '~di(\\d+)-', 1) AS INTEGER) AS volume,
			nullif(regexp_extract(a."@id", '~di\\d+-0*(\\w+)', 1), '') AS number, a."schema:name" AS title,
			TRY_CAST(left(a."schema:temporalCoverage"."@value", 4) AS INTEGER) AS year_from,
			TRY_CAST(left(split_part(a."schema:temporalCoverage"."@value", '/', 2), 4) AS INTEGER) AS year_to,
			array_to_string(list_transform(list_filter(a."schema:keywords", lambda k: k."@id" LIKE 'wd:%'),
				lambda k: replace(k."@id", 'wd:', '')), ', ') AS wikidata,
			CAST(CASE WHEN a."schema:image" IS NULL THEN 0 WHEN json_type(a."schema:image") = 'ARRAY'
				THEN json_array_length(a."schema:image") ELSE 1 END AS INTEGER) AS images
		FROM articles)
		SELECT * FROM rows ORDER BY TRY_CAST(regexp_extract(volume, '\\d+') AS INTEGER) NULLS LAST, article""")
	return only(rows(con, """SELECT count(*) AS n FROM "$(table)" """).n)
end

# The files of Rundata are in Windows-1252: the bytes 0x80 to 0x9f are the characters of this table, the others the
# characters of the same code
const WINDOWS_1252 = collect("€\u81‚ƒ„…†‡ˆ‰Š‹Œ\u8dŽ\u8f\u90‘’“”•–—˜™š›œ\u9džŸ")

"""
	rundata(con; folder)

Rundata 3.1, the Scandinavian Runic-text Database, from the files of its Windows program (2018), an archive of 5 MB
downloaded once into `folder` and read without unpacking it: a row per inscription with its `signum` (as U 344; its
first part is the region, a Swedish province as U Uppland, Sö Södermanland, Ög Östergötland, or N Norway, DR
Denmark and others), `place`, `parish`, `municipality`, `period` (V the Viking Age, M the Middle Ages, U the
Proto-Norse period), `object`, `material`, `carver`, `style`, `runes` (transliterated) and `english` translation,
and the coordinates of its findspot, else of where it is now (`lon`, `lat`). Coordinates given in the Swedish grid
RT90 are converted to longitude and latitude by DuckDB's extension `spatial`, which `con` must have loaded.
"""
function rundata(con; folder::AbstractString)
	reader = ZipReader(read(kept("https://www.runforum.nordiska.uu.se/filer/rundata_3-1_zip.zip", joinpath(folder, "rundata_3-1_zip.zip"))))
	decoded(bytes) = String([0x80 <= b <= 0x9f ? WINDOWS_1252[b - 0x7f] : Char(b) for b in bytes])
	# The records of a file, a line each, without the lines of its header, which start with "!"
	lines(name) = filter(line -> !isempty(line) && !startswith(line, '!'), split(decoded(zip_readentry(reader, name)), "\r\n"))
	# A record starts with its signum and its flags (as † for a lost inscription); in RUNDATA.INF its fields follow, each
	# between two copies of a control character, the place of its letter in the alphabet: P (16) the place, X (24) the
	# coordinates, D (4) the period and so on
	signum(line) = join(first(split(line, ' '), 2), ' ')
	head(line) = line[1:prevind(line, something(findfirst(c -> c < ' ', line), lastindex(line) + 1))]
	function value(line, letter)
		mark = Char(letter - 'A' + 1)
		start = findfirst(mark, line)
		stop = start === nothing ? nothing : findnext(mark, line, nextind(line, start))
		return stop === nothing ? "" : String(strip(line[nextind(line, start):prevind(line, stop)]))
	end
	info = lines("RUNDATA.INF")
	heads = Dict(signum(line) => head(line) for line in info)
	texts(name) = Dict(signum(line) => String(strip(chopprefix(line, get(heads, signum(line), "")))) for line in lines(name))
	runes, english = texts("RUNDATA.RUN"), texts("RUNDATA.ENG")
	# Latitude and longitude in brackets, as (59.3293 ; 18.0686), or northing and easting in RT90, as 6275755.1538971
	function coordinates(text)
		m = match(r"\((?<lat>-?[\d.]+) ; (?<lon>-?[\d.]+)\)", text)
		m === nothing || return (lon = parse(Float64, m[:lon]), lat = parse(Float64, m[:lat]), east = missing, north = missing)
		m = match(r"^(?<north>\d{7})\.(?<east>\d{7})$", text)
		m === nothing || return (lon = missing, lat = missing, east = parse(Float64, m[:east]), north = parse(Float64, m[:north]))
		return (lon = missing, lat = missing, east = missing, north = missing)
	end
	records = map(info) do line
		s = signum(line)
		x = value(line, 'X')
		(signum = s, place = value(line, 'P'), parish = value(line, 'S'), municipality = value(line, 'K'), period = value(line, 'D'),
			object = value(line, 'L'), material = value(line, 'I'), carver = value(line, 'R'), style = value(line, 'G'),
			runes = get(runes, s, ""), english = get(english, s, ""), coordinates(isempty(x) ? value(line, 'Y') : x)...)
	end
	grid = tempname() * ".csv"
	write(grid, "signum,east,north\n" * join(("$(csv_field(r.signum)),$(r.east),$(r.north)" for r in records if !ismissing(r.east)), "\n"))
	converted = rows(con, """SELECT signum, ST_X(p) AS lon, ST_Y(p) AS lat FROM (SELECT signum,
		ST_Transform(ST_Point(east, north), 'EPSG:3021', 'EPSG:4326', always_xy := true) AS p FROM read_csv('$(quoted(grid))', header = true))""")
	rm(grid)
	lonlat = Dict(converted.signum[i] => (converted.lon[i], converted.lat[i]) for i in eachindex(converted.signum))
	return [begin
		lon, lat = haskey(lonlat, r.signum) ? lonlat[r.signum] : (r.lon, r.lat)
		merge(Base.structdiff(r, NamedTuple{(:lon, :lat, :east, :north)}), (lon = lon, lat = lat))
	end for r in records]
end
