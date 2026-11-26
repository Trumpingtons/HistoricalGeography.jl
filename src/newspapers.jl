# The articles of newspaper archives: Delpher (the KB, the national library of the Netherlands), Papers Past (the
# National Library of New Zealand, through DigitalNZ), Digi (the National Library of Finland), Europeana Newspapers,
# and American Stories (the articles of Chronicling America, read from its scans by Dell and Harvard), each searched
# by words and dates, and read as text

"""The periods from `from` to `to`, each year or each decade over more than 60 years, as `(label, first day, last day)`."""
function date_periods(from::Dates.Date, to::Dates.Date)
	each = Dates.year(to) - Dates.year(from) > 60 ? 10 : 1
	return [(each == 1 ? string(y) : "$(y)s", max(from, Dates.Date(y)), min(to, Dates.Date(y + each - 1, 12, 31)))
		for y in fld(Dates.year(from), each) * each:each:Dates.year(to)]
end

const SRU_NAMESPACES = ["srw" => "http://www.loc.gov/zing/srw/", "diag" => "http://www.loc.gov/zing/srw/diagnostic/",
	"dc" => "http://purl.org/dc/elements/1.1/", "ddd" => "http://www.kb.nl/ddd"]

"""
	delpher_query(words, from, to; newspaper = "", kind = "all", region = "all")

The query of Delpher's newspaper articles in CQL, the language of the KB's search service: the `words` (a phrase in
quotes searched for with adj, the words next to one another), the dates `from` and `to` between which the articles
were published, and the `newspaper` (its title as Delpher gives it), the `kind` of article (artikel, advertentie,
familiebericht, illustratie met onderschrift) and the `region` where the newspaper was published (Landelijk,
Regionaal/lokaal, Nederlands-Indië / Indonesië, Suriname, Nederlandse Antillen, Buitenland) when they are given.
"""
function delpher_query(words::AbstractString, from::Dates.Date, to::Dates.Date; newspaper::AbstractString = "", kind::AbstractString = "all",
		region::AbstractString = "all")
	parts = ["(" * replace(words, r"\"(?<phrase>[^\"]+)\"" => s"cql.serverChoice adj \"\g<phrase>\"") * ")",
		"date within \"$(Dates.format(from, "dd-mm-yyyy")) $(Dates.format(to, "dd-mm-yyyy"))\""]
	isempty(newspaper) || push!(parts, "papertitle=\"$newspaper\"")
	kind == "all" || push!(parts, "type=\"$kind\"")
	region == "all" || push!(parts, "spatial=\"$region\"")
	return join(parts, " AND ")
end

"""A request to the KB's search service, for the articles from `start` on, `count` of them at most (up to 1,000), or 0 to count them."""
function delpher_sru(query::AbstractString; start::Integer = 1, count::Integer = 0)
	url = "https://jsru.kb.nl/sru/sru?version=1.2&operation=searchRetrieve&x-collection=DDD_artikel&recordSchema=ddd" *
		"&startRecord=$start&maximumRecords=$count&query=$(percent_encoded(query))"
	doc = EzXML.parsexml(fetched_text(url; headers = Pair{String, String}[], timeout = 120))
	message = findfirst("//diag:message", EzXML.root(doc), SRU_NAMESPACES)
	message === nothing || error("Delpher: ", EzXML.nodecontent(message), " in the query ", query)
	return doc
end

"""
	delpher_count(query)

The number of Delpher's articles that the query in CQL `query` (of [`delpher_query`](@ref)) finds.
"""
delpher_count(query::AbstractString) = parse(Int, EzXML.nodecontent(findfirst("//srw:numberOfRecords", EzXML.root(delpher_sru(query)), SRU_NAMESPACES)))

"""
	delpher_periods(words, from, to; newspaper, kind, region)

The numbers of Delpher's articles with `words` (searched as [`delpher_query`](@ref) writes them) of each year from
`from` to `to`, or of each decade over more than 60 years, a request each: pairs `"1839" => n` or `"1830s" => n`.
"""
delpher_periods(words::AbstractString, from::Dates.Date, to::Dates.Date; kw...) =
	[label => delpher_count(delpher_query(words, a, b; kw...)) for (label, a, b) in date_periods(from, to)]

"""
	delpher_articles(query; at_most = 1000, order = "relevance")

The first `at_most` articles of Delpher that the query in CQL `query` (of [`delpher_query`](@ref)) finds, in
`order` ("relevance", "oldest" or "newest"), up to 1,000 a request, half a second apart, as the KB asks of programs:
numbered, each with its `date`, `newspaper`, `title`, `kind`, `page`, the `place` and `region` of the newspaper, its
`id`, the address of its text in the KB's resolver, `text`, and that of its page on Delpher, `delpher`.
"""
function delpher_articles(query::AbstractString; at_most::Integer = 1000, order::AbstractString = "relevance")
	sorting = Dict("relevance" => "", "oldest" => " sortBy dc.date/sort.ascending", "newest" => " sortBy dc.date/sort.descending")[order]
	wanted = min(at_most, delpher_count(query))
	field(record, name) = (node = findfirst(name, record, SRU_NAMESPACES); node === nothing ? "" : String(strip(EzXML.nodecontent(node))))
	articles = NamedTuple[]
	for start in 1:1000:wanted
		doc = delpher_sru(query * sorting; start, count = min(1000, wanted - start + 1))
		for record in findall("//srw:recordData", EzXML.root(doc), SRU_NAMESPACES)
			id = field(record, "ddd:metadataKey")
			push!(articles, (number = length(articles) + 1, date = Dates.Date(first(field(record, "dc:date"), 10), Dates.dateformat"yyyy/mm/dd"),
				newspaper = field(record, "ddd:papertitle"), title = field(record, "dc:title"), kind = field(record, "dc:type"),
				page = something(tryparse(Int, field(record, "ddd:page")), 0), place = field(record, "ddd:spatialCreation"),
				region = field(record, "ddd:spatial"), id = id, text = field(record, "dc:identifier"),
				delpher = "https://www.delpher.nl/nl/kranten/view?identifier=$id&coll=ddd"))
		end
		sleep(0.5)  # a pause between requests, as the KB asks of programs
	end
	return identity.(articles)
end

"""
	delpher_text(article)

The text of an article of [`delpher_articles`](@ref), as the KB's OCR read it, from the KB's resolver, given up
after a minute without an answer: `(title, paragraphs)`.
"""
function delpher_text(article)
	doc = EzXML.parsexml(fetched_text(replace(article.text, r"^http:" => "https:"); headers = Pair{String, String}[]))
	title = findfirst("//title", EzXML.root(doc))
	return (title = title === nothing ? "" : String(strip(EzXML.nodecontent(title))),
		paragraphs = [String(strip(EzXML.nodecontent(p))) for p in findall("//p", EzXML.root(doc))])
end

"""A request to the DigitalNZ API for the newspaper articles of Papers Past, with the key in `DIGITALNZ_API_KEY` when one is set."""
function digitalnz(words::AbstractString, from::Integer, to::Integer, newspaper::AbstractString, parameters)
	filters = ["and[display_collection][]" => "Papers Past", "and[category][]" => "Newspapers", "text" => words]
	isempty(newspaper) || push!(filters, "and[collection][]" => newspaper)
	append!(filters, ["or[year][]" => string(y) for y in from:to])
	key = get(ENV, "DIGITALNZ_API_KEY", "")
	answer = JSON.parse(answered("https://api.digitalnz.org/v3/records.json?" * query_string([filters; parameters]);
		headers = isempty(key) ? Pair{String, String}[] : ["Authentication-Token" => key]).body)
	haskey(answer, "errors") && error("DigitalNZ: ", join(answer["errors"], "; "))
	return answer["search"]
end

"""
	paperspast_search(words, from, to; newspaper = "")

The articles of Papers Past with `words` published in the years `from` to `to`, in the `newspaper` (its title as
Papers Past gives it) when it is given, counted in one request to the DigitalNZ API (with the key in
`DIGITALNZ_API_KEY` when one is set): `(total, years)`, their number, and the number of each year, `year => n`.
"""
function paperspast_search(words::AbstractString, from::Integer, to::Integer; newspaper::AbstractString = "")
	counted = digitalnz(words, from, to, newspaper, ["per_page" => 0, "facets" => "year", "facets_per_page" => 350])
	return (total = counted["result_count"], years = Dict(parse(Int, string(y)) => n for (y, n) in counted["facets"]["year"]))
end

"""
	paperspast_search_address(words, from, to)

The address of Papers Past's own search for `words` in the years `from` to `to`, to open on
paperspast.natlib.govt.nz: it has the newspapers and years that DigitalNZ does not hold.
"""
paperspast_search_address(words::AbstractString, from::Integer, to::Integer) =
	"https://paperspast.natlib.govt.nz/newspapers?query=$(percent_encoded(words))&start_date=01-01-$from&end_date=31-12-$to"

"""
	paperspast_articles(words, from, to; newspaper = "", at_most = 1000, order = "relevance")

The first `at_most` articles of Papers Past with `words` published in the years `from` to `to` (in the `newspaper`
when it is given), in `order` ("relevance", "oldest" or "newest"), 100 a request to the DigitalNZ API, half a second
apart: numbered, each with its `date`, `newspaper`, `title`, `rights`, `id`, its page on `papers_past` and its `text`.
"""
function paperspast_articles(words::AbstractString, from::Integer, to::Integer; newspaper::AbstractString = "", at_most::Integer = 1000,
		order::AbstractString = "relevance")
	sorting = Dict("relevance" => Pair{String, String}[], "oldest" => ["sort" => "date", "direction" => "asc"],
		"newest" => ["sort" => "date", "direction" => "desc"])[order]
	articles = NamedTuple[]
	for page in 1:cld(at_most, 100)
		found = digitalnz(words, from, to, newspaper, [["per_page" => 100, "page" => page]; sorting])["results"]
		for r in found
			length(articles) < at_most || break
			papers = filter(!=("Papers Past"), string.(r["collection_title"]))
			push!(articles, (number = length(articles) + 1, date = Dates.Date(first(string(first(r["date"])), 10)), newspaper = isempty(papers) ? "" : first(papers),
				title = replace(string(r["title"]), r"\s*\([^()]*\)$" => ""), rights = string(something(r["rights"], "")),
				id = r["id"], papers_past = string(r["landing_url"]), text = string(something(r["fulltext"], ""))))
		end
		(isempty(found) || length(articles) >= at_most) && break
		sleep(0.5)  # a pause between requests, to keep within DigitalNZ's limit for requests without a key
	end
	return identity.(articles)
end

"""The JSON at `url`, given up after two minutes without an answer."""
json_at(url::AbstractString) = JSON.parse(fetched_text(url; headers = Pair{String, String}[], timeout = 120))

const DIGI_ORDER = Dict("relevance" => "RELEVANCE", "oldest" => "DATE", "newest" => "DATE_DESC")

"""The newspapers of Digi, with their ISSN, by which the search takes a newspaper, and their languages."""
digi_titles() = json_at("https://digi.kansalliskirjasto.fi/api/newspaper/titles")

"""The ISSNs of the newspapers searched: the `newspaper`, or those in `language`, or all (none named)."""
function digi_issns(titles, newspaper::AbstractString, language::AbstractString)
	if !isempty(newspaper)
		issns = [string(t["identification"]) for t in titles if lowercase(t["title"]) == lowercase(newspaper)]
		isempty(issns) && error("Digi has no newspaper called ", newspaper)
		return issns
	end
	return language == "all" ? String[] : [string(t["identification"]) for t in titles if language in t["languageCodes"]]
end

"""The parameters of a search of Digi, as digi.kansalliskirjasto.fi writes them."""
digi_parameters(words, from, to, issns, order) = join(vcat(["formats=NEWSPAPER", "query=$(percent_encoded(words))", "startDate=$from",
	"endDate=$to", "orderBy=$(DIGI_ORDER[order])"], ["title=$i" for i in issns]), "&")

"""
	digi_search_address(words, from, to; newspaper = "", language = "all")

The address of the search of Digi for `words` from the date `from` to `to` (in the `newspaper`, or the newspapers
in `language` when either is given), to open on digi.kansalliskirjasto.fi.
"""
digi_search_address(words::AbstractString, from::Dates.Date, to::Dates.Date; newspaper::AbstractString = "", language::AbstractString = "all") =
	"https://digi.kansalliskirjasto.fi/search?" * digi_parameters(words, from, to, digi_issns(digi_titles(), newspaper, language), "relevance")

"""A search of Digi, in the order asked, and the languages of its newspapers by ISSN."""
function digi_answer(words, from, to, newspaper, language, order)
	titles = digi_titles()
	answer = json_at("https://digi.kansalliskirjasto.fi/api/dam/binding-search?" * digi_parameters(words, from, to, digi_issns(titles, newspaper, language), order))
	answer["queryValidity"] == "VALID" || error("Digi does not take the query ", words, ": ", answer["queryValidity"])
	return answer, Dict(string(t["identification"]) => join(t["languageCodes"], ", ") for t in titles)
end

"""
	digi_search(words, from, to; newspaper = "", language = "all")

The pages of the newspapers of Digi with `words` from the date `from` to `to`, in the `newspaper` (its title as Digi
gives it) or in the newspapers in `language` (fin, swe, rus or ger) when either is given: `(total, years)`, their
number, and for each year, `year => (found, of)`, the pages with the words and all the pages of the year in the
newspapers searched.
"""
function digi_search(words::AbstractString, from::Dates.Date, to::Dates.Date; newspaper::AbstractString = "", language::AbstractString = "all")
	answer, _ = digi_answer(words, from, to, newspaper, language, "relevance")
	hits = Dict(parse(Int, string(y)) => n for (y, n) in something(answer["hitsByYear"], Dict()))
	pages = Dict(parse(Int, string(y)) => n for (y, n) in something(answer["totalHitsByYear"], Dict()))
	return (total = answer["totalResults"], years = Dict(y => (found = get(hits, y, 0), of = get(pages, y, 0)) for y in union(keys(hits), keys(pages))))
end

"""
	digi_pages(words, from, to; newspaper = "", language = "all", at_most = 1000, order = "relevance")

The first `at_most` pages of Digi with `words` (searched as [`digi_search`](@ref) does) in `order` ("relevance",
"oldest" or "newest"), 1,000 a request, half a second apart: numbered, each with its `date`, `newspaper`, `issue`,
`page`, `place`, `language`, the words `found` on it as they are written there, the `passage` that has them, whether
it is `restricted` (it may have rights that restrict its use), its address on `digi`, and that of its `text`.
"""
function digi_pages(words::AbstractString, from::Dates.Date, to::Dates.Date; newspaper::AbstractString = "", language::AbstractString = "all",
		at_most::Integer = 1000, order::AbstractString = "relevance")
	answer, languages = digi_answer(words, from, to, newspaper, language, order)
	wanted = min(at_most, answer["totalResults"])
	pages = NamedTuple[]
	while length(pages) < wanted && !isempty(answer["rows"])
		for r in answer["rows"]
			length(pages) < wanted || break
			date = something(tryparse(Dates.Date, first(string(r["date"]), 10)), Dates.Date(parse(Int, first(string(r["date"]), 4))))
			passage = isempty(r["textHighlights"]["text"]) ? "" : replace(string(first(r["textHighlights"]["text"])), r"</?em>" => "", r"\s+" => " ")
			push!(pages, (number = length(pages) + 1, date = date, newspaper = string(r["bindingTitle"]), issue = string(something(r["issue"], "")),
				page = r["pageNumber"], place = string(something(r["placeOfPublication"], "")), language = get(languages, string(r["publicationId"]), ""),
				found = join(unique(string.(r["terms"])), ", "), passage = passage, restricted = r["copyrightWarnings"] == true,
				digi = "$(r["baseUrl"])?page=$(r["pageNumber"])", text = "$(r["baseUrl"])/page-$(r["pageNumber"]).txt"))
		end
		length(pages) < wanted || break
		sleep(0.5)  # a pause between requests
		answer = json_at("https://digi.kansalliskirjasto.fi/api/dam/binding-search/" * answer["scrollId"])
	end
	return identity.(pages)
end

"""
	digi_text(page)

The text of a page of [`digi_pages`](@ref), as the National Library's OCR read it, given up after a minute without
an answer.
"""
digi_text(page) = fetched_text(page.text; headers = Pair{String, String}[])

"""The key of Europeana's API, in `EUROPEANA_API_KEY`, or else the demo key that Europeana gives for trying its API."""
europeana_key() = (key = get(ENV, "EUROPEANA_API_KEY", ""); isempty(key) ? "api2demo" : key)

"""The JSON answer of a request to Europeana, read also when it is an error, whose reason Europeana gives in it."""
function europeana_json(url::AbstractString)
	answer = JSON.parse(answered(url; headers = Pair{String, String}[]).body)
	haskey(answer, "error") && error("Europeana: ", answer["error"], ". ", get(answer, "message", ""))
	return answer
end

"""A request to Europeana's full-text search of its newspapers, for the issues between two dates."""
function europeana_search(words, a, b, newspaper, language, parameters)
	filters = ["theme" => "newspaper", "query" => words, "qf" => "proxy_dcterms_issued:[$a TO $b]"]
	isempty(newspaper) || push!(filters, "qf" => "title:\"$newspaper\"")
	language == "all" || push!(filters, "qf" => "LANGUAGE:$language")
	return europeana_json("https://api.europeana.eu/fulltext/search.json?wskey=$(europeana_key())&" * query_string([filters; parameters]))
end

"""
	europeana_count(words, from, to; newspaper = "", language = "all")

The number of issues of Europeana's newspapers with `words` published from the date `from` to `to`, in the
`newspaper` (its title as Europeana gives it) and the `language` (its code, as de or fr) when they are given, with
the key of Europeana's API in `EUROPEANA_API_KEY`, or else its demo key.
"""
europeana_count(words::AbstractString, from::Dates.Date, to::Dates.Date; newspaper::AbstractString = "", language::AbstractString = "all") =
	europeana_search(words, from, to, newspaper, language, ["rows" => 0])["totalResults"]

"""
	europeana_periods(words, from, to; newspaper = "", language = "all")

The [`europeana_count`](@ref) of each year from `from` to `to`, or of each decade over more than 60 years, a
request each, a fifth of a second apart: pairs `"1865" => n` or `"1860s" => n`.
"""
europeana_periods(words::AbstractString, from::Dates.Date, to::Dates.Date; kw...) =
	[(sleep(0.2); label => europeana_count(words, a, b; kw...)) for (label, a, b) in date_periods(from, to)]

"""
	europeana_search_address(words, from, to; language = "all")

The address of the search of Europeana's newspapers for `words` from the date `from` to `to` (in `language` when it
is given), to open on europeana.eu.
"""
europeana_search_address(words::AbstractString, from::Dates.Date, to::Dates.Date; language::AbstractString = "all") =
	"https://www.europeana.eu/en/collections/topic/18-newspapers?api=fulltext&query=$(percent_encoded(words))" *
	"&qf=$(percent_encoded("proxy_dcterms_issued:[$from TO $to]"))" * (language == "all" ? "" : "&qf=$(percent_encoded("LANGUAGE:\"$language\""))")

"""The rights of an item of Europeana by the address of their statement, in short: CC BY-SA 4.0, Public Domain Mark, InC..."""
europeana_rights(url::AbstractString) = occursin("publicdomain/mark", url) ? "Public Domain Mark" : occursin("publicdomain/zero", url) ? "CC0" :
	occursin("creativecommons.org/licenses/", url) ? "CC " * uppercase(split(split(url, "licenses/")[2], '/')[1]) :
	occursin("rightsstatements.org", url) ? String(split(rstrip(url, '/'), '/')[end - 1]) : url

"""
	europeana_issues(words, from, to; newspaper = "", language = "all", at_most = 1000, order = "relevance")

The first `at_most` issues of Europeana's newspapers with `words` (searched as [`europeana_count`](@ref) does) in
`order` ("relevance", "oldest" or "newest"), 100 a request, each request going on from the cursor of the last, half
a second apart: numbered, each with its `date`, `newspaper`, `language`, the `library` that gave it, its `rights`, the
words `found` in it as they are written there, the `passage` that has them, its `id` and its page on `europeana`.
"""
function europeana_issues(words::AbstractString, from::Dates.Date, to::Dates.Date; newspaper::AbstractString = "", language::AbstractString = "all",
		at_most::Integer = 1000, order::AbstractString = "relevance")
	# (by date, with the record's id to break ties, as Europeana asks of a search that goes on from a cursor)
	sorting = Dict("relevance" => Pair{String, String}[], "oldest" => ["sort" => "proxy_dcterms_issued asc,europeana_id asc"],
		"newest" => ["sort" => "proxy_dcterms_issued desc,europeana_id asc"])[order]
	wanted = min(at_most, europeana_count(words, from, to; newspaper, language))
	issues = NamedTuple[]
	cursor = "*"
	while length(issues) < wanted
		answer = europeana_search(words, from, to, newspaper, language, [["rows" => min(100, wanted - length(issues)), "cursor" => cursor, "profile" => "minimal hits"]; sorting])
		hits = Dict(string(h["scope"]) => h["selectors"] for h in something(get(answer, "hits", nothing), []))
		items = something(get(answer, "items", nothing), [])
		for item in items
			id = string(item["id"])
			title = string(first(item["title"]))
			parts = match(r"^(?<newspaper>.*?)\s+-\s+(?<date>\d{4}-\d{2}-\d{2})$", title)
			selectors = get(hits, id, [])
			push!(issues, (number = length(issues) + 1, date = parts === nothing ? missing : Dates.Date(parts[:date]),
				newspaper = parts === nothing ? title : string(parts[:newspaper]), language = join(something(get(item, "language", nothing), []), ", "),
				library = join(something(get(item, "dataProvider", nothing), []), ", "), rights = europeana_rights(string(first(item["rights"]))),
				found = join(unique(string(s["exact"]) for s in selectors), ", "),
				passage = isempty(selectors) ? "" : replace(string(get(first(selectors), "prefix", ""), first(selectors)["exact"], get(first(selectors), "suffix", "")), r"\s+" => " "),
				id = id, europeana = "https://www.europeana.eu/item$id"))
		end
		cursor = string(something(get(answer, "nextCursor", nothing), ""))
		(isempty(cursor) || isempty(items)) && break
		sleep(0.5)  # a pause between requests
	end
	return identity.(issues)
end

"""
	europeana_pages(issue)

The texts of the pages of an issue of [`europeana_issues`](@ref), from its IIIF manifest, whose annotation of each
page names its full text, which Europeana's full-text service gives, a fifth of a second apart, each request given
up after a minute without an answer: a `(page, text)` each.
"""
function europeana_pages(issue)
	manifest = europeana_json("https://iiif.europeana.eu/presentation$(issue.id)/manifest?format=3")
	pages = NamedTuple[]
	for canvas in something(get(manifest, "items", nothing), [])
		label = string(first(first(values(canvas["label"]))))
		annotations = something(get(canvas, "annotations", nothing), [])
		isempty(annotations) && continue
		text_id = split(split(string(first(annotations)["id"]), "/annopage/")[2], '?')[1]
		resource = europeana_json("https://api.europeana.eu/fulltext$(issue.id)/$text_id")
		push!(pages, (page = label, text = string(something(get(resource, "value", nothing), ""))))
		sleep(0.2)  # a pause between requests
	end
	return identity.(pages)
end

const AMERICAN_STORIES = "https://huggingface.co/datasets/dell-research-harvard/AmericanStories"

"""
	americanstories_download(from, to; at_most_gb = 5, folder)

The archives of American Stories on Hugging Face of the years of the dates `from` to `to`, a gzipped tar archive a
year, downloaded once into `folder/americanstories`. It says the size of each and which are downloaded, and throws
an error, downloading nothing, when those still to download come to more than `at_most_gb` GB. Returns the years.
"""
function americanstories_download(from::Dates.Date, to::Dates.Date; at_most_gb::Real = 5, folder::AbstractString)
	archives = mkpath(joinpath(folder, "americanstories"))
	listing = json_at("https://huggingface.co/api/datasets/dell-research-harvard/AmericanStories/tree/main")
	sizes = Dict(parse(Int, m[:year]) => f["size"] for f in listing for m in (match(r"^faro_(?<year>\d{4})\.tar\.gz$", f["path"]),) if m !== nothing)
	years = filter(y -> haskey(sizes, y), Dates.year(from):Dates.year(to))
	isempty(years) && error("American Stories has no year from ", Dates.year(from), " to ", Dates.year(to), ": it has ", minimum(keys(sizes)), " to ", maximum(keys(sizes)))
	archive(y) = joinpath(archives, "faro_$y.tar.gz")
	missing_years = filter(y -> !isfile(archive(y)), years)
	foreach(y -> println(y, lpad(size_text(sizes[y]; gigabytes = 1e8), 10), isfile(archive(y)) ? ", downloaded" : ""), years)
	needed = sum(y -> sizes[y], missing_years; init = 0)
	needed > at_most_gb * 1e9 && error("The years not downloaded come to ", size_text(needed; gigabytes = 1e8), ", more than the ", at_most_gb,
		" GB allowed: raise Download at Most, or choose fewer years")
	for y in missing_years
		println("Downloading ", y, ", ", size_text(sizes[y]; gigabytes = 1e8))
		Downloads.download("$AMERICAN_STORIES/resolve/main/faro_$y.tar.gz", archive(y) * ".part")
		mv(archive(y) * ".part", archive(y); force = true)
	end
	println(length(years), " years in ", archives, isempty(missing_years) ? "" : ", $(length(missing_years)) of them downloaded now")
	return collect(years)
end

"""
Each JSON file of a tar archive in turn, read from the decompressed stream `io`, `f(name, data)`: a header of 512
bytes with its name and size, then its data, padded to 512 bytes.
"""
function each_json_file(f, io::IO)
	header = Vector{UInt8}(undef, 512)
	while !eof(io) && readbytes!(io, header, 512) == 512 && !all(iszero, header)
		name = String(rstrip(String(header[1:100]), '\0'))
		size = parse(Int, strip(String(header[125:136]), ['\0', ' ']); base = 8)
		data = read(io, size)
		padding = mod(-size, 512)
		padding > 0 && read(io, padding)
		header[157] in (UInt8('0'), 0x00) && endswith(name, ".json") && f(name, data)
	end
end

"""A field of a record of JSON, through its keys, or `default` where a key is missing or empty."""
function json_field(record, keys...; default = "")
	for k in keys
		record isa AbstractDict || return default
		record = get(record, k, nothing)
		record === nothing && return default
	end
	return record
end

unescaped_html(s::AbstractString) = replace(s, "&#39;" => "'", "&quot;" => "\"", "&amp;" => "&", "&lt;" => "<", "&gt;" => ">")

"""
	americanstories_articles(query, from, to; newspaper = "", state = "", keep = 50000, folder)

The articles of American Stories, in the archives downloaded by [`americanstories_download`](@ref), published from
the date `from` to `to` whose text answers `query` (a [`text_query`](@ref)), in the newspapers whose title and state
have `newspaper` and `state` (a part of them, capitals apart) when they are given; read from each archive as it is
decompressed, saying the number of each year. Beyond twice `keep` articles, only the `keep` with the most hits are
kept. Returns `(articles, years)`: the articles, each with its `date`, `newspaper`, `state`, `page`, `headline`,
`byline`, `hits` (the times its text has the words), `id`, the address of its page on `chronicling_america` and its
`text`; and the number of articles found in each year, `year => n`.
"""
function americanstories_articles(query::TextQuery, from::Dates.Date, to::Dates.Date; newspaper::AbstractString = "", state::AbstractString = "",
		keep::Integer = 50000, folder::AbstractString)
	newspaper, state = lowercase(newspaper), lowercase(state)
	found = NamedTuple[]
	by_year = Dict{Int, Int}()
	for y in Dates.year(from):Dates.year(to)
		archive = joinpath(folder, "americanstories", "faro_$y.tar.gz")
		isfile(archive) || continue
		open(GzipDecompressorStream, archive) do io
			each_json_file(io) do name, data
				parts = match(r"(?<date>\d{4}-\d{2}-\d{2})_p(?<page>\d+)_(?<lccn>[a-z]+\d+)", basename(name))
				parts === nothing && return
				date = tryparse(Dates.Date, parts[:date])
				(date === nothing || date < from || date > to) && return
				scan = JSON.parse(String(data))
				title = unescaped_html(string(json_field(scan, "lccn", "title")))
				paper_state = string(json_field(scan, "lccn", "state"))
				(isempty(newspaper) || occursin(newspaper, lowercase(title))) || return
				(isempty(state) || occursin(state, lowercase(paper_state))) || return
				for a in json_field(scan, "full articles"; default = [])
					text = string(json_field(a, "article"))
					query(text) || continue
					by_year[y] = get(by_year, y, 0) + 1
					edition = something(tryparse(Int, replace(string(json_field(scan, "scan", "edition"; default = "ed-1")), r"\D" => "")), 1)
					push!(found, (date = date, newspaper = rstrip(strip(first(split(title, " [volume]"))), '.'), state = paper_state,
						page = parse(Int, parts[:page]), headline = replace(strip(string(json_field(a, "headline"))), r"\s+" => " "),
						byline = String(strip(string(json_field(a, "byline")))), hits = query_hits(query, text),
						id = "$(json_field(scan, "id"))_$(json_field(a, "full_article_id"))",
						chronicling_america = "https://chroniclingamerica.loc.gov/lccn/$(parts[:lccn])/$(parts[:date])/ed-$edition/seq-$(parts[:page])/",
						text = text))
					# beyond twice the articles to keep, only the most relevant are kept
					length(found) > 2keep && (sort!(found; by = r -> -r.hits); resize!(found, keep))
				end
			end
		end
		println(y, ": ", get(by_year, y, 0), " articles")
	end
	length(found) > keep && (sort!(found; by = r -> -r.hits); resize!(found, keep))
	return (articles = identity.(found), years = by_year)
end
