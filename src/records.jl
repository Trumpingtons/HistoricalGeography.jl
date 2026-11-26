# What the sources of paleography, papyrology and epigraphy share: counts of values, the folders of archives, the
# records of TEI and EpiDoc files, and the findspots of records on a map

"""
	tally(values; top = nothing)

The distinct `values` with the number of times each comes, as pairs `value => count`, the most frequent first and
those as frequent in their order; the first `top` of them when `top` is given.
"""
function tally(values; top::Union{Integer, Nothing} = nothing)
	counts = Dict{Any, Int}()
	for v in values
		counts[v] = get(counts, v, 0) + 1
	end
	pairs = sort!(sort!(collect(counts); by = first, lt = isless); by = last, rev = true)
	return top === nothing ? pairs : first(pairs, top)
end

"""
	tallied(values; top = nothing, ordered = false, separator = ", ")

The [`tally`](@ref) of `values` as text, `value (count)` after another, as `Latin (120), Greek (45)`; in the order of
the values, as centuries from the first, when `ordered` is true; apart by `separator`, as `"; "` for values with
commas in them.
"""
function tallied(values; top::Union{Integer, Nothing} = nothing, ordered::Bool = false, separator::AbstractString = ", ")
	pairs = tally(values; top)
	ordered && sort!(pairs; by = first, lt = isless)
	return join(("$(v) ($(n))" for (v, n) in pairs), separator)
end

"""
	linked(rows, column => address)

The rows with the values of `column` written as links to the web addresses of `address`, `[text](address)`, which
Pollis's tables show as `text` in blue, opening the address in Pollis's browser when clicked; the column `address`
is left out. A row without an address keeps its value as it is.
"""
function linked(rows, link::Pair{Symbol, Symbol})
	column, address = link
	return map(rows) do row
		url = getproperty(row, address)
		value = isempty(something(url, "")) ? getproperty(row, column) : "[$(getproperty(row, column))]($(url))"
		Base.structdiff(merge(row, NamedTuple{(column,)}((value,))), NamedTuple{(address,)})
	end
end

"""
	natural_order(text)

A key that sorts texts with numbers in them by their numbers, as shelfmarks are: MsMurF 2 before MsMurF 10.
"""
natural_order(text::AbstractString) = [all(isdigit, p) ? lpad(p, 12, '0') : lowercase(p) for p in (m.match for m in eachmatch(r"\d+|\D+", text))]

"""
	century(year)

The century of `year`, negative before the Common Era: 1 to 100 is the 1st century, -100 to -1 the -1st.
"""
century(year::Integer) = year > 0 ? (year - 1) ÷ 100 + 1 : -((-year - 1) ÷ 100 + 1)
century(::Missing) = missing

"""
	findspots_geojson(table; name = :findspot, fallback = nothing, count = :inscriptions, path = tempname() * ".geojson")

The places of the rows of `table` (any table with the columns `lon` and `lat`, in degrees), written as GeoJSON to
`path`, which is returned: a point for each place, with its `name` (the first not empty of the rows there, else of
their column `fallback`) and its number of rows as `count`. Rows without coordinates are left out.
"""
function findspots_geojson(table; name::Symbol = :findspot, fallback::Union{Symbol, Nothing} = nothing,
		count::Symbol = :inscriptions, path::AbstractString = tempname() * ".geojson")
	spots = Dict{Tuple{Float64, Float64}, Vector{String}}()
	order = Tuple{Float64, Float64}[]
	for r in Tables.rows(table)
		lon, lat = Tables.getcolumn(r, :lon), Tables.getcolumn(r, :lat)
		(ismissing(lon) || ismissing(lat)) && continue
		place = (Float64(lon), Float64(lat))
		haskey(spots, place) || (push!(order, place); spots[place] = String[])
		label = string(coalesce(Tables.getcolumn(r, name), ""))
		isempty(label) && fallback !== nothing && (label = string(coalesce(Tables.getcolumn(r, fallback), "")))
		push!(spots[place], label)
	end
	features = map(order) do place
		names = spots[place]
		i = findfirst(!isempty, names)
		Dict("type" => "Feature", "geometry" => Dict("type" => "Point", "coordinates" => collect(place)),
			"properties" => Dict(String(name) => i === nothing ? "" : names[i], String(count) => length(names)))
	end
	write(path, JSON.json(Dict("type" => "FeatureCollection", "features" => features)))
	return path
end

"""The folder `dir` with the entries of the gzipped tar archive `archive` whose paths start with `prefix`, extracted once."""
function extracted(archive::AbstractString, dir::AbstractString, prefix::AbstractString)
	isdir(dir) && return dir
	part = dir * ".part"
	rm(part; force = true, recursive = true)
	open(io -> Tar.extract(h -> startswith(h.path, prefix), GzipDecompressorStream(io), part), archive)
	return mv(part, dir)
end

"""The XML files under `dir`, in order, without those named in `skip`."""
xml_files(dir::AbstractString; skip = ()) =
	sort!([joinpath(root, name) for (root, _, names) in walkdir(dir) for name in names if endswith(name, ".xml") && !(name in skip)])

"""
The records `f(doc)` of the XML documents that `parse` reads from `items` (files by default), in order. A document
that is not valid XML is left out, and said so once; the parser's warnings, as about ids that are not XML names, are
not shown.
"""
function xml_records(f, items; parse = EzXML.readxml)
	records = with_logger(NullLogger()) do
		map(items) do item
			doc = try parse(item) catch; return nothing end
			return f(doc)
		end
	end
	unread = count(isnothing, records)
	unread > 0 && @info "$(unread) records could not be read as XML and are left out"
	return [r for r in records if r !== nothing]
end

const TEI = ["t" => "http://www.tei-c.org/ns/1.0"]

"""A field of a TEI or EpiDoc record, by its XPath, `""` when the record has none."""
function field(doc::EzXML.Document, path::AbstractString)
	node = findfirst(path, EzXML.root(doc), TEI)
	return node === nothing ? "" : strip(EzXML.nodecontent(node))
end

"""The first element of a TEI record that matches one of `paths`, in their order; `nothing` when none does."""
element(doc::EzXML.Document, paths::AbstractString...) =
	something((findfirst(p, EzXML.root(doc), TEI) for p in paths)..., Some(nothing))

"""A year from a date such as `-0249-01-28`, `missing` when there is none."""
year_of(date::AbstractString) = (m = match(r"^-?\d+", date); m === nothing ? missing : parse(Int, m.match))

"""The first and last years of a TEI record's date of origin: its `when`, else its `notBefore` and `notAfter`."""
origin_years(doc::EzXML.Document; date = "//t:origDate") =
	(year_of(field(doc, "($(date)/@when | $(date)/@notBefore)[1]")), year_of(field(doc, "($(date)/@when | $(date)/@notAfter)[1]")))

"""The language of a TEI division, by its `xml:lang`; `""` when it has none."""
language_of(div) = div === nothing || !haskey(div, "xml:lang") ? "" : div["xml:lang"]

"""
The text of an edition or translation of a TEI or EpiDoc record, as written, its abbreviations expanded: its heading,
the regularised spellings and the editors' corrections are left out, and a line break that does not split a word is
a space. `""` for `nothing`.
"""
function edition_text(div)
	div === nothing && return ""
	foreach(EzXML.unlink!, findall("t:head | .//t:reg | .//t:corr", div, TEI))
	foreach(lb -> EzXML.linkprev!(lb, EzXML.TextNode(" ")), findall(".//t:lb[not(@break='no')]", div, TEI))
	return join(split(EzXML.nodecontent(div)), " ")
end

"""A class of a taxonomy of the IIP or the USEP, without its `#`."""
class_of(value::AbstractString) = replace(value, "#" => "")

"""Coordinates given as `latitude,longitude`, as `(lon, lat)`; `(missing, missing)` when there are none."""
function latlon(text::AbstractString)
	m = match(r"^(?<lat>-?[\d.]+),\s*(?<lon>-?[\d.]+)$", strip(text))
	return m === nothing ? (missing, missing) : (parse(Float64, m[:lon]), parse(Float64, m[:lat]))
end

"""An entry of a zip archive, by the end of its name, leaving out the copies macOS adds in `__MACOSX`."""
entry_ending(reader, ending::AbstractString) = only(filter(n -> endswith(n, ending) && !startswith(n, "__MACOSX"), zip_names(reader)))

"""The file at `url`, downloaded again when the copy at `path` is older than `age` seconds."""
function fresh(url::AbstractString, path::AbstractString; age::Real = 86400)
	isfile(path) && time() - mtime(path) >= age && rm(path)
	return kept(url, path)
end

"""The JSON at `url`, read without keeping it."""
fetched(url::AbstractString) = JSON.parse(String(take!(Downloads.download(url, IOBuffer(); headers = [AGENT]))))
