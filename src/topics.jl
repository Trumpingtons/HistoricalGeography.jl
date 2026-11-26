# Topic maps: the events of a war or a conquest, from Wikidata or written by hand from its source; the battlefields of
# the National Park Service; the stages of a journey, written by hand; and the places a text names, from the texts of
# the Perseus Digital Library with the coordinates of the Getty Thesaurus of Geographic Names, or written by hand; each
# written as a table and as GeoJSON for a map.

const WIKIDATA_SPARQL = "https://query.wikidata.org/sparql"
const GETTY_SPARQL = "https://vocab.getty.edu/sparql"
# The commit of PerseusDL/canonical-greekLit the texts are read from, so that a text and its passages stay the same
const PERSEUS_COMMIT = "dacb04909e43dc47738828d33cc3d2b0635bc54c"

"""Percent-encodes a text for a query string: letters, digits and `-_.~` stay, every other byte becomes `%XX`."""
query_escape(text::AbstractString) = join(c in ('-', '_', '.', '~') || ('0' <= c <= '9') || ('A' <= c <= 'Z') || ('a' <= c <= 'z') ?
	string(c) : join("%" * uppercase(string(b; base = 16, pad = 2)) for b in codeunits(string(c))) for c in text)

"""Downloads `url` into `path` unless it is there already (or `refresh`), through a `.part` file, and returns `path`."""
function download_once(url, path; refresh::Bool = false, headers = Pair{String, String}[])
	(refresh || !isfile(path)) || return path
	mkpath(dirname(path))
	Downloads.download(url, path * ".part"; headers = [AGENT; headers])
	mv(path * ".part", path; force = true)
	return path
end

"""
Runs a SPARQL query at `endpoint`, sent as a form (a long query does not fit in an address), and keeps its JSON results
beside `path`, in a file named after the query, read once unless `refresh`.
"""
function sparql(endpoint, query, path; refresh::Bool = false, timeout::Real = 120)
	# the file is named after the query too, so that a query changed by a new version is asked again
	path = string(splitext(path)[1], "-", string(hash(query); base = 16), ".json")
	(refresh || !isfile(path)) || return JSON.parsefile(path)
	mkpath(dirname(path))
	# a busy service drops a query now and then: three tries, 10 and 30 seconds apart
	for (attempt, wait) in enumerate((10, 30, 0))
		try
			open(path * ".part", "w") do io
				response = Downloads.request(endpoint; method = "POST", input = IOBuffer("query=" * query_escape(query)), output = io, timeout,
					headers = [AGENT, "Accept" => "application/sparql-results+json", "Content-Type" => "application/x-www-form-urlencoded"])
				response.status == 200 || error("$(endpoint) answered the query with HTTP $(response.status)")
			end
			# an error page in place of the results is not kept
			results = JSON.parsefile(path * ".part")
			mv(path * ".part", path; force = true)
			return results
		catch e
			interrupted(e) && rethrow()
			rm(path * ".part"; force = true)
			attempt == 3 && rethrow()
			sleep(wait)
		end
	end
end

"""The value of a variable of a SPARQL result, or `nothing`."""
binding(row, name) = haskey(row, name) ? row[name]["value"] : nothing

"""
The year of a date of Wikidata's SPARQL service, negative before the Common Era. The service writes dates as XSD 1.1,
in which year 0 is 1 BCE, so 490 BCE comes as -0489: one is taken off years before 1.
"""
function wikidata_year(date::AbstractString)
	m = match(r"^(?<year>-?\d+)-", date)
	m === nothing && return nothing
	year = parse(Int, m[:year])
	return year <= 0 ? year - 1 : year
end

"""The longitude and latitude of a `Point(lon lat)` of Wikidata, or `nothing`."""
function wikidata_point(point)
	point === nothing && return nothing
	m = match(r"^Point\((?<lon>[-0-9.eE]+) (?<lat>[-0-9.eE]+)\)$", point)
	m === nothing && return nothing
	return (parse(Float64, m[:lon]), parse(Float64, m[:lat]))
end

"""The box (west, south, east, north) around points, with a margin of a tenth of its size and of at least `least` degrees."""
function points_box(points; least = 1.0)
	lons, lats = first.(points), last.(points)
	pad(a, b) = max((b - a) / 10, least)
	return (max(minimum(lons) - pad(extrema(lons)...), -180.0), max(minimum(lats) - pad(extrema(lats)...), -85.0),
		min(maximum(lons) + pad(extrema(lons)...), 180.0), min(maximum(lats) + pad(extrema(lats)...), 85.0))
end

"""Writes `features` as a GeoJSON file at `path` and as the table `table` of `con`, and returns `path`."""
function write_features(con, features, path, table, columns)
	# JSON.json of a value, a text, in JSON 0.21 as in 1: JSON.json(io, value) writes to io only in 1
	write(path, JSON.json(Dict("type" => "FeatureCollection", "features" => features)))
	DBInterface.execute(con, """CREATE OR REPLACE TABLE "$(table)" AS SELECT $(columns), geom FROM ST_Read('$(quoted(path))')""")
	return path
end

"""The file of corrections to the Wikidata items that `war_events` reads, written by hand."""
const WIKIDATA_CORRECTIONS = joinpath(dirname(@__DIR__), "data", "wikidata-corrections.toml")

"""
The corrections to Wikidata items, by item id, each checked: a `note` that says what Wikidata gives wrong and the
source of the correction, and only `name`, `kind`, `starts`, `ends` and `wikipedia` corrected.
"""
function wikidata_corrections()
	corrections = TOML.parsefile(WIKIDATA_CORRECTIONS)
	for (id, fix) in corrections
		ok = occursin(r"^Q[1-9][0-9]*$", id) && !isempty(get(fix, "note", "")) &&
			issubset(keys(fix), ("note", "name", "kind", "starts", "ends", "wikipedia")) &&
			all(field -> get(fix, field, 0) isa Integer, ("starts", "ends")) && get(fix, "starts", 0) <= get(fix, "ends", get(fix, "starts", 0))
		ok || error("the correction of $(id) needs a Wikidata id, a note, and only name, kind, starts <= ends and wikipedia")
	end
	return corrections
end

"""
The kind of an event of a war, `name`, from the kinds Wikidata gives it (`kinds`, joined by `|`), leaving out `war`,
since an item that is part of a war and also a war is one of its battles or campaigns: the kind the name starts with
(a siege for the Siege of Massilia, which Wikidata gives as a siege and a naval battle), else the first in
alphabetical order; `war` when it is the only one, and an empty text when there are none.
"""
function event_kind(kinds, name = "")
	names = sort!(unique!(filter!(!isempty, split(something(kinds, ""), "|"))))
	others = filter(!=("war"), names)
	isempty(others) && return isempty(names) ? "" : first(names)
	named = findfirst(kind -> startswith(lowercase(something(name, "")), lowercase(kind)), others)
	return others[something(named, 1)]
end

"""
	war_events(con, war; folder, table = "events", refresh = false)

Writes the table `table` of the events of the war `war` that Wikidata gives with a place and a date: the battles,
sieges, treaties and other items that are part of the war (P361, at any depth) or name it as their conflict (P607),
within the war's own years (P580 to P582, a year either side) when Wikidata gives them.
`war` is the Wikidata id of the war, such as `"Q76026"` (the Greco-Persian Wars) or `"Q12551"` (the Hundred Years'
War), or a vector of ids, for a war with a part that Wikidata does not give as one, such as
`["Q1238338", "Q9377266"]` (Caesar's Civil War and the Alexandrian War); their events are written together, within
the first and last of their years. An event without coordinates of its own takes those of its location (P276).

An event that Wikidata gives several kinds takes the one its name starts with, else the first in alphabetical order,
leaving out `war`. The dates, kind, name or Wikipedia article of an item that Wikidata gives wrong are corrected by
hand in the package's `data/wikidata-corrections.toml`, each with a note of its source.

The table has `name`, `kind` (such as battle or siege), `starts` and `ends` (years, negative before the Common Era),
`until` (the last year of any event, so that a map with a year slider keeps every event on it from its year),
`place`, `sides` (the participants, P710), `located` (`event` or `place`), `wikidata`, `wikipedia` and `geom`. It is
also written as GeoJSON in `folder`, whose path is returned with the number of events, their first and last year
and a box around them: `(; path, count, since, upto, box)`.

Wikidata's answer is kept in `folder` and read again unless `refresh`. Its items are CC0.
"""
function war_events(con, war::Union{AbstractString, AbstractVector{<:AbstractString}}; folder::AbstractString, table::AbstractString = "events", refresh::Bool = false)
	wars = war isa AbstractString ? [war] : collect(war)
	isempty(wars) && throw(ArgumentError("war is the Wikidata id of a war, or a vector of them, not an empty vector"))
	for id in wars
		occursin(r"^Q[1-9][0-9]*$", id) || throw(ArgumentError("war is the Wikidata id of a war, such as \"Q76026\", not \"$(id)\""))
	end
	parts = join(["{ ?e wdt:P361+ wd:$(id) } UNION { ?e wdt:P607 wd:$(id) }" for id in wars], " UNION ")
	query = """
	SELECT ?e (SAMPLE(?name) AS ?label) (GROUP_CONCAT(DISTINCT ?kindName; separator = "|") AS ?kinds) (MIN(?d0) AS ?from) (MAX(?d1) AS ?to)
		(SAMPLE(?own) AS ?ownPoint) (SAMPLE(?at) AS ?placePoint) (SAMPLE(?placeName) AS ?place) (SAMPLE(?article) AS ?wiki)
		(GROUP_CONCAT(DISTINCT ?sideName; separator = "; ") AS ?sides) WHERE {
	  $(parts)
	  # a date first: it leaves out the people, ships and memorials that name the war as their conflict
	  FILTER EXISTS { ?e wdt:P585|wdt:P580 [] }
	  FILTER NOT EXISTS { ?e wdt:P31 wd:Q5 }
	  OPTIONAL { ?e wdt:P625 ?own }
	  OPTIONAL { ?e wdt:P276 ?location . ?location wdt:P625 ?at .
	    OPTIONAL { ?location rdfs:label ?placeName FILTER(LANG(?placeName) = "en") } }
	  FILTER(BOUND(?own) || BOUND(?at))
	  OPTIONAL { ?e wdt:P585 ?point } OPTIONAL { ?e wdt:P580 ?start } OPTIONAL { ?e wdt:P582 ?end }
	  BIND(COALESCE(?point, ?start) AS ?d0) BIND(COALESCE(?end, ?point, ?start) AS ?d1)
	  FILTER(BOUND(?d0))
	  OPTIONAL { ?e rdfs:label ?name FILTER(LANG(?name) = "en") }
	  OPTIONAL { ?e wdt:P31 ?k . ?k rdfs:label ?kindName FILTER(LANG(?kindName) = "en") }
	  OPTIONAL { ?e wdt:P710 ?side . ?side rdfs:label ?sideName FILTER(LANG(?sideName) = "en") }
	  OPTIONAL { ?article schema:about ?e ; schema:isPartOf <https://en.wikipedia.org/> }
	} GROUP BY ?e"""
	mkpath(folder)
	stem = join(wars, "-")
	rows = sparql(WIKIDATA_SPARQL, query, joinpath(folder, "wikidata-$(stem).json"); refresh)["results"]["bindings"]
	# the wars' own years, within which their events must fall: items that name a war can be of other years
	values = join(("wd:$(id)" for id in wars), " ")
	dates = sparql(WIKIDATA_SPARQL, "SELECT ?from ?to WHERE { VALUES ?war { $(values) } OPTIONAL { ?war wdt:P580 ?from } OPTIONAL { ?war wdt:P582 ?to } }",
		joinpath(folder, "wikidata-$(stem)-years.json"); refresh)["results"]["bindings"]
	years_of(name) = [year for year in (wikidata_year(something(binding(row, name), "")) for row in dates) if year !== nothing]
	first_year, last_year = isempty(years_of("from")) ? nothing : minimum(years_of("from")), isempty(years_of("to")) ? nothing : maximum(years_of("to"))
	corrections = wikidata_corrections()
	events = []
	for row in rows
		own = wikidata_point(binding(row, "ownPoint"))
		at = own === nothing ? wikidata_point(binding(row, "placePoint")) : own
		id = last(split(binding(row, "e"), "/"))
		fix = get(corrections, id, Dict{String, Any}())
		starts = get(fix, "starts", wikidata_year(something(binding(row, "from"), "")))
		(at === nothing || starts === nothing) && continue
		(first_year !== nothing && starts < first_year - 1 || last_year !== nothing && starts > last_year + 1) && continue
		ends = get(fix, "ends", haskey(fix, "starts") ? starts : something(wikidata_year(something(binding(row, "to"), "")), starts))
		push!(events, (; id, name = get(fix, "name", something(binding(row, "label"), id)), kind = get(fix, "kind", event_kind(binding(row, "kinds"), binding(row, "label"))),
			starts, ends = max(ends, starts), point = at, located = own === nothing ? "place" : "event", place = something(binding(row, "place"), ""),
			sides = something(binding(row, "sides"), ""), wikipedia = get(fix, "wikipedia", something(binding(row, "wiki"), ""))))
	end
	isempty(events) && error("Wikidata gives no event of $(join(wars, ", ")) with a place and a date")
	sort!(events; by = event -> (event.starts, event.name))
	since, upto = minimum(event.starts for event in events), maximum(event.ends for event in events)
	features = [Dict("type" => "Feature", "geometry" => Dict("type" => "Point", "coordinates" => collect(event.point)),
		"properties" => Dict("name" => event.name, "kind" => event.kind, "starts" => event.starts, "ends" => event.ends, "until" => upto,
			"place" => event.place, "sides" => event.sides, "located" => event.located,
			"wikidata" => "https://www.wikidata.org/wiki/$(event.id)", "wikipedia" => event.wikipedia)) for event in events]
	path = write_features(con, features, joinpath(folder, "war-$(stem).geojson"), table,
		"name, kind, starts::INTEGER AS starts, ends::INTEGER AS ends, until::INTEGER AS until, place, sides, located, wikidata, wikipedia")
	return (; path, count = length(events), since, upto, box = points_box([event.point for event in events]))
end

"""The folder of the hand-written topic data: one TOML file per work, read from its passages."""
const TOPICS_FOLDER = joinpath(dirname(@__DIR__), "data", "topics")

"""
The hand-written data `name` (`data/topics/<name>.toml`), with each of its places checked: a Wikidata id, or for a
place with no item, a `source` (the address its point comes from), and a point `[lon, lat]` within the world.
"""
function topic_data(name::Symbol)
	path = joinpath(TOPICS_FOLDER, "$(name).toml")
	isfile(path) || throw(ArgumentError("there is no topic data :$(name); there are $(join(topic_names(), ", "))"))
	data = TOML.parsefile(path)
	for (id, place) in get(data, "places", Dict{String, Any}())
		point = get(place, "point", nothing)
		identified = haskey(place, "wikidata") ? occursin(r"^Q[1-9][0-9]*$", place["wikidata"]) :
			startswith(get(place, "source", ""), "https://")
		ok = identified && point isa AbstractVector && length(point) == 2 && -180 <= point[1] <= 180 && -90 <= point[2] <= 90
		ok || error("place $(id) of :$(name) needs a Wikidata id or a source, and a point [lon, lat]")
	end
	return data
end

"""The page of a place of the hand-written data: its Wikidata item, or the source of its point for a place with none."""
place_link(place) = haskey(place, "wikidata") ? "https://www.wikidata.org/wiki/$(place["wikidata"])" : place["source"]

"""The names of the hand-written topic data, as symbols."""
topic_names() = sort!([Symbol(first(splitext(file))) for file in readdir(TOPICS_FOLDER) if endswith(file, ".toml")])

"""
	war_events(con, war::Symbol; folder, table = "events")

Writes the table `table` of the events of a war written by hand from its source, such as `:qin` (the conquests of
Qin Shi Huang, from chapter 6 of Sima Qian's Records of the Grand Historian). The table has the columns of the
Wikidata wars, `name`, `kind`, `starts`, `ends`, `until`, `place`, `sides` and `wikidata` (the place's item), with
`reign` (the year of the ruler's reign the source dates it by), `passage` (the source's words) and `summary` (an
English summary of them, for a source in another language), and `geom`. A source that gives no years, such as
`:samudragupta` (the conquests of Samudragupta, from his Allahabad pillar inscription), has events without `starts`,
`ends` or `reign`, in the order of the source, and `since` and `upto` are `nothing`. It is also written as GeoJSON in
`folder`; returns `(; path, count, since, upto, box)`.
"""
function war_events(con, war::Symbol; folder::AbstractString, table::AbstractString = "events")
	data = topic_data(war)
	places = data["places"]
	events = data["events"]
	years = [event["year"] for event in events if haskey(event, "year")]
	# events dated by year in the order of their years; those of a source that gives no years in its own order
	length(years) == length(events) && (events = sort(events; by = event -> event["year"]))
	since, upto = isempty(years) ? (nothing, nothing) : extrema(years)
	features = map(events) do event
		place = places[event["place"]]
		year = get(event, "year", nothing)
		Dict("type" => "Feature", "geometry" => Dict("type" => "Point", "coordinates" => place["point"]),
			"properties" => Dict("name" => event["name"], "kind" => event["kind"], "starts" => year, "ends" => year,
				"until" => upto, "place" => place["name"], "sides" => event["sides"], "reign" => get(event, "reign", nothing),
				"passage" => event["passage"], "summary" => get(event, "summary", nothing),
				"wikidata" => place_link(place)))
	end
	mkpath(folder)
	path = write_features(con, features, joinpath(folder, "war-$(war).geojson"), table,
		"name, kind, starts::INTEGER AS starts, ends::INTEGER AS ends, until::INTEGER AS until, place, sides, reign::INTEGER AS reign, passage, summary::VARCHAR AS summary, wikidata")
	return (; path, count = length(events), since, upto, box = points_box([places[event["place"]]["point"] for event in events]))
end

# The battlefield boundaries of the American Battlefield Protection Program of the National Park Service
const BATTLEFIELDS_SERVICE = "https://services1.arcgis.com/fBc8EJBxQRMcHlei/arcgis/rest/services/Battlefield_Boundaries/FeatureServer/0"
const BATTLEFIELD_WARS = [:revolutionary => "REV", :war1812 => "1812", :civil => "CIVIL WAR"]

"""
	battlefields(con, war = :civil; folder, table = "battlefields", refresh = false)

Writes the table `table` of the battlefields of a war in the United States, as the American Battlefield Protection
Program of the National Park Service drew them: `:civil` (the Civil War), `:revolutionary` (the War of Independence)
or `:war1812` (the War of 1812). The table has `name` (the battle), `site` (the Program's id, such as `VA032`),
`state`, `boundary` (`study area`, the land the battle was fought over, or `core area`, where the fighting was) and
`geom`, a polygon, simplified to within about 50 metres. It is also written as GeoJSON in `folder`; returns
`(; path, count, box)`. The Program's answer is kept in `folder` and read again unless `refresh`.
"""
function battlefields(con, war::Symbol = :civil; folder::AbstractString, table::AbstractString = "battlefields", refresh::Bool = false)
	at = findfirst(==(war), first.(BATTLEFIELD_WARS))
	at === nothing && throw(ArgumentError("war is one of $(join(":" .* string.(first.(BATTLEFIELD_WARS)), ", ")), not :$(war)"))
	query = "where=" * query_escape("WAR = '$(last(BATTLEFIELD_WARS[at]))'") * "&outFields=SITE,STATE,NAME,BOUNDARY&outSR=4326&resultRecordCount=2000" *
		# the outlines simplified to within about 50 metres, which a map of a war does not show, and a twelfth of the size
		"&maxAllowableOffset=0.0005&geometryPrecision=5&f=geojson"
	answer = JSON.parsefile(download_once("$(BATTLEFIELDS_SERVICE)/query?$(query)", joinpath(folder, "abpp", "battlefields-$(war).json"); refresh))
	features = answer["features"]
	isempty(features) && error("the National Park Service gave no battlefields of :$(war)")
	# the Program writes names in capitals: SHEPHERDSTOWN, MCDOWELL
	pretty(name) = replace(titlecase(lowercase(strip(name))), r"\bMc(?<letter>[a-z])" => s -> "Mc" * uppercase(s[3:end]))
	points = Tuple{Float64, Float64}[]
	for feature in features
		properties = feature["properties"]
		feature["properties"] = Dict("name" => pretty(properties["NAME"]), "site" => properties["SITE"], "state" => properties["STATE"],
			"boundary" => lowercase(properties["BOUNDARY"]))
		for ring in Iterators.flatten(feature["geometry"]["type"] == "Polygon" ? [feature["geometry"]["coordinates"]] : feature["geometry"]["coordinates"])
			append!(points, (Float64(point[1]), Float64(point[2])) for point in ring)
		end
	end
	path = write_features(con, features, joinpath(folder, "battlefields-$(war).geojson"), table, "name, site, state, boundary")
	return (; path, count = length(features), box = points_box(points))
end

"""
The lines through `points` in order, `[lon, lat]` each, split where a step crosses the antimeridian (a step of more
than 180 degrees of longitude goes the short way round), so that a map draws it across the Pacific.
"""
function route_lines(points)
	lines = [Any[points[1]]]
	for (from, to) in zip(points, points[2:end])
		if abs(to[1] - from[1]) > 180
			edge = from[1] > 0 ? 180.0 : -180.0
			span = 360 - abs(to[1] - from[1])
			latitude = from[2] + (to[2] - from[2]) * (180 - abs(from[1])) / span
			push!(lines[end], [edge, latitude])
			push!(lines, Any[[-edge, latitude]])
		end
		push!(lines[end], to)
	end
	return lines
end

"""
	journey(con, name::Symbol; folder, table = "stages")

Writes the table `table` of the stages of a journey written by hand from its source, such as `:bly` (Nellie Bly's
journey around the world, from her book of 1890), and the table `<table>_route` of the route through them.

The stages have `stage` (their number, in the order of the journey), `name` (the place), `part` (the voyage or leg,
for a journey of several), `date` (as `yyyy-mm-dd`, when the source dates it), `day` (the day of the journey, from 1),
`year`, `until` (the last year of any stage, so that a map with a year slider keeps every stage on it from its year),
`cite` (where in the source), `passage` (the source's words), `summary` (an English summary of a passage in another
language), `note`, `identified` (for a place of legend, where an ancient author put it, in that author's words),
`wikidata` (the place's item), `painting` (a painting of the stage, its title, painter, year and collection, for a
stage that has one) and `image` (the address of its image at Wikimedia Commons, 640 pixels wide), and `geom`. The route is a line through each part, split where it
crosses the antimeridian; a journey whose source does not give the order of its stages, such as the voyages of Zheng He, has none
(`route` is `nothing`). They are also written as GeoJSON in `folder`; returns `(; path, route, count, since, upto, box)`.
"""
function journey(con, name::Symbol; folder::AbstractString, table::AbstractString = "stages")
	data = topic_data(name)
	places, stages = data["places"], data["stages"]
	isempty(stages) && error("the journey :$(name) has no stages")
	start = get(first(stages), "date", nothing)
	year_of(stage) = haskey(stage, "date") ? Dates.year(stage["date"]) : get(stage, "year", nothing)
	years = [year for year in map(year_of, stages) if year !== nothing]
	since, upto = isempty(years) ? (nothing, nothing) : extrema(years)
	features = map(enumerate(stages)) do (number, stage)
		place = places[stage["place"]]
		date = get(stage, "date", nothing)
		painting = get(stage, "painting", nothing)
		Dict("type" => "Feature", "geometry" => Dict("type" => "Point", "coordinates" => place["point"]),
			"properties" => Dict("stage" => number, "name" => place["name"], "part" => get(stage, "part", nothing),
				"date" => date === nothing ? nothing : string(date),
				"day" => date === nothing || start === nothing ? nothing : Dates.value(date - start) + 1,
				"year" => year_of(stage), "until" => upto, "cite" => stage["cite"], "passage" => stage["passage"],
				"summary" => get(stage, "summary", nothing), "note" => get(stage, "note", nothing),
				"identified" => get(place, "identified", nothing), "wikidata" => place_link(place),
				"painting" => painting === nothing ? nothing : painting_caption(painting),
				"image" => painting === nothing ? nothing : commons_image(painting["file"])))
	end
	mkpath(folder)
	path = write_features(con, features, joinpath(folder, "journey-$(name).geojson"), table,
		"stage::INTEGER AS stage, name, part::INTEGER AS part, date::VARCHAR AS date, day::INTEGER AS day, year::INTEGER AS year, " *
		"until::INTEGER AS until, cite, passage, summary::VARCHAR AS summary, note::VARCHAR AS note, identified::VARCHAR AS identified, wikidata, " *
		"painting::VARCHAR AS painting, image::VARCHAR AS image")
	points = [places[stage["place"]]["point"] for stage in stages]
	route = nothing
	if get(data, "route", true)
		# a line through each part, such as each journey of a traveller who made several
		parts = [Int[]]
		for (index, stage) in enumerate(stages)
			index > 1 && get(stage, "part", nothing) != get(stages[index - 1], "part", nothing) && push!(parts, Int[])
			push!(parts[end], index)
		end
		lines = reduce(vcat, [route_lines(points[part]) for part in parts if length(part) > 1]; init = Any[])
		line = Dict("type" => "Feature", "geometry" => Dict("type" => "MultiLineString", "coordinates" => lines),
			"properties" => Dict("name" => data["title"], "stages" => length(stages)))
		route = write_features(con, [line], joinpath(folder, "journey-$(name)-route.geojson"), "$(table)_route", "name, stages::INTEGER AS stages")
	end
	return (; path, route, count = length(stages), since, upto, box = points_box(points))
end

"""
The caption of a painting of a stage: its title, painter (when the stage's traveller is not the painter), year and
collection, as `Irises (1889), J. Paul Getty Museum`.
"""
function painting_caption(painting::AbstractDict)
	title = get(painting, "title", "")
	isempty(title) && error("a painting of a stage needs a title")
	painter = get(painting, "painter", nothing)
	year = get(painting, "year", nothing)
	collection = get(painting, "collection", nothing)
	return string(title, year === nothing ? "" : " ($(year))", painter === nothing ? "" : ", $(painter)",
		collection === nothing ? "" : ", $(collection)")
end

"""
The address of the image `file` of Wikimedia Commons, 640 pixels wide, by its page Special:FilePath, which
redirects to the image itself.
"""
function commons_image(file::AbstractString)
	isempty(file) && error("a painting of a stage needs the file of its image at Wikimedia Commons")
	name = replace(file, ' ' => '_')
	escaped = join(c in ('_', '-', '.', '~', '(', ')', '\'', ',') || (isascii(c) && isletter(c)) || isdigit(c) ? string(c) :
		join("%" * uppercase(string(byte; base = 16, pad = 2)) for byte in codeunits(string(c))) for c in name)
	return "https://commons.wikimedia.org/wiki/Special:FilePath/$(escaped)?width=640"
end

# id => (work, translator, file in PerseusDL/canonical-greekLit)
const PERSEUS_TEXTS = [
	:herodotus => ("Herodotus, Histories", "A. D. Godley", "data/tlg0016/tlg001/tlg0016.tlg001.perseus-eng2.xml"),
]

"""The value of the attribute `name` in the attributes of a tag, or `nothing`."""
function attribute(attributes, name)
	m = match(Regex("\\b$(name)=\"(?<value>[^\"]*)\""), attributes)
	return m === nothing ? nothing : m[:value]
end

"""
The places a Perseus TEI text names, in the order of the text, and the coordinates its editors give for the places of
Perseus' own gazetteer. A place is tagged with its id in the Getty Thesaurus of Geographic Names (`tgn,7016142`) or
in Perseus' gazetteer (`perseus,Athens`), as a `<placeName>` or a `<name type="place">`; the editors' regularised
name (`<reg>`) holds the coordinates, `Athens [23.7333,37.9667] (Perseus)`. Each mention is `(key, name, passage)`:
the key, the word of the text, and the passage as book.chapter, of the book and the chapter, card or line it is in.
The translator's notes are left out: they are not the author's words.
"""
function perseus_mentions(xml::AbstractString)
	xml = replace(xml, r"<note\b.*?</note>"s => "")
	coordinates = Dict{String, Tuple{Float64, Float64}}()
	for m in eachmatch(r"<name\b[^>]*key=\"(?<key>perseus,[^\"]*)\"[^>]*>\s*<reg>[^<\[]*\[(?<lon>-?[0-9.]+),(?<lat>-?[0-9.]+)\]"s, xml)
		haskey(coordinates, m[:key]) || (coordinates[m[:key]] = (parse(Float64, m[:lon]), parse(Float64, m[:lat])))
	end
	xml = replace(xml, r"<reg>.*?</reg>"s => "")
	# <name type="place" key="..."> around the word of the text, or around a <placeName> of the same place
	xml = replace(xml, r"<name\b[^>]*>.*?</name>"s => function (tag)
		m = match(r"^<name\b(?<attributes>[^>]*)>(?<content>.*)</name>$"s, tag)
		key = something(attribute(m[:attributes], "key"), "")
		(occursin(r"^(tgn|perseus),", key) && attribute(m[:attributes], "type") == "place") || return tag
		return "<placeName key=\"$(key)\">" * replace(m[:content], r"<[^>]*>" => "") * "</placeName>"
	end)
	book, part = "", ""
	mentions = NamedTuple{(:key, :name, :passage), Tuple{String, String, String}}[]
	for m in eachmatch(r"<div\b(?<div>[^>]*)>|<milestone\b(?<milestone>[^>]*)>|<placeName\b(?<place>[^>]*)>(?<name>.*?)</placeName>"s, xml)
		if m[:div] !== nothing
			subtype = lowercase(something(attribute(m[:div], "subtype"), ""))
			n = something(attribute(m[:div], "n"), "")
			subtype == "book" && ((book, part) = (n, ""))
			subtype in ("chapter", "card") && (part = n)
		elseif m[:milestone] !== nothing
			attribute(m[:milestone], "unit") == "line" && (part = something(attribute(m[:milestone], "n"), part))
		else
			key = something(attribute(m[:place], "key"), "")
			occursin(r"^(tgn,[0-9]+|perseus,.+)$", key) || continue
			name = strip(replace(m[:name], r"<[^>]*>" => "", r"\s+" => " "))
			isempty(name) && continue
			push!(mentions, (key = String(key), name = String(name), passage = isempty(part) ? book : "$(book).$(part)"))
		end
	end
	return mentions, coordinates
end

"""
	text_places(con, work; folder, table = "places", refresh = false)

Writes the table `table` of the places that a text names, each with the number of times it is named and the passages
that name it. `work` is `:herodotus`: the Histories in A. D. Godley's translation, read from the Perseus Digital
Library (PerseusDL/canonical-greekLit, CC BY-SA 4.0), whose editors tagged each place with its id in the Getty
Thesaurus of Geographic Names (TGN) or in Perseus' own gazetteer. A place of TGN has TGN's coordinates (Open Data
Commons Attribution License), a place of Perseus' gazetteer those its editors give in the text. `work` can also be a
text whose places are written by hand from it: `:genji` (The Tale of Genji, in the text of Shibuya Eiichi on
Wikisource, CC BY-SA 3.0), `:nights` (The Arabian Nights, in Richard F. Burton's translation), `:periplus` (The Periplus
of the Erythraean Sea, in Wilfred H. Schoff's translation), `:meghaduta` (Kalidasa's Cloud-Messenger, in Arthur W.
Ryder's translation) or `:decameron` (Boccaccio's Decameron, in John Payne's translation); each place then has
the coordinates of its Wikidata item and `key` is that item (for a place with no item, `key` is missing and `source`
is the address its coordinates come from), with no `link`, and the table also has `order` (the order in which the
text first names it), `passage`, the words of each passage joined by ` / `, `summary` (for a text whose passages
have one), `day` and `teller` (for a text of stories told on days, such as the Decameron, the day, with its theme,
and the teller of the stories that name the place, or `Several days` and `Several tellers`), `painting` and `image`
(a painting of a story set there, and the address of its image at Wikimedia Commons) and `note` (what is uncertain
about where the place is, such as an identification that has been questioned). A column that a text has nothing
for is empty in all its rows.

The table has `name` (the word the text uses most for it), `key` (`tgn,...` or `perseus,...`), `mentions`, `first`
(the first passage, book.chapter), `passages`, `link` (its page at Getty, for a place of TGN) and `geom`. It is also
written as GeoJSON in `folder`, whose path is returned with the number of places and of the mentions of those
located, the names of the places without coordinates, and a box around the places: `(; path, count, mentions,
unlocated, box)`.

The text and TGN's answer are kept in `folder` and read again unless `refresh`.
"""
function text_places(con, work::Symbol; folder::AbstractString, table::AbstractString = "places", refresh::Bool = false)
	at = findfirst(==(work), first.(PERSEUS_TEXTS))
	at === nothing && return written_places(con, work; folder, table)
	file = last(last(PERSEUS_TEXTS[at]))
	mkpath(folder)
	xml = read(download_once("https://raw.githubusercontent.com/PerseusDL/canonical-greekLit/$(PERSEUS_COMMIT)/$(file)",
		joinpath(folder, "perseus", basename(file)); refresh), String)
	mentions, located = perseus_mentions(xml)
	isempty(mentions) && error("the text names no place with an identification")
	keys = unique(mention.key for mention in mentions)
	tgn = [last(split(key, ",")) for key in keys if startswith(key, "tgn,")]
	query = """
	PREFIX tgn: <http://vocab.getty.edu/tgn/>
	PREFIX foaf: <http://xmlns.com/foaf/0.1/>
	PREFIX wgs: <http://www.w3.org/2003/01/geo/wgs84_pos#>
	SELECT ?p ?lat ?lon WHERE { VALUES ?p { $(join("tgn:" .* tgn, " ")) } ?p foaf:focus ?f . ?f wgs:lat ?lat ; wgs:long ?lon . }"""
	for row in sparql(GETTY_SPARQL, query, joinpath(folder, "getty-$(work).json"); refresh)["results"]["bindings"]
		located["tgn," * last(split(binding(row, "p"), "/"))] = (parse(Float64, binding(row, "lon")), parse(Float64, binding(row, "lat")))
	end
	features = Dict{String, Any}[]
	unlocated = String[]
	for key in keys
		named = [mention for mention in mentions if mention.key == key]
		spellings = [mention.name for mention in named]
		name = argmax(spelling -> count(==(spelling), spellings), unique(spellings))
		if !haskey(located, key)
			push!(unlocated, name)
			continue
		end
		passages = unique(mention.passage for mention in named)
		link = startswith(key, "tgn,") ? "http://vocab.getty.edu/page/tgn/" * last(split(key, ",")) : ""
		push!(features, Dict("type" => "Feature", "geometry" => Dict("type" => "Point", "coordinates" => collect(located[key])),
			"properties" => Dict("name" => name, "key" => key, "mentions" => length(named), "first" => first(passages),
				"passages" => join(passages, "; "), "link" => link)))
	end
	path = write_features(con, features, joinpath(folder, "places-$(work).geojson"), table,
		"name, key, mentions::INTEGER AS mentions, first, passages, link")
	points = [Tuple(feature["geometry"]["coordinates"]) for feature in features]
	return (; path, count = length(features), mentions = count(mention -> haskey(located, mention.key), mentions), unlocated,
		box = points_box(points))
end

"""
The places of a text written by hand from it (`data/topics/<work>.toml`, its `[[mentions]]` in the order of the text),
for `text_places`: one row a place, with the columns of a Perseus text but `link`, `key` its Wikidata id (for a place
with no item, `key` is missing and `source` is the address its point comes from), and `order` (the order in which
the text first names it), `passage` (the text's words) and `summary` (an English summary of them, missing when no
mention has one), the words of each mention joined by ` / `, `day` and `teller` (those of its mentions, or `Several
days` and `Several tellers`), `painting` and `image` (those of the first of its mentions that has a painting) and
`note` (the notes of its mentions, joined by ` / `). A map's pop-up leaves out what a place has nothing in.
"""
function written_places(con, work::Symbol; folder::AbstractString, table::AbstractString)
	work in topic_names() || throw(ArgumentError("work is one of $(join(":" .* string.([first.(PERSEUS_TEXTS); topic_names()]), ", ")), not :$(work)"))
	data = topic_data(work)
	places, mentions = data["places"], get(data, "mentions", Any[])
	isempty(mentions) && error("the text :$(work) has no mentions of places")
	keys = unique(mention["place"] for mention in mentions)
	features = map(enumerate(keys)) do (order, key)
		place = places[key]
		named = [mention for mention in mentions if mention["place"] == key]
		cites = unique(mention["cite"] for mention in named)
		# the day or teller of all the mentions of the place, or several
		shared(field, several) = (values = unique(mention[field] for mention in named if haskey(mention, field));
			isempty(values) ? nothing : length(values) == 1 ? only(values) : several)
		summaries = any(mention -> haskey(mention, "summary"), named)
		painted = findfirst(mention -> haskey(mention, "painting"), named)
		painting = painted === nothing ? nothing : named[painted]["painting"]
		notes = [mention["note"] for mention in named if haskey(mention, "note")]
		Dict("type" => "Feature", "geometry" => Dict("type" => "Point", "coordinates" => place["point"]),
			"properties" => Dict("name" => place["name"], "key" => get(place, "wikidata", nothing), "mentions" => length(named), "first" => first(cites),
				"passages" => join(cites, "; "), "source" => get(place, "source", nothing), "order" => order,
				"passage" => join([mention["passage"] for mention in named], " / "),
				"summary" => summaries ? join([get(mention, "summary", "") for mention in named], " / ") : nothing,
				"day" => shared("day", "Several days"), "teller" => shared("teller", "Several tellers"),
				"painting" => painting === nothing ? nothing : painting_caption(painting),
				"image" => painting === nothing ? nothing : commons_image(painting["file"]),
				"note" => isempty(notes) ? nothing : join(notes, " / ")))
	end
	mkpath(folder)
	path = write_features(con, features, joinpath(folder, "places-$(work).geojson"), table,
		"name, key::VARCHAR AS key, mentions::INTEGER AS mentions, first, passages, source::VARCHAR AS source, \"order\"::INTEGER AS \"order\", " *
		"passage, summary::VARCHAR AS summary, day::VARCHAR AS day, teller::VARCHAR AS teller, painting::VARCHAR AS painting, " *
		"image::VARCHAR AS image, note::VARCHAR AS note")
	return (; path, count = length(features), mentions = length(mentions), unlocated = String[],
		box = points_box([places[key]["point"] for key in keys]))
end
