# Old maps: the historical maps of France that IGN serves as tiles, the georeferenced maps of Allmaps, and famous
# maps of the world held by libraries, each with the address a web map draws it from.

"""The tile address of a layer of IGN's Géoplateforme, in the REST form of WMTS."""
ign_url(layer, matrixset, format) = "https://data.geopf.fr/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=$(layer)" *
	"&STYLE=normal&TILEMATRIXSET=$(matrixset)&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&FORMAT=$(format)"

# the source that IGN's terms ask every reuse of the Cassini maps to name, after the copy whose sheets were scanned
cassini_source(copy) = "Carte de France de Cassini reconstituée en une version numérique de haute qualité, 2025 / Archives nationales et IGN – " *
	"issue de la numérisation des planches originales: $(copy), Bibliothèque, E/III/200"

# id => (layer, tile matrix set, format, title, years, min zoom, max zoom)
const IGN_LAYERS = [
	:cassini => ("BNF-IGNF_GEOGRAPHICALGRIDSYSTEMS.CASSINI", "PM_6_14", "image/png", "Carte de Cassini, exemplaire de Marie-Antoinette", "1756-1815", 6, 14),
	:cassini_king => ("AN-IGNF_GEOGRAPHICALGRIDSYSTEMS.CASSINI", "PM_0_14", "image/jpeg", "Carte de Cassini, exemplaire du Roi", "1756-1815", 0, 14),
	:etatmajor => ("GEOGRAPHICALGRIDSYSTEMS.ETATMAJOR40", "PM_6_15", "image/jpeg", "Carte de l'état-major", "1820-1866", 6, 15),
	:etatmajor_paris => ("GEOGRAPHICALGRIDSYSTEMS.ETATMAJOR10", "PM_6_16", "image/jpeg", "Carte de l'état-major, environs de Paris", "1818-1824", 6, 16),
	:scan50_1950 => ("GEOGRAPHICALGRIDSYSTEMS.MAPS.SCAN50.1950", "PM_3_15", "image/jpeg", "Carte 1950 (SCAN 50)", "1950", 3, 15),
	:photos_1950 => ("ORTHOIMAGERY.ORTHOPHOTOS.1950-1965", "PM_0_18", "image/png", "Photographies aériennes 1950-1965", "1950-1965", 0, 18),
	:photos_1965 => ("ORTHOIMAGERY.ORTHOPHOTOS.1965-1980", "PM_3_18", "image/png", "Photographies aériennes 1965-1980", "1965-1980", 3, 18),
	:photos_1980 => ("ORTHOIMAGERY.ORTHOPHOTOS.1980-1995", "PM_3_18", "image/png", "Photographies aériennes 1980-1995", "1980-1995", 3, 18),
	:plan => ("GEOGRAPHICALGRIDSYSTEMS.PLANIGNV2", "PM_0_19", "image/png", "Plan IGN", "today", 0, 19),
	:photos => ("ORTHOIMAGERY.ORTHOPHOTOS", "PM_0_19", "image/jpeg", "Photographies aériennes", "today", 0, 19),
]

"""
	ign_layers()

The maps of France that [`ign_layer`](@ref) gives, as a table: `id`, `title`, `years`, `minzoom` and `maxzoom`.

- `:cassini` and `:cassini_king`: the map of Cassini, made between 1756 and 1815, in the copy said to have been made
  for Marie-Antoinette, scanned by the Bibliothèque nationale de France, and in the King's copy, scanned by the
  Archives nationales, each assembled and georeferenced by IGN;
- `:etatmajor`: the map of the état-major, 1820 to 1866, and `:etatmajor_paris`, the surroundings of Paris at
  1:10,000, 1818 to 1824;
- `:scan50_1950`: IGN's map of 1950 at 1:50,000;
- `:photos_1950`, `:photos_1965` and `:photos_1980`: aerial photographs of 1950-1965, 1965-1980 and 1980-1995;
- `:plan` and `:photos`: today's Plan IGN and aerial photographs.
"""
function ign_layers()
	ids = first.(IGN_LAYERS)
	specs = last.(IGN_LAYERS)
	return (id = ids, title = [s[4] for s in specs], years = [s[5] for s in specs], minzoom = [s[6] for s in specs], maxzoom = [s[7] for s in specs])
end

"""
	ign_layer(id)

A map of France that IGN's Géoplateforme serves as tiles, as `(id, title, years, url, minzoom, maxzoom,
attribution)`: `url` is the address of a tile with `{z}`, `{x}` and `{y}` in it, which a web map draws, and the map
has tiles from `minzoom` to `maxzoom`. `attribution` is the source a map that shows it names: for the maps of
Cassini, the source that IGN's terms of reuse ask for. `id` is one of [`ign_layers`](@ref).
"""
function ign_layer(id::Symbol)
	at = findfirst(==(id), first.(IGN_LAYERS))
	at === nothing && throw(ArgumentError("id is one of $(join(":" .* string.(first.(IGN_LAYERS)), ", ")), not :$(id)"))
	layer, matrixset, format, title, years, minzoom, maxzoom = last(IGN_LAYERS[at])
	attribution = id == :cassini ? cassini_source("BIBLIOTHEQUE NATIONALE DE FRANCE (BNF)") :
		id == :cassini_king ? cassini_source("Archives nationales (France)") : "IGN, Géoplateforme"
	return (; id, title, years, url = ign_url(layer, matrixset, format), minzoom, maxzoom, attribution)
end

const ALLMAPS_API = "https://api.allmaps.org/maps.geojson"

"""The text of a IIIF label in any language: a string, or the first value of a language map."""
function label_text(label)
	label === nothing && return ""
	label isa AbstractString && return strip(label)
	label isa AbstractVector && return isempty(label) ? "" : label_text(first(label))
	if label isa AbstractDict
		haskey(label, "@value") && return label_text(label["@value"])
		for values in Base.values(label)
			text = label_text(values)
			isempty(text) || return text
		end
	end
	return ""
end

"""The year of a IIIF manifest: the year of its `navDate`, or the first year in a metadata entry whose label names a date."""
function manifest_year(manifest)
	nav = get(manifest, "navDate", nothing)
	if nav isa AbstractString
		m = match(r"^(?<year>-?\d{1,4})-", nav)
		m === nothing || return parse(Int, m[:year])
	end
	for entry in get(manifest, "metadata", [])
		entry isa AbstractDict || continue
		lowercase(label_text(get(entry, "label", nothing))) in ("date", "datum", "year", "jaar", "datering", "date of publication",
			"publication date", "created", "date created", "date de publication", "erscheinungsjahr", "data") || continue
		m = match(r"\b(?<year>1[0-9]{3}|20[0-2][0-9])\b", label_text(get(entry, "value", nothing)))
		m === nothing || return parse(Int, m[:year])
	end
	return missing
end

"""
	allmaps(con; at = nothing, box = nothing, largest = nothing, smallest = nothing, limit = 100, folder, years = true, table = "maps")

Writes the table `table` of the maps that Allmaps holds georeferenced and that cover the place `at` (longitude,
latitude) or cross the box `box` (west, south, east, north), at most `limit` of them: `id`, `title`, `year`,
`library`, `km2` (the area the map covers), `tiles` (the address of a tile of the map, warped onto today's
coordinates by Allmaps' tile server, with `{z}`, `{x}` and `{y}` in it), `image` (the IIIF image),
`manifest` (the IIIF manifest), `editor` (the page of the map in Allmaps Editor) and `geom` (the outline of the map,
from its mask).

`largest` and `smallest` keep the maps whose area is at most and at least that many km², which leaves out maps of
whole countries or continents that also cover the place. The title is the label of the IIIF manifest the map
belongs to; a map in several manifests takes the label least shared with the other maps found. With
`years = true`, each manifest is read, once, into `folder`, for the year it gives, as its `navDate` or in a metadata
entry named as a date; a manifest that gives none, or that cannot be read in one try of 30 seconds, leaves `year`
missing.

Returns the number of maps.
"""
function allmaps(con; at = nothing, box = nothing, largest::Union{Real, Nothing} = nothing, smallest::Union{Real, Nothing} = nothing,
		limit::Integer = 100, folder::AbstractString, years::Bool = true, table::AbstractString = "maps")
	(at === nothing) == (box === nothing) && throw(ArgumentError("give either at (longitude, latitude) or box (west, south, east, north)"))
	at === nothing || length(at) == 2 || throw(ArgumentError("at is (longitude, latitude), in degrees"))
	box === nothing || length(box) == 4 || throw(ArgumentError("box is (west, south, east, north), in degrees"))
	# Allmaps takes latitude first: a point as lat,lon and a box as south,west,north,east
	where = at === nothing ? join(Float64.([box[2], box[1], box[4], box[3]]), ",") : join(Float64.([at[2], at[1]]), ",")
	query = ["intersects=$(where)", "limit=$(Int(limit))"]
	largest === nothing || push!(query, "maxArea=$(round(Int, largest * 1e6))")
	smallest === nothing || push!(query, "minArea=$(round(Int, smallest * 1e6))")
	mkpath(folder)
	found = Downloads.download(ALLMAPS_API * "?" * join(query, "&"), joinpath(folder, "allmaps-search.geojson"); headers = [AGENT])
	features = get(JSON.parsefile(found), "features", [])
	isempty(features) && error("Allmaps has no maps there$(largest === nothing ? "" : " of at most $(largest) km²")")
	# the manifests each map belongs to, with their labels
	manifests = map(features) do feature
		resource = get(feature["properties"], "resource", Dict())
		[(id = manifest["id"], label = label_text(get(manifest, "label", nothing)))
			for canvas in get(resource, "partOf", []) for manifest in get(canvas, "partOf", []) if get(manifest, "type", "") == "Manifest"]
	end
	shared = Dict{String, Int}()
	foreach(list -> foreach(m -> shared[m.label] = get(shared, m.label, 0) + 1, unique(list)), manifests)
	chosen = [isempty(list) ? nothing : list[argmin([(shared[m.label], -i) for (i, m) in enumerate(list)])] for list in manifests]
	found_years = fill!(Vector{Union{Int, Missing}}(undef, length(features)), missing)
	if years
		ids = unique(m.id for m in chosen if m !== nothing)
		mkpath(joinpath(folder, "allmaps-manifests"))
		# a manifest is read once, in one try: one that cannot be read, or is refused, leaves the year missing
		function read_year(id)
			# local: allmaps has a path of its own, which the tasks reading manifests must not share
			local cached = joinpath(folder, "allmaps-manifests", string(hash(id); base = 16) * ".json")
			try
				isfile(cached) && return manifest_year(JSON.parsefile(cached))
				Downloads.download(id, cached * ".part"; headers = [AGENT], timeout = 30)
				# a page in place of the manifest, such as a server's check for browsers, is not kept
				local year = manifest_year(JSON.parsefile(cached * ".part"))
				mv(cached * ".part", cached; force = true)
				return year
			catch e
				interrupted(e) && rethrow()
				@debug "The manifest gives no year" id exception = e
				rm(cached * ".part"; force = true)
				return missing
			end
		end
		year_of = Dict(zip(ids, asyncmap(read_year, ids; ntasks = 4)))
		found_years = [m === nothing ? missing : year_of[m.id] for m in chosen]
	end
	records = map(enumerate(features)) do (i, feature)
		p = feature["properties"]
		resource = get(p, "resource", Dict())
		provider = get(resource, "provider", [])
		short = last(split(p["id"], "/"))
		Dict("type" => "Feature", "geometry" => feature["geometry"], "properties" => Dict(
			"id" => short,
			"title" => chosen[i] === nothing ? "" : join(split(chosen[i].label), " "),
			"year" => coalesce(found_years[i], nothing),
			"library" => isempty(provider) ? "" : label_text(get(first(provider), "label", nothing)),
			"km2" => round(get(get(p, "_allmaps", Dict()), "area", 0) / 1e6; sigdigits = 4),
			"tiles" => "https://allmaps.xyz/maps/$(short)/{z}/{x}/{y}.png",
			"image" => get(resource, "id", ""),
			"manifest" => chosen[i] === nothing ? "" : chosen[i].id,
			"editor" => "https://editor.allmaps.org/#/images?url=" * get(resource, "id", "") * "/info.json"))
	end
	path = joinpath(folder, "allmaps-maps.geojson")
	write(path, JSON.json(Dict("type" => "FeatureCollection", "features" => records)))
	DBInterface.execute(con, """CREATE OR REPLACE TABLE "$(table)" AS SELECT id, coalesce(title, '') AS title, TRY_CAST(year AS INTEGER) AS year, coalesce(library, '') AS library,
		km2::DOUBLE AS km2, tiles, image, manifest, editor, geom FROM ST_Read('$(quoted(path))') ORDER BY km2""")
	return length(records)
end

# id => (title, year, author, library, image, page, terms, box of the region it shows (west, south, east, north), note)
const FAMOUS_MAPS = [
	:catalan => ("Catalan Atlas", 1375, "Abraham Cresques", "Bibliothèque nationale de France",
		"https://thumb.wikimedia.org/wikipedia/commons/thumb/3/35/1375_Atlas_Catalan_Abraham_Cresques.jpg/3840px-1375_Atlas_Catalan_Abraham_Cresques.jpg",
		"https://commons.wikimedia.org/wiki/File:1375_Atlas_Catalan_Abraham_Cresques.jpg", "Public domain (Wikimedia Commons)",
		(-20.0, 5.0, 125.0, 60.0), "the world map, from the Atlantic to China, in panels"),
	:framauro => ("Fra Mauro map", 1459, "Fra Mauro", "Biblioteca Nazionale Marciana, Venice",
		"https://thumb.wikimedia.org/wikipedia/commons/thumb/1/1b/FraMauroDetailedMap.jpg/3840px-FraMauroDetailedMap.jpg",
		"https://commons.wikimedia.org/wiki/File:FraMauroDetailedMap.jpg", "Public domain (Wikimedia Commons, PD-Art)",
		(-20.0, -35.0, 145.0, 70.0), "south is at the top"),
	:cantino => ("Cantino planisphere", 1502, "anonymous Portuguese cartographer", "Biblioteca Estense Universitaria, Modena",
		"https://thumb.wikimedia.org/wikipedia/commons/thumb/9/9c/Cantino_planisphere_%281502%29.jpg/3840px-Cantino_planisphere_%281502%29.jpg",
		"https://commons.wikimedia.org/wiki/File:Cantino_planisphere_(1502).jpg", "Public domain (Wikimedia Commons, PD-Scan)",
		(-100.0, -45.0, 135.0, 70.0), ""),
	:waldseemuller => ("Universalis Cosmographia", 1507, "Martin Waldseemüller", "Library of Congress",
		"https://tile.loc.gov/image-services/iiif/service:gmd:gmd3:g3200:g3200:ct000725C/full/pct:22/0/default.jpg",
		"https://www.loc.gov/resource/g3200.ct000725", "Public domain (Wikimedia Commons, PD-old-100)",
		(-180.0, -60.0, 180.0, 75.0), ""),
	:mercator => ("Nova et Aucta Orbis Terrae Descriptio", 1569, "Gerhard Mercator", "Universitätsbibliothek Basel",
		"https://www.e-rara.ch/i3f/v20/30341994/full/4000,/0/default.jpg",
		"https://doi.org/10.3931/e-rara-25290", "Public Domain Mark 1.0 (e-rara)",
		(-180.0, -70.0, 180.0, 80.0), "the sheets, joined"),
	:gerritsz => ("Caert van't Landt van d'Eendracht", 1627, "Hessel Gerritsz", "National Library of Australia",
		"https://thumb.wikimedia.org/wikipedia/commons/thumb/e/e6/Caert_van%27t_Landt_van_d%27Eendracht_%28NLA%29.jpg/3840px-Caert_van%27t_Landt_van_d%27Eendracht_%28NLA%29.jpg",
		"https://commons.wikimedia.org/wiki/File:Caert_van%27t_Landt_van_d%27Eendracht_(NLA).jpg", "Public domain (Wikimedia Commons, PD-Art)",
		(105.0, -38.0, 135.0, -10.0), "the west coast of Australia"),
	:tasman => ("Tasman map", 1644, "unknown, after Abel Tasman's voyages", "State Library of New South Wales",
		"https://thumb.wikimedia.org/wikipedia/commons/thumb/0/0b/Tasman_Map_SLNSWSLNSW_FL19288478.jpg/3840px-Tasman_Map_SLNSWSLNSW_FL19288478.jpg",
		"https://commons.wikimedia.org/wiki/File:Tasman_Map_SLNSWSLNSW_FL19288478.jpg", "Public domain (Wikimedia Commons, PD-Australia)",
		(95.0, -50.0, 180.0, 5.0), "Australia, New Zealand and New Guinea"),
	:peutinger => ("Tabula Peutingeriana, segment IV", 1200, "unknown", "Österreichische Nationalbibliothek",
		"https://api.onb.ac.at/iiif/image/v3/10002029/uk4nGb4kQJKJxrSr/full/4000,/0/default.jpg",
		"https://data.onb.ac.at/dtl/2764184", "Attribution: Austrian National Library (its IIIF manifest)",
		(5.0, 36.0, 20.0, 48.0), "segment IV, with Italy and Rome"),
]

"""
	famous_maps()

Famous maps of the world, as a table: `id`, `title`, `year`, `author`, `library` (the library that holds the map),
`image` (the address of an image of the map), `page` (the page of the image), `terms` (the terms under which the
image is published), `west`, `south`, `east` and `north` (the region the map shows, on today's coordinates) and
`note`. The maps are not georeferenced: each is shown beside today's map of its region. The year of the Tabula
Peutingeriana is the first of 1200-1220, the date the Austrian National Library gives its copy, a roll now in 11
segments; the image is of segment IV.
"""
function famous_maps()
	ids = first.(FAMOUS_MAPS)
	specs = last.(FAMOUS_MAPS)
	field(k) = [s[k] for s in specs]
	return (id = ids, title = field(1), year = field(2), author = field(3), library = field(4),
		image = field(5), page = field(6), terms = field(7), west = [s[8][1] for s in specs], south = [s[8][2] for s in specs],
		east = [s[8][3] for s in specs], north = [s[8][4] for s in specs], note = field(9))
end

"""
	famous_map(id)

One map of [`famous_maps`](@ref), as a named tuple of its columns.
"""
function famous_map(id::Symbol)
	maps = famous_maps()
	at = findfirst(==(id), maps.id)
	at === nothing && throw(ArgumentError("id is one of $(join(":" .* string.(maps.id), ", ")), not :$(id)"))
	return NamedTuple{keys(maps)}(Tuple(column[at] for column in maps))
end

"""
	save_geotiff(url, box; zoom, path, tilesize = 256)

Saves the tiles of `url` (an address with `{z}`, `{x}` and `{y}` in it, such as the `url` of [`ign_layer`](@ref) or
the `tiles` of [`allmaps`](@ref)) that cover `box` (west, south, east, north, in degrees) at zoom `zoom`, as one
GeoTIFF in Web Mercator (EPSG:3857) at `path`, which is returned. GDAL reads the tiles through its WMS driver, with
red, green, blue and alpha bands. A zoom higher by one doubles the width and height of the image: 2 to the power
`zoom` tiles span the world. Tiles outside the map, or missing on the server, are left transparent.

Needs ArchGDAL.jl loaded (`using ArchGDAL`).
"""
function save_geotiff(url::AbstractString, box; zoom::Integer, path::AbstractString, tilesize::Integer = 256)
	ext = Base.get_extension(@__MODULE__, :HistoricalGeographyTilesExt)
	ext === nothing && error("save_geotiff writes the GeoTIFF with ArchGDAL.jl: run `using ArchGDAL` first")
	occursin(r"\{z\}.*\{[xy]\}"s, url) || throw(ArgumentError("the address has no {z}, {x} and {y} in it: $(first(url, 120))"))
	length(box) == 4 || throw(ArgumentError("box is (west, south, east, north), in degrees"))
	0 <= zoom <= 22 || throw(ArgumentError("zoom runs from 0 to 22"))
	return ext.tiles_geotiff(url, Float64.(Tuple(box)), Int(zoom), path, Int(tilesize))
end
