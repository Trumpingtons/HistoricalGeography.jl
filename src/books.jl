# The texts of antique books: those of the Text Creation Partnership (EEBO-TCP, ECCO-TCP and Evans-TCP), of the
# Deutsches Textarchiv, of Project Gutenberg and of Wikisource, each found by a query of words and downloaded once
# into a folder

"""The first letters of the TCP's numbers of the texts of each of its collections."""
const TCP_COLLECTIONS = Dict("EEBO-TCP" => "AB", "ECCO-TCP" => "K", "Evans-TCP" => "N")

"""The year of a date as a catalogue writes it, its first four digits in a row; 0 when it has none."""
first_year(date::AbstractString) = (m = match(r"\d{4}", date); m === nothing ? 0 : parse(Int, m.match))

"""
	tcp_catalogue(; folder)

The catalogue of the Text Creation Partnership, TCP.csv of its repository Texts on GitHub, downloaded once into
`folder/tcp`: a row per text, with the fields of the catalogue in lower case: `tcp` (the TCP's number of the text),
`eebo`, `vid`, `stc`, `status`, `author`, `date`, `title`, `terms` (its subjects) and `pages`.
"""
function tcp_catalogue(; folder::AbstractString)
	file = kept("https://raw.githubusercontent.com/textcreationpartnership/Texts/master/TCP.csv", joinpath(folder, "tcp", "TCP.csv");
		agent = RESEARCH_AGENT)
	rows = csv_rows(read(file, String))
	header = Tuple(Symbol.(lowercase.(first(rows))))
	return [NamedTuple{header}(Tuple(r)) for r in rows[2:end] if length(r) == length(header)]
end

"""
	tcp_works(collection, query, from, to; folder)

The works of `collection` ("EEBO-TCP", "ECCO-TCP" or "Evans-TCP") in the [`tcp_catalogue`](@ref) printed from `from`
to `to` whose records, their title, author and subjects, answer `query`, a [`text_query`](@ref): each row of the
catalogue with its `year` and its `record_hits`, the number of times its record has the words.
"""
function tcp_works(collection::AbstractString, query::TextQuery, from::Integer, to::Integer; folder::AbstractString)
	prefixes = TCP_COLLECTIONS[collection]
	record(r) = join((r.title, r.author, r.terms), " ; ")
	return [merge(r, (year = first_year(r.date), record_hits = query_hits(query, record(r))))
		for r in tcp_catalogue(; folder) if first(r.tcp) in prefixes && from <= first_year(r.date) <= to && query(record(r))]
end

const TCP_BLOCK_ENDS = r"</(?:p|l|head|speaker|stage|item|trailer|closer|salute|signed|byline|cell|dateline|opener|argument|epigraph|row)>"

"""
The text of a TCP file: its text without the header, a paragraph each block, a line of verse or a speech; the
hyphens at the ends of lines removed, the notes in brackets, and what the keyers could not read as the TCP writes
it: • a letter, 〈◊〉 a word, 〈…〉 more.
"""
function tcp_plain_text(xml::AbstractString)
	header_end = findfirst("</teiHeader>", xml)
	body = header_end === nothing ? xml : xml[nextind(xml, last(header_end)):end]
	body = replace(body, r"<g ref=\"char:EOLhyphen\"\s*/>" => "", r"<gap[^>]*>\s*<desc>(?<desc>.*?)</desc>\s*</gap>"s => s"\g<desc>",
		r"<gap[^>]*/>" => "〈…〉", r"<gap[^>]*>.*?</gap>"s => "〈…〉", r"<note[^>]*>" => " [", "</note>" => "] ", TCP_BLOCK_ENDS => "\n", r"<[^>]+>" => "")
	body = replace(body, "&amp;" => "&", "&lt;" => "<", "&gt;" => ">", "&quot;" => "\"", "&apos;" => "'")
	return join(filter(!isempty, [strip(replace(line, r"\s+" => " ")) for line in split(body, "\n")]), "\n")
end

"""
The first `at_most` of the works found in a catalogue, by `date` ("oldest" or "newest", those without one last), or
else those whose records have the words most.
"""
function candidates(found, order::AbstractString, at_most::Integer; date::Function)
	undated = filter(r -> date(r) === nothing, found)
	dated = filter(r -> date(r) !== nothing, found)
	sorted = order == "oldest" ? [sort(dated; by = date); undated] : order == "newest" ? [sort(dated; by = date, rev = true); undated] :
		sort(found; by = r -> -r.record_hits)
	return first(sorted, min(at_most, length(sorted)))
end

"""The texts kept, those that answer `query`, numbered; with words in `query`, in order of relevance, sorted by their hits."""
function numbered_texts(texts, query::TextQuery, order::AbstractString)
	isempty(query.patterns) || order != "relevance" || sort!(texts; by = r -> -r.hits)
	return [merge((number = i,), r) for (i, r) in enumerate(texts)]
end

"""
	tcp_texts(works, query; at_most = 100, order = "oldest", folder)

The texts of the first `at_most` of `works` (those of [`tcp_works`](@ref)) in `order`: "oldest", "newest", or
"relevance", those whose records have the words most. Each is downloaded once into `folder/tcp/texts` from its
repository of the TCP on GitHub, a fifth of a second apart, and read as text: without its header, a paragraph each
block (a paragraph, a line of verse, a speech), the hyphens at the ends of lines removed, the notes in brackets, and
what the keyers could not read as the TCP writes it, • a letter, 〈◊〉 a word, 〈…〉 more. The works whose text answers
`query` are kept, numbered, each with its number of `words`, its `hits` (the times its text has the words of
`query`), the address of its text on `github`, and its `text`; with words in `query`, in order of relevance, they
are sorted by their hits.
"""
function tcp_texts(works, query::TextQuery; at_most::Integer = 100, order::AbstractString = "oldest", folder::AbstractString)
	texts_folder = mkpath(joinpath(folder, "tcp", "texts"))
	texts = NamedTuple[]
	for r in candidates(works, order, at_most; date = r -> r.year)
		file = joinpath(texts_folder, r.tcp * ".xml")
		if !isfile(file)
			kept("https://raw.githubusercontent.com/textcreationpartnership/$(r.tcp)/master/$(r.tcp).xml", file; agent = RESEARCH_AGENT)
			sleep(0.2)  # a pause between requests
		end
		text = tcp_plain_text(read(file, String))
		query(text) || continue
		push!(texts, (tcp = r.tcp, year = r.year, date = r.date, author = r.author, title = r.title, subjects = r.terms, pages = r.pages,
			words = length(split(text)), hits = query_hits(query, text), github = "https://github.com/textcreationpartnership/$(r.tcp)", text = text))
	end
	return numbered_texts(identity.(texts), query, order)
end

const DTA_DOWNLOADS = "https://www.deutschestextarchiv.de/media/download"
const DTA_PARTS = Dict("dtak" => "core corpus", "dtae" => "further texts")

"""The field of a record in Dublin Core, `""` when it has none."""
dublin_core(xml::AbstractString, field::AbstractString) =
	(m = match(Regex("<dc:$field>(?<value>[^<]*)</dc:$field>"), xml); m === nothing ? "" : String(strip(m[:value])))

"""The records of the DTA's catalogue in Dublin Core, a file each, by the name of the work's folder at the DTA."""
function dta_catalogue(dir::AbstractString)
	catalogue = Dict{String, NamedTuple}()
	for file in readdir(joinpath(dir, only(readdir(dir))); join = true)
		xml = read(file, String)
		subject = split(dublin_core(xml, "subject"), ":"; limit = 2)
		rights = dublin_core(xml, "rights")
		catalogue[last(split(dublin_core(xml, "identifier"), "/"))] = (
			title = replace(dublin_core(xml, "title"), r"\s*\(vollständige digitalisierte Ausgabe\)" => ""), author = dublin_core(xml, "creator"),
			year = first_year(dublin_core(xml, "date")), category = String(strip(first(subject))), subcategory = length(subject) > 1 ? String(strip(subject[2])) : "",
			rights = isempty(rights) ? "CC BY-SA 4.0" : replace(rights, "Creative Commons Attribution-NonCommercial 3.0 Unported License" => "CC BY-NC 3.0"),
			part = occursin("Kernkorpus", dublin_core(xml, "publisher")) ? "core corpus" : "further texts", source = dublin_core(xml, "source"))
	end
	return catalogue
end

"""
	dta_download(from, to; spelling = "normalized", parts = "core", at_most_gb = 1, folder)

The texts of the Deutsches Textarchiv (DTA) of the centuries of the years `from` to `to`, in modern spelling
("normalized") or as printed ("original"), of its core corpus ("core") or of its further texts too ("all"),
downloaded once into `folder/dta`, a ZIP file for each part and century, and its catalogue in Dublin Core. It says
the size of each package and which are downloaded, and throws an error, downloading nothing, when those still to
download come to more than `at_most_gb` GB. Returns `(catalogue, files, spelling)`: the records of the catalogue
by the name of each work, and the text files of the centuries.
"""
function dta_download(from::Integer, to::Integer; spelling::AbstractString = "normalized", parts::AbstractString = "core",
		at_most_gb::Real = 1, folder::AbstractString)
	dta_folder = mkpath(joinpath(folder, "dta"))
	headers = [RESEARCH_AGENT]
	catalogue_folder = joinpath(dta_folder, "catalogue")
	if !isdir(catalogue_folder)
		zip = Downloads.download("$DTA_DOWNLOADS/dta_metadaten_oai_dc_2026-02-12.zip", joinpath(dta_folder, "catalogue.zip"); headers)
		rm(catalogue_folder * ".part"; force = true, recursive = true)
		mv(unzipped(zip, catalogue_folder * ".part"), catalogue_folder)
		rm(zip)
	end
	centuries = [c for c in 1400:100:1900 if c <= to && c + 99 >= from]
	packages = [(part = p, century = c, url = "$DTA_DOWNLOADS/$p/2020-10-23/$spelling/$c-$(c + 99).zip",
		folder = joinpath(dta_folder, p, spelling, "$c-$(c + 99)")) for p in (parts == "core" ? ["dtak"] : ["dtak", "dtae"]) for c in centuries]
	size_of(url) = (r = Downloads.request(url; method = "HEAD", headers, throw = false); r isa Downloads.Response && r.status == 200 ?
		parse(Int, Dict(lowercase(k) => v for (k, v) in r.headers)["content-length"]) : 0)
	sizes = Dict(p.url => size_of(p.url) for p in packages)
	done(p) = isfile(joinpath(p.folder, ".complete"))
	for p in packages
		println(rpad(DTA_PARTS[p.part], 15), "$(p.century)–$(p.century + 99)  ", sizes[p.url] == 0 ? "no texts" : lpad(size_text(sizes[p.url]), 9),
			done(p) ? "  downloaded" : "")
	end
	missing_bytes = sum((sizes[p.url] for p in packages if !done(p)); init = 0)
	missing_bytes > at_most_gb * 1e9 && error("The texts still to download come to ", size_text(missing_bytes), ", more than the ", at_most_gb,
		" GB allowed: raise Download at Most, choose fewer years, or only the core corpus")
	for p in packages
		(done(p) || sizes[p.url] == 0) && continue
		println("Downloading the ", DTA_PARTS[p.part], " of ", p.century, "–", p.century + 99, ", ", size_text(sizes[p.url]))
		zip = Downloads.download(p.url, joinpath(dta_folder, "package.zip"); headers)
		unzipped(zip, dirname(p.folder))
		rm(zip)
		touch(joinpath(p.folder, ".complete"))
	end
	files = [joinpath(p.folder, f) for p in packages if isdir(p.folder) for f in readdir(p.folder) if endswith(f, ".txt")]
	return (catalogue = dta_catalogue(catalogue_folder), files = files, spelling = spelling)
end

"""
	dta_works(texts, query, from, to; category = "")

The works of `texts` (those of [`dta_download`](@ref)) printed from `from` to `to`, of the `category` of the DTA when
it is given (Belletristik, Gebrauchsliteratur, Wissenschaft...), whose text answers `query`, a
[`text_query`](@ref): each with its `name` at the DTA, the fields of its record (title, author, year, category,
subcategory, rights, part, source), its number of `words`, its `hits` (the times its text has the words), its
text `file` and its address at the DTA, `dta`.
"""
function dta_works(texts, query::TextQuery, from::Integer, to::Integer; category::AbstractString = "")
	found = NamedTuple[]
	for file in texts.files
		name = replace(basename(file), ".txt" => "")
		record = get(texts.catalogue, name, (title = name, author = "", year = 0, category = "", subcategory = "", rights = "CC BY-SA 4.0", part = "", source = ""))
		(from <= record.year <= to && (isempty(category) || lowercase(record.category) == lowercase(category))) || continue
		text = read(file, String)
		query(text) || continue
		push!(found, merge((name = name,), record, (words = length(split(text)), hits = query_hits(query, text), file = file,
			dta = "https://www.deutschestextarchiv.de/$name")))
	end
	return identity.(found)
end

const GUTENBERG_MIRROR = "https://gutenberg.pglaf.org"

"""
The years of the life of a book's first author, as the catalogue of Project Gutenberg gives them after the name:
1775-1817, 1564?-1616, -0428?-0348?; `missing` when it gives none.
"""
function gutenberg_life(authors::AbstractString)
	m = match(r"(?<born>-?\d{1,4})\??\s*-\s*(?<died>-?\d{1,4})\??", first(split(authors, ";")))
	return m === nothing ? (born = missing, died = missing) : (born = parse(Int, m[:born]), died = parse(Int, m[:died]))
end

"""
	gutenberg_catalogue(; folder, update = false)

The catalogue of Project Gutenberg, pg_catalog.csv from its mirror at PGLAF, downloaded once into `folder/gutenberg`,
again when `update` is true: a row per book of text, with its `ebook` number, `type`, the date it was `issued`,
`title`, `language`, `authors`, `subjects`, `locc` (its class of the Library of Congress) and `bookshelves`, and the
years in which its first author was `born` and `died`, as the catalogue gives them after the name.
"""
function gutenberg_catalogue(; folder::AbstractString, update::Bool = false)
	file = joinpath(folder, "gutenberg", "pg_catalog.csv")
	if update || !isfile(file)
		mkpath(dirname(file))
		packed = Downloads.download("$GUTENBERG_MIRROR/cache/epub/feeds/pg_catalog.csv.gz", file * ".gz"; headers = [RESEARCH_AGENT])
		write(file, transcode(GzipDecompressor, read(packed)))
		rm(packed)
	end
	header = (:ebook, :type, :issued, :title, :language, :authors, :subjects, :locc, :bookshelves)
	books = [NamedTuple{header}(Tuple(replace.(r, r"\s*\n\s*" => " "))) for r in csv_rows(read(file, String))[2:end] if length(r) == length(header) && r[2] == "Text"]
	return [merge(b, gutenberg_life(b.authors)) for b in books]
end

"""
	gutenberg_books(query; language = "", from = nothing, to = nothing, folder)

The books of the [`gutenberg_catalogue`](@ref) whose records, their title, authors, subjects and bookshelves, answer
`query`, a [`text_query`](@ref): in the `language` given (its code, as en or de), and by authors who lived between
`from` and `to` (born before `to` and dead after `from`) when either is given; each with its `record_hits`, the
number of times its record has the words.
"""
function gutenberg_books(query::TextQuery; language::AbstractString = "", from::Union{Integer, Nothing} = nothing,
		to::Union{Integer, Nothing} = nothing, folder::AbstractString)
	record(r) = join((r.title, r.authors, r.subjects, r.bookshelves), " ; ")
	lived(r) = (from === nothing && to === nothing) || (!ismissing(r.born) && (to === nothing || r.born <= to) && (from === nothing || r.died >= from))
	in_language(r) = isempty(language) || language in strip.(split(r.language, ";"))
	return [merge(r, (record_hits = query_hits(query, record(r)),)) for r in gutenberg_catalogue(; folder) if in_language(r) && lived(r) && query(record(r))]
end

"""The text of a book of Project Gutenberg, without its header and its licence, a paragraph a line."""
function gutenberg_plain_text(file::AbstractString)
	s = replace(read(file, String), "﻿" => "", "\r\n" => "\n")
	start = findfirst(r"^\*\*\* ?START OF (THE|THIS) PROJECT GUTENBERG.*$"m, s)
	start === nothing || (s = s[nextind(s, last(start)):end])
	stop = findfirst(r"^\*\*\* ?END OF (THE|THIS) PROJECT GUTENBERG"m, s)
	stop === nothing || (s = s[1:prevind(s, first(stop))])
	return join(filter(!isempty, [strip(replace(p, r"\s+" => " ")) for p in split(s, r"\n\s*\n")]), "\n")
end

"""
	gutenberg_texts(books, query; at_most = 100, order = "oldest", folder)

The texts of the first `at_most` of `books` (those of [`gutenberg_books`](@ref)) in `order`: "oldest" or "newest",
by the year their first author was born, or "relevance", those whose records have the words most. Each is
downloaded once as plain text into `folder/gutenberg/texts` from the mirror of PGLAF, a second apart, and read
without its header and licence, a paragraph a line; a book with no plain text is said and left out. The books whose
text answers `query` are kept, numbered, each with its number of `words`, its `hits` (the times its text has the
words of `query`), its page at Project Gutenberg, `link`, and its `text`; with words in `query`, in order of
relevance, they are sorted by their hits.
"""
function gutenberg_texts(books, query::TextQuery; at_most::Integer = 100, order::AbstractString = "oldest", folder::AbstractString)
	texts_folder = mkpath(joinpath(folder, "gutenberg", "texts"))
	texts = NamedTuple[]
	for r in candidates(books, order, at_most; date = r -> ismissing(r.born) ? nothing : r.born)
		file = joinpath(texts_folder, "pg$(r.ebook).txt")
		if !isfile(file)
			sleep(1)  # a pause between requests
			try
				Downloads.download("$GUTENBERG_MIRROR/cache/epub/$(r.ebook)/pg$(r.ebook).txt", file; headers = [RESEARCH_AGENT])
			catch e
				e isa InterruptException && rethrow()
				println("No plain text of book ", r.ebook, ", ", r.title)
				continue
			end
		end
		text = gutenberg_plain_text(file)
		query(text) || continue
		push!(texts, (ebook = parse(Int, r.ebook), title = r.title, authors = r.authors, born = r.born, died = r.died, language = r.language,
			subjects = r.subjects, bookshelves = r.bookshelves, issued = r.issued, words = length(split(text)), hits = query_hits(query, text),
			link = "https://www.gutenberg.org/ebooks/$(r.ebook)", text = text))
	end
	return numbered_texts(identity.(texts), query, order)
end

"""
A request to a MediaWiki API (`site`, as en.wikisource.org or www.wikidata.org), with a pause of a second before it,
to keep within Wikimedia's limits; asked again up to three times when Wikimedia asks to wait, after the time it
gives, at most two minutes.
"""
function mediawiki(site::AbstractString, parameters)
	url = "https://$site/w/api.php?" * query_string([["format" => "json", "formatversion" => 2, "maxlag" => 5]; parameters])
	for attempt in 1:4
		sleep(1)
		answer = answered(url)
		waiting = answer.status in (429, 503) || occursin("maxlag", answer.body)
		if waiting && attempt < 4
			wait_for = something(tryparse(Int, get(answer.headers, "retry-after", "")), 30)
			println("Wikimedia asks to wait: asking again in ", wait_for, " seconds")
			sleep(min(wait_for, 120))
			continue
		end
		answer.status == 200 || error(site, " answered ", answer.status, ": ", first(answer.body, 200))
		parsed = JSON.parse(answer.body)
		haskey(parsed, "error") && error(site, ": ", parsed["error"]["info"])
		return parsed
	end
end

"""
	wikisource_search(language, words; category = "")

The pages of the Wikisource of `language` (its code, as en or fr) that Wikisource's search finds for `words`, in
the category `category` when it is given, the most relevant first, up to the 10,000 it lists: each with its `rank`,
`title`, the `work` it is part of (its title before the first /), its number of `words`, and the `snippet` of it
that the search shows. Returns `(total, pages)`: the number of pages found, and those listed.
"""
function wikisource_search(language::AbstractString, words::AbstractString; category::AbstractString = "")
	search = words * (isempty(category) ? "" : " incategory:\"$category\"")
	pages = NamedTuple[]
	total, offset = 0, 0
	while true
		answer = mediawiki("$language.wikisource.org", ["action" => "query", "list" => "search", "srsearch" => search, "srnamespace" => 0,
			"srlimit" => 500, "sroffset" => offset, "srprop" => "wordcount|snippet"])
		total = answer["query"]["searchinfo"]["totalhits"]
		for r in answer["query"]["search"]
			push!(pages, (rank = length(pages) + 1, title = r["title"], work = String(first(split(r["title"], "/"))), words = r["wordcount"],
				snippet = String(strip(replace(replace(r["snippet"], r"<[^>]+>" => ""), r"\s+" => " ")))))
		end
		haskey(answer, "continue") || break
		offset = answer["continue"]["sroffset"]
		offset >= 10000 && break
	end
	return (total = total, pages = identity.(pages))
end

"""The address of a page of the Wikisource of `language`."""
wikisource_link(language::AbstractString, title::AbstractString) =
	"https://$language.wikisource.org/wiki/" * replace(percent_encoded(replace(title, " " => "_")), "%2F" => "/")

"""
	wikisource_years(language, pages; from = nothing, to = nothing, order = "relevance")

The `pages` of the Wikisource of `language` (those of [`wikisource_search`](@ref)), each with the `year` of its work,
its date of publication or else of creation in the work's item of Wikidata (`missing` when it has none), the
address of that item, `wikidata`, and the page's address, `wikisource_page`; those whose year is from `from` to
`to` when either is given, in `order` ("relevance", as the search found them, "oldest" or "newest", those without
a year last), numbered.
"""
function wikisource_years(language::AbstractString, pages; from::Union{Integer, Nothing} = nothing, to::Union{Integer, Nothing} = nothing,
		order::AbstractString = "relevance")
	site = "$language.wikisource.org"
	items = Dict{String, String}()
	for batch in Iterators.partition(unique(p.work for p in pages), 50)
		answer = mediawiki(site, ["action" => "query", "prop" => "pageprops", "ppprop" => "wikibase_item", "redirects" => 1, "titles" => join(batch, "|")])
		renamed = Dict(r["to"] => r["from"] for r in vcat(get(answer["query"], "normalized", []), get(answer["query"], "redirects", [])))
		for p in answer["query"]["pages"]
			item = get(get(p, "pageprops", Dict()), "wikibase_item", nothing)
			item === nothing || (items[get(renamed, p["title"], p["title"])] = item)
		end
	end
	years = Dict{String, Int}()
	for batch in Iterators.partition(unique(values(items)), 50)
		answer = mediawiki("www.wikidata.org", ["action" => "wbgetentities", "ids" => join(batch, "|"), "props" => "claims"])
		for (id, entity) in answer["entities"]
			claims = get(entity, "claims", Dict())
			for property in ("P577", "P571")
				dates = [c["mainsnak"]["datavalue"]["value"]["time"] for c in get(claims, property, []) if haskey(c["mainsnak"], "datavalue")]
				isempty(dates) || (years[id] = minimum(parse(Int, match(r"^[+-]\d+", d).match) for d in dates); break)
			end
		end
	end
	year_of(work) = haskey(items, work) ? get(years, items[work], nothing) : nothing
	in_years(y) = (from === nothing && to === nothing) || (y !== nothing && (from === nothing || y >= from) && (to === nothing || y <= to))
	kept_pages = [merge(p, (year = something(year_of(p.work), missing), wikidata = haskey(items, p.work) ? "https://www.wikidata.org/wiki/" * items[p.work] : "",
		wikisource_page = wikisource_link(language, p.title))) for p in pages if in_years(year_of(p.work))]
	return ranked(kept_pages, order == "relevance" ? "" : order)
end

"""The HTML of a page without the elements whose opening tag matches `pattern` (its group `tag` their name), with what is inside them."""
function without_elements(html::AbstractString, pattern::Regex)
	out, at = IOBuffer(), 1
	while (m = match(pattern, html, at)) !== nothing
		print(out, html[at:prevind(html, m.offset)])
		depth, k = 1, m.offset + ncodeunits(m.match)
		while depth > 0
			t = match(Regex("<(/?)$(m[:tag])\\b[^>]*?(/?)>"), html, k)
			t === nothing && (k = ncodeunits(html) + 1; break)
			depth += t[1] == "/" ? -1 : t[2] == "/" ? 0 : 1
			k = t.offset + ncodeunits(t.match)
		end
		at = k
	end
	print(out, html[at:end])
	return String(take!(out))
end

"""
	wikisource_text(language, title; folder)

The text of the page `title` of the Wikisource of `language`, from Wikisource's parse of it, a paragraph a line,
without its header, notes and licence, and first the year of the edition and the author that its header gives;
kept in `folder/wikisource/<language>/pages` and read from there afterwards.
"""
function wikisource_text(language::AbstractString, title::AbstractString; folder::AbstractString)
	file = joinpath(mkpath(joinpath(folder, "wikisource", language, "pages")), first(replace(title, r"[/\\:*?\"<>|]" => "_"), 150) * ".txt")
	isfile(file) && return read(file, String)
	html = mediawiki("$language.wikisource.org", ["action" => "parse", "page" => title, "prop" => "text", "disablelimitreport" => 1,
		"disableeditsection" => 1])["parse"]["text"]
	header = join(("$k: $(strip(replace(m[:value], r"<[^>]+>" => "")))" for (k, id) in (("year of the edition", "ws-year"), ("author", "ws-author"))
		for m in (match(Regex("<span id=\"$id\">(?<value>.*?)</span>"), html),) if m !== nothing), "\n")
	s = replace(html, r"<style[^>]*>.*?</style>"s => "", r"<script[^>]*>.*?</script>"s => "")
	s = without_elements(s, r"<(?<tag>div|span|table|sup|ol|ul|p)\b[^>]*(?:class=\"[^\"]*\b(?:ws-noexport|noprint|wst-header|licenseContainer|reference|mw-references-wrap|references)\b[^\"]*\"|style=\"display:\s*none;?\")[^>]*>")
	s = replace(s, r"</p>|<br\s*/?>|</div>|</h\d>|</li>|</tr>|</dd>|</dt>" => "\n", r"<[^>]+>" => "")
	s = replace(s, r"&#x(?<h>[0-9A-Fa-f]+);" => e -> string(Char(parse(Int, e[4:end-1]; base = 16))), r"&#(?<d>\d+);" => e -> string(Char(parse(Int, e[3:end-1]))))
	s = replace(s, "&nbsp;" => " ", "&amp;" => "&", "&lt;" => "<", "&gt;" => ">", "&quot;" => "\"", r"\p{Cf}" => "")
	text = (isempty(header) ? "" : header * "\n\n") * join(filter(!isempty, [strip(replace(l, r"\s+" => " ")) for l in split(s, "\n")]), "\n")
	write(file, text)
	return text
end
