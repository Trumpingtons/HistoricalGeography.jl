# The sources of paleography: digitised manuscripts, a dictionary of abbreviations, and data sets of transcribed and
# classified handwriting, each downloaded once into a folder

const ECODICES = "https://e-codices.ch/metadata/iiif/"

"""A IIIF file of e-codices, downloaded once into `folder`; e-codices refuses requests that come too fast, so they come a second apart."""
function ecodices_file(url::AbstractString, folder::AbstractString)
	path = joinpath(folder, "e-codices", replace(chopprefix(url, ECODICES), "/" => "-"))
	isfile(path) || sleep(1)
	return JSON.parse(read(kept(url, path), String))
end

"""
	ecodices_libraries(; folder)

The libraries of e-codices, the Virtual Manuscript Library of Switzerland, as rows `library` (the name of its
collection, as `kba` for the Aargauer Kantonsbibliothek in Aarau, `csg` the Stiftsbibliothek of St. Gallen) and
`name`. The list is downloaded once into `folder`.
"""
ecodices_libraries(; folder::AbstractString) =
	[(library = chopsuffix(basename(c["@id"]), ".json"), name = c["label"]) for c in ecodices_file(ECODICES * "collection.json", folder)["collections"]]

"""The values of a field of a IIIF manifest of e-codices, joined by `; ` when it comes more than once, without their HTML."""
function manifest_field(manifest, label::AbstractString)
	values = [string(m["value"]) for m in manifest["metadata"] if m["label"] == label]
	return replace(join(values, "; "), r"<[^>]+>" => "")
end

"""
	ecodices(library; folder, saved = nothing)

The manuscripts of a library of e-codices (see [`ecodices_libraries`](@ref)), from their IIIF manifests, each
downloaded once into `folder`, a second apart: a row per manuscript with its shelfmark in the library (`manuscript`,
as MsMurF 3), title, date, summary, century, place of origin, language, material, number of pages, dimensions,
number of images, DOI, its `citation`, how to quote it as e-codices writes it (Aarau, Aargauer Kantonsbibliothek,
MsBN 47: Henry Suso, Büchlein der ewigen Weisheit, and the address of its page), its `page` on e-codices, where it is
read and described, the address of its IIIF `manifest`, from which [`ecodices_pages`](@ref) reads its images,
whether it is `saved` whole in the folder `saved` by [`ecodices_save`](@ref), and whether that copy is `collated` into
a PDF. The rows are in the order of the
shelfmarks, their numbers counted as numbers: MsMurF 2 before MsMurF 10. A field that comes more than once, as the
century of a manuscript of two centuries, has its values joined by `; `. [`linked`](@ref) shows the shelfmarks as
links to the pages.
"""
function ecodices(library::AbstractString; folder::AbstractString, saved::Union{AbstractString, Nothing} = nothing)
	rows = map(ecodices_file(ECODICES * "collection/$(library).json", folder)["manifests"]) do entry
		manuscript_row(ecodices_file(entry["@id"], folder), entry["@id"], saved)
	end
	return sort!(rows; by = r -> natural_order(r.manuscript))
end

"""The row of a manuscript of e-codices, from its manifest `m` at `url`, as [`ecodices`](@ref) gives it."""
function manuscript_row(m, url::AbstractString, saved::Union{AbstractString, Nothing})
	shelfmark = manifest_field(m, "Shelfmark")
	title, page = manifest_field(m, "Title (English)"), string(get(m, "related", ""))
	cited = join(filter(!isempty, [manifest_field(m, "Location"), manifest_field(m, "Collection Name"), shelfmark]), ", ")
	return (manuscript = isempty(shelfmark) ? m["label"] : shelfmark, title = title,
		date = manifest_field(m, "Date of Origin (English)"), summary = manifest_field(m, "Summary (English)"),
		century = manifest_field(m, "Century"), origin = manifest_field(m, "Place of Origin (English)"),
		language = manifest_field(m, "Text Language"), material = manifest_field(m, "Material"),
		pages = manifest_field(m, "Number of Pages"), dimensions = manifest_field(m, "Dimensions"),
		images = length(m["sequences"][1]["canvases"]), doi = manifest_field(m, "DOI"),
		citation = cited * (isempty(title) ? "" : ": " * title) * (isempty(page) ? "" : " ($(page))") * ".",
		page = page, manifest = String(url), saved = ecodices_saved(url, saved) !== nothing, collated = ecodices_pdf(url, saved) !== nothing)
end

"""
	ecodices_library(library; folder)

The name of a library of e-codices from the name of its collection, as `Aarau, Aargauer Kantonsbibliothek` for `kba`
(see [`ecodices_libraries`](@ref)).
"""
function ecodices_library(library::AbstractString; folder::AbstractString)
	names = [l.name for l in ecodices_libraries(; folder) if l.library == library]
	isempty(names) && throw(ArgumentError("e-codices has no library $(repr(library)): its codes are in the column library of ecodices_libraries"))
	return only(names)
end

"""The address of an image of e-codices, `width` pixels wide, from the address of its IIIF image at full size."""
ecodices_width(url::AbstractString, width::Integer) = replace(url, "/full/full/" => "/full/$(width),/")

"""
	ecodices_image(manifest, n; folder, width = 1000)

The `n`th image of the manuscript of a IIIF manifest of e-codices (the column `manifest` of [`ecodices`](@ref)),
`width` pixels wide, downloaded once into `folder` from the IIIF image server; returns the file and the image's
label, as `(; file, label)`.
"""
function ecodices_image(manifest::AbstractString, n::Integer; folder::AbstractString, width::Integer = 1000)
	canvas = ecodices_file(manifest, folder)["sequences"][1]["canvases"][n]
	url = ecodices_width(canvas["images"][1]["resource"]["@id"], width)
	name = chopsuffix(basename(dirname(dirname(dirname(dirname(url))))), ".jp2") * "-$(width).jpg"
	path = joinpath(folder, "e-codices", name)
	isfile(path) || sleep(1)
	return (file = kept(url, path), label = string(canvas["label"]))
end

"""The folder of the saved copy of a manuscript of e-codices in `saved`, as `e-codices/kba-BN0047`, from its manifest's address."""
ecodices_copy(manifest::AbstractString, saved::AbstractString) = joinpath(saved, "e-codices", basename(dirname(manifest)))

"""The file of the `n`th image of a saved copy, with its label, as `0003 V1r.jpg`."""
ecodices_page_file(n::Integer, label::AbstractString) = lpad(n, 4, '0') * " " * replace(label, r"[^\p{L}\p{N} .()-]" => "_") * ".jpg"

"""
	ecodices_saved(manifest, saved)

The folder of the copy of the manuscript of a IIIF manifest of e-codices that [`ecodices_save`](@ref) saved whole in
`saved`, as its images or collated into a PDF, or `nothing` when there is none, or `saved` is `nothing` or empty.
"""
function ecodices_saved(manifest::AbstractString, saved::Union{AbstractString, Nothing})
	(saved === nothing || isempty(saved)) && return nothing
	copy = ecodices_copy(manifest, saved)
	return isfile(joinpath(copy, "record.toml")) ? copy : nothing
end

"""
	ecodices_pdf(manifest, saved)

The PDF of the manuscript of a IIIF manifest of e-codices that [`ecodices_save`](@ref) collated in `saved`, or
`nothing` when it is not saved, or saved as its images.
"""
function ecodices_pdf(manifest::AbstractString, saved::Union{AbstractString, Nothing})
	copy = ecodices_saved(manifest, saved)
	copy === nothing && return nothing
	record = TOML.parsefile(joinpath(copy, "record.toml"))
	return get(record, "collated", false) ? joinpath(copy, record["pdf"]) : nothing
end

"""
	ecodices_pages(manifest; folder, width = 2000, saved = nothing)

The images of the manuscript of a IIIF manifest of e-codices (the column `manifest` of [`ecodices`](@ref)), each
leaf, cover and paste-down in the order of the manuscript, `width` pixels wide: their files when
[`ecodices_save`](@ref) saved the manuscript's images in `saved`, read without a connection, else their addresses
on the IIIF image server (`images`), and their labels (`labels`), as `V1r`, `1v` or `Front cover`, which
`Pollis.browse(images; labels)` goes through page by page. Only the manifest is downloaded, once, into `folder`. A
manuscript collated into a PDF is read from [`ecodices_pdf`](@ref).
"""
function ecodices_pages(manifest::AbstractString; folder::AbstractString, width::Integer = 2000, saved::Union{AbstractString, Nothing} = nothing)
	copy = ecodices_saved(manifest, saved)
	if copy !== nothing && ecodices_pdf(manifest, saved) === nothing
		labels = [string(c["label"]) for c in JSON.parse(read(joinpath(copy, "manifest.json"), String))["sequences"][1]["canvases"]]
		return (images = [joinpath(copy, ecodices_page_file(n, label)) for (n, label) in enumerate(labels)], labels = labels)
	end
	canvases = ecodices_file(manifest, folder)["sequences"][1]["canvases"]
	return (images = [ecodices_width(string(c["images"][1]["resource"]["@id"]), width) for c in canvases], labels = [string(c["label"]) for c in canvases])
end

"""
	ecodices_copies(saved)

The manuscripts of e-codices that [`ecodices_save`](@ref) saved whole in the folder `saved`, of any library, as the
rows of [`ecodices`](@ref), first with the code of their `library` and its `name`: read from the copies, without a
connection, in the order of the libraries' names and of the shelfmarks.
"""
function ecodices_copies(saved::AbstractString)
	root = joinpath(saved, "e-codices")
	folders = isdir(root) ? filter(f -> isfile(joinpath(root, f, "record.toml")), readdir(root)) : String[]
	rows = map(folders) do f
		record = TOML.parsefile(joinpath(root, f, "record.toml"))
		m = JSON.parse(read(joinpath(root, f, "manifest.json"), String))
		name = join(filter(!isempty, [manifest_field(m, "Location"), manifest_field(m, "Collection Name")]), ", ")
		(library = String(first(split(f, '-'))), name = name, manuscript_row(m, record["manifest"], saved)...)
	end
	return sort!(rows; by = r -> (r.name, natural_order(r.manuscript)))
end

"""
	ecodices_copy_libraries(saved)

The libraries of the manuscripts of e-codices saved in `saved` (see [`ecodices_copies`](@ref)), as rows `library`
(the code of its collection), `name` and `manuscripts` (how many are saved), in the order of their names.
"""
ecodices_copy_libraries(saved::AbstractString) =
	[(library = l.library, name = l.name, manuscripts = count(c -> c.library == l.library, copies))
		for copies in (ecodices_copies(saved),) for l in unique(c -> c.library, copies)]

"""
	ecodices_save(manifest; folder, saved, width = 2000, collated = false)

Saves the manuscript of a IIIF manifest of e-codices whole into its own folder of `saved`, as `e-codices/kba-BN0047`:
each image `width` pixels wide, a second apart, named by its number and label (`0003 V1r.jpg`), the manifest
(`manifest.json`) and, once every image is there, `record.toml`, with the citation, title, date, page on e-codices,
manifest and number of images, by which [`ecodices_saved`](@ref) knows the copy whole. With `collated`, the images
then go into one PDF, `kba-BN0047.pdf`, each JPEG as it is, its pages labelled with the folios and the citation
among its properties, and are deleted. Images saved before are kept, so a save that stopped goes on from where it
stopped, and a manuscript saved as images is collated without downloading them again. Prints how far it has come
every 25 images. Returns the folder, the number of images saved and the numbers of those that did not come, as
`(; folder, saved, missed)`.
"""
function ecodices_save(manifest::AbstractString; folder::AbstractString, saved::AbstractString, width::Integer = 2000, collated::Bool = false)
	isempty(saved) && throw(ArgumentError("ecodices_save needs the folder to save in"))
	m = ecodices_file(manifest, folder)
	canvases = m["sequences"][1]["canvases"]
	copy = mkpath(ecodices_copy(manifest, saved))
	collated && ecodices_pdf(manifest, saved) !== nothing && return (folder = copy, saved = length(canvases), missed = Int[])
	labels = [string(c["label"]) for c in canvases]
	files = [joinpath(copy, ecodices_page_file(n, label)) for (n, label) in enumerate(labels)]
	missed = Int[]
	for (n, canvas) in enumerate(canvases)
		if !isfile(files[n])
			sleep(1)
			try
				kept(ecodices_width(string(canvas["images"][1]["resource"]["@id"]), width), files[n])
			catch e
				interrupted(e) && rethrow()
				push!(missed, n)
			end
		end
		n % 25 == 0 && println(n, " of ", length(canvases), " images")
	end
	write(joinpath(copy, "manifest.json"), JSON.json(m))
	isempty(missed) || return (folder = copy, saved = length(canvases) - length(missed), missed = missed)
	row = manuscript_row(m, manifest, nothing)
	record = Dict("manuscript" => row.manuscript, "title" => row.title, "date" => row.date, "citation" => row.citation,
		"page" => row.page, "manifest" => row.manifest, "images" => length(canvases), "width" => width, "collated" => collated)
	if collated
		println("Collating the ", length(files), " images into one PDF")
		record["pdf"] = basename(copy) * ".pdf"
		collate_pdf(joinpath(copy, record["pdf"]), files, labels; title = "$(row.manuscript): $(row.title)", subject = row.citation)
	end
	# The record before the images go, so that a copy is never without both
	open(io -> TOML.print(io, record), joinpath(copy, "record.toml"), "w")
	collated && foreach(rm, files)
	return (folder = copy, saved = length(canvases), missed = missed)
end

"""The width, height and number of colour components of a JPEG, from its frame header."""
function jpeg_size(file::AbstractString)
	bytes = read(file)
	length(bytes) > 4 && bytes[1] == 0xff && bytes[2] == 0xd8 || throw(ArgumentError("$file is not a JPEG"))
	i = 3
	while i + 9 <= length(bytes)
		bytes[i] == 0xff || throw(ArgumentError("$file has no frame header"))
		marker = bytes[i + 1]
		marker == 0xff && (i += 1; continue)
		# The frame headers of every kind of JPEG: SOF0 to SOF15 but DHT (C4), JPG (C8) and DAC (CC)
		if 0xc0 <= marker <= 0xcf && marker ∉ (0xc4, 0xc8, 0xcc)
			return (width = Int(bytes[i + 7]) << 8 | bytes[i + 8], height = Int(bytes[i + 5]) << 8 | bytes[i + 6], components = Int(bytes[i + 9]))
		end
		i += 2 + (Int(bytes[i + 2]) << 8 | bytes[i + 3])
	end
	throw(ArgumentError("$file has no frame header"))
end

"""A text of a PDF, in UTF-16 written in hexadecimal, so that any letter and bracket can be in it."""
pdf_text(text::AbstractString) = "<FEFF" * join(string(u; base = 16, pad = 4) for u in transcode(UInt16, String(text))) * ">"

"""
Writes `images`, JPEG files, as the pages of one PDF at `path`, each as it is, without being decoded again, at 200
pixels an inch, its page labelled with its label, as `1r`, and `title` and `subject` among the PDF's properties.
"""
function collate_pdf(path::AbstractString, images::AbstractVector{<:AbstractString}, labels::AbstractVector{<:AbstractString};
		title::AbstractString, subject::AbstractString)
	n = length(images)
	# The objects: 1 the catalogue, 2 the pages, 3 the properties, and three a page: the page, its content and its image
	offsets = zeros(Int, 3 + 3n)
	open(path * ".part", "w") do io
		write(io, "%PDF-1.4\n%", [0xe2, 0xe3, 0xcf, 0xd3], "\n")
		object(k, body) = (offsets[k] = position(io); write(io, "$k 0 obj\n", body, "\nendobj\n"))
		labelled = join(("$(k - 1) << /P $(pdf_text(labels[k])) >>" for k in 1:n), " ")
		object(1, "<< /Type /Catalog /Pages 2 0 R /PageLabels << /Nums [$labelled] >> >>")
		object(2, "<< /Type /Pages /Kids [$(join(("$(1 + 3k) 0 R" for k in 1:n), " "))] /Count $n >>")
		object(3, "<< /Title $(pdf_text(title)) /Subject $(pdf_text(subject)) /Producer (HistoricalGeography.jl) >>")
		for (k, file) in enumerate(images)
			page = 1 + 3k
			size = jpeg_size(file)
			width, height = round(size.width * 72 / 200; digits = 2), round(size.height * 72 / 200; digits = 2)
			object(page, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $width $height] /Resources << /XObject << /Im $(page + 2) 0 R >> >> /Contents $(page + 1) 0 R >>")
			drawn = "q $width 0 0 $height 0 0 cm /Im Do Q"
			object(page + 1, "<< /Length $(ncodeunits(drawn)) >>\nstream\n$drawn\nendstream")
			colours = size.components == 1 ? "/DeviceGray" : size.components == 4 ? "/DeviceCMYK" : "/DeviceRGB"
			data = read(file)
			offsets[page + 2] = position(io)
			write(io, "$(page + 2) 0 obj\n<< /Type /XObject /Subtype /Image /Width $(size.width) /Height $(size.height) /ColorSpace $colours /BitsPerComponent 8 /Filter /DCTDecode /Length $(length(data)) >>\nstream\n")
			write(io, data, "\nendstream\nendobj\n")
		end
		xref = position(io)
		write(io, "xref\n0 $(n * 3 + 4)\n0000000000 65535 f \n")
		foreach(offset -> write(io, lpad(offset, 10, '0'), " 00000 n \n"), offsets)
		write(io, "trailer\n<< /Size $(n * 3 + 4) /Root 1 0 R /Info 3 0 R >>\nstartxref\n$xref\n%%EOF\n")
	end
	return mv(path * ".part", path; force = true)
end

const CAPPELLI = "https://www.adfontes.uzh.ch/media/files/5_Ressourcen/cappelli.zip"

"""
	cappelli(con; folder, table = "cappelli")

The abbreviations of Adriano Cappelli's Lexicon Abbreviaturarum (Leipzig, 1928), as the Ad fontes hackathon of the
University of Zürich (2015) cut them out of its pages, written to the table `table` of `con`: a row per abbreviation
with its `id`, its `page` in the Lexicon, the `letters` it starts with, its `transcription`, `category`, `century`
(as XV) and `period` of the manuscripts it comes from (XV m. is the middle of the 15th century, p. the start, f. the
end) and `language`. The categories are in German, as the hackathon gave them: römische Zahl is a Roman numeral,
Westgotisch Visigothic. Returns the number of abbreviations.

The archive (49 MB), with the spreadsheet and an image of each abbreviation, is downloaded once into `folder`; the
spreadsheet is read with DuckDB's extension `excel`, which `con` must be able to load.
"""
function cappelli(con; folder::AbstractString, table::AbstractString = "cappelli")
	archive = kept(CAPPELLI, joinpath(folder, "cappelli.zip"))
	sheet = joinpath(folder, "cappelli.xlsx")
	isfile(sheet) || write(sheet, zip_readentry(ZipReader(read(archive)), "cappelli.xlsx"))
	DBInterface.execute(con, "LOAD excel")
	DBInterface.execute(con, """CREATE OR REPLACE TABLE "$(table)" AS
		SELECT id, page_id AS page, characters AS letters, transcription, category,
			regexp_extract(period, '^([IVX]+)', 1) AS century, period, language
		FROM read_xlsx('$(quoted(sheet))', all_varchar = true) ORDER BY TRY_CAST(id AS INTEGER)""")
	return only(rows(con, """SELECT count(*) AS n FROM "$(table)" """).n)
end

"""
	cappelli_image(id; folder)

The image of the abbreviation `id` of [`cappelli`](@ref), taken out of its archive in `folder` and saved beside it;
returns the file.
"""
function cappelli_image(id; folder::AbstractString)
	path = joinpath(folder, "cappelli_$(id).jpg")
	isfile(path) || write(path, zip_readentry(ZipReader(read(kept(CAPPELLI, joinpath(folder, "cappelli.zip")))), "img_abbr/$(id).jpg"))
	return path
end

"""A licence of HTR-United's catalogue: its name, or its type and version."""
htr_licence(l) = haskey(l, "name") ? string(l["name"]) : strip("$(get(l, "type", "")) $(get(l, "version", ""))")

"""
	htr_united(; folder)

The catalogue of HTR-United, the data sets made to train handwritten text recognition (HTR) and OCR, downloaded again
into `folder` once a day (0.5 MB): a row per data set with its `title`, `languages` (ISO 639 codes: lat Latin, fro Old
French), `scripts` (ISO 15924: Latn Latin, Grek Greek, Arab Arabic), `kind` (handwritten or printed), the years
`from` and `to`, `format` (ALTO or PAGE XML), its numbers of `lines`, `pages` and `characters` (0 when it does not
count them), `licence` (those of a data set of more than one joined by `; `), `software` and `url`.
"""
function htr_united(; folder::AbstractString)
	entries = JSON.parse(read(fresh("https://raw.githubusercontent.com/HTR-United/htr-united/master/catalog.json",
		joinpath(folder, "htr-united.json")), String))
	volume(e, metric) = sum((v["count"] for v in e["volume"] if v["metric"] == metric); init = 0)
	licences(e) = join((htr_licence(l) for l in (e["license"] isa AbstractVector ? e["license"] : [e["license"]])), "; ")
	map(sort!(collect(values(entries)); by = e -> strip(e["title"]))) do e
		(title = strip(e["title"]), languages = join(e["language"], ", "), scripts = join((s["iso"] for s in e["script"]), ", "),
			kind = e["script-type"], from = get(e["time"], "notBefore", ""), to = get(e["time"], "notAfter", ""),
			format = e["format"], lines = volume(e, "lines"), pages = volume(e, "pages"), characters = volume(e, "characters"),
			licence = licences(e), software = e["production-software"], url = e["url"])
	end
end

const CATMUS = "https://huggingface.co/datasets/CATMuS/medieval"
const CATMUS_FILE = r"^(?<split>\w+)/L-(?<language>[^.]+)\.C-(?<century>\d+)\.S-(?<script>[^.]+)\.(?<shelfmark>.+)\.H-\w+\.Part-(?<part>\d+)"

"""
	catmus_files()

The files of CATMuS Medieval on Hugging Face, read each time: a Parquet file per manuscript (or per part of one) in
the splits train, dev and test, as rows `shelfmark` (its parts joined by `__`, its spaces by `_`: `Paris__BnF__esp__33`
is Paris, BnF, esp. 33), `language` (Lat Latin, Fre French, Cas Castilian, Mid_Dut Middle Dutch, Ita Italian, Cat
Catalan, Occ Occitan), `century`, `script` (Tex Textualis, Cur Cursiva, Hyb Hybrida, Car Caroline, Sem
Semitextualis, Hum Humanistica, Pra Praegothica, Pri printed, an incunable), `split`, `part` (from 0), `megabytes`
and `path`.
"""
function catmus_files()
	api = "https://huggingface.co/api/datasets/CATMuS/medieval/tree/main/"
	map([f for split in ("train", "dev", "test") for f in fetched(api * split)]) do f
		m = match(CATMUS_FILE, f["path"])
		(shelfmark = m[:shelfmark], language = m[:language], century = parse(Int, m[:century]), script = m[:script],
			split = m[:split], part = parse(Int, m[:part]), megabytes = round(f["size"] / 1e6; digits = 1), path = f["path"])
	end
end

"""
	catmus(con, manuscript; folder, view = "catmus")

The lines of a manuscript of CATMuS Medieval, by its `shelfmark` in [`catmus_files`](@ref), as the view `view` of
`con`: a row per line, numbered from 1 (`line`), with its `text`, the `shelfmark`, `language`, `century`,
`script_type`, `genre` and `region` of its manuscript, its `project` and `line_type`, and its image as PNG
(`im.bytes`). The manuscript's files are downloaded once into `folder`. Returns the number of lines.
"""
function catmus(con, manuscript::AbstractString; folder::AbstractString, view::AbstractString = "catmus")
	chosen = filter(f -> f.shelfmark == manuscript, catmus_files())
	isempty(chosen) && throw(ArgumentError("CATMuS Medieval has no manuscript $(manuscript)"))
	paths = [kept("$(CATMUS)/resolve/main/$(f.path)", joinpath(folder, "catmus", basename(f.path))) for f in chosen]
	list = join(("'$(quoted(p))'" for p in paths), ", ")
	DBInterface.execute(con, """CREATE OR REPLACE VIEW "$(view)" AS
		SELECT row_number() OVER (ORDER BY filename, file_row_number) AS line, *
		FROM read_parquet([$(list)], filename = true, file_row_number = true)""")
	return only(rows(con, """SELECT count(*) AS n FROM "$(view)" """).n)
end

"""
	catmus_image(con, line; folder, view = "catmus")

The image of the line `line` of the view `view` of `con` (made by [`catmus`](@ref)), saved as PNG into `folder`;
returns the file.
"""
function catmus_image(con, line::Integer; folder::AbstractString, view::AbstractString = "catmus")
	row = only(Tables.rowtable(DBInterface.execute(con, """SELECT shelfmark, im.bytes AS bytes FROM "$(view)" WHERE line = $(line)""")))
	path = joinpath(mkpath(joinpath(folder, "catmus")), replace(row.shelfmark, r"[^\w.-]+" => "_") * "_$(line).png")
	write(path, row.bytes)
	return path
end

const CLAMM = "https://zenodo.org/records/5527690/files/ICDAR2017_CLaMM_Training.zip"
const CLAMM_SCRIPTS = ["Caroline", "Cursiva", "Half-Uncial", "Humanistic", "Humanistic Cursive", "Hybrida", "Praegothica",
	"Semihybrida", "Semitextualis", "Southern Textualis", "Textualis", "Uncial"]
const CLAMM_DATES = ["before 1000", "1001-1100", "1101-1200", "1201-1250", "1251-1300", "1301-1350", "1351-1400", "1401-1425",
	"1426-1450", "1451-1475", "1476-1500", "1501-1525", "1526-1550", "1551-1575", "1576-1600"]

"""
	clamm(; folder)

The training set of the ICDAR 2017 Competition on the Classification of Medieval Handwritings in Latin Script
(CLaMM), an archive of 5.5 GB downloaded once into `folder` from Zenodo and read without unpacking it. Returns
`(; images, scripts)`: a row per image with its file (`image`), `script` and `date`, and a row per script with its
number of images in each class of dates, from before 1000 to 1576-1600.
"""
function clamm(; folder::AbstractString)
	reader = ZipReader(Mmap.mmap(kept(CLAMM, joinpath(folder, "ICDAR2017_CLaMM_Training.zip"))))
	labels = split(zip_readentry(reader, "ICDAR2017_CLaMM_Training/@ICDAR2017_CLaMM_Training.csv", String), r"\r?\n"; keepempty = false)
	images = map(Iterators.drop(labels, 1)) do line
		file, script, date = split(line, ';')
		(image = String(file), script = CLAMM_SCRIPTS[parse(Int, script)], date = CLAMM_DATES[parse(Int, date)])
	end
	scripts = [(; script = s, (Symbol(d) => count(i -> i.script == s && i.date == d, images) for d in CLAMM_DATES)...) for s in CLAMM_SCRIPTS]
	return (; images, scripts)
end

"""
	clamm_image(image; folder)

An image of [`clamm`](@ref), by its file, taken out of the archive in `folder` and saved beside it; returns the file.
"""
function clamm_image(image::AbstractString; folder::AbstractString)
	path = joinpath(folder, image)
	isfile(path) || write(path, zip_readentry(ZipReader(Mmap.mmap(kept(CLAMM, joinpath(folder, "ICDAR2017_CLaMM_Training.zip")))),
		"ICDAR2017_CLaMM_Training/$(image)"))
	return path
end

const PAGE = ["p" => "http://schema.primaresearch.org/PAGE/gts/pagecontent/2013-07-15"]
const DIVA_MANUSCRIPTS = Dict("CB55" => "Cod. Bodmer 55", "CS18" => "Cod. Sang. 18", "CSG18" => "Cod. Sang. 18",
	"CS863" => "Cod. Sang. 863", "CSG863" => "Cod. Sang. 863")

"""
	divahisdb(; folder)

The layout of the pages of DIVA-HisDB, three manuscripts of St. Gallen and Cologny, as drawn by hand in PAGE XML:
a row per page with its `manuscript` (Cod. Bodmer 55, Cod. Sang. 18 or Cod. Sang. 863), `page`, `split` (training,
validation, public-test or private-test), `width` and `height` in pixels, its numbers of `text_regions` and
`decorations` (graphic regions), and its lines of main text (`main_lines`) and of comments (`comment_lines`), the
glosses written between and beside them; the pages of the private test have the lines of the main text only.

The archive of the DIVA group's site (1.3 GB) is downloaded once into `folder` from Zenodo, and the archives of the
PAGE XML, a few MB per manuscript, are taken out of it once.
"""
function divahisdb(; folder::AbstractString)
	archive = kept("https://zenodo.org/records/19127869/files/DIVAHisDB.tar.gz", joinpath(folder, "DIVAHisDB.tar.gz"))
	dir = joinpath(folder, "DIVA-HisDB")
	if !isdir(dir)
		wanted(h) = occursin(r"/diva-hisdb/hisdoc/(private-test/)?PAGE-gt-[\w-]+\.zip$", h.path) && !occursin("TASK-2", h.path)
		open(io -> Tar.extract(wanted, GzipDecompressorStream(io), dir * ".part"), archive)
		mv(dir * ".part", dir)
	end
	zips = sort!([joinpath(root, f) for (root, _, files) in walkdir(dir) for f in files if endswith(f, ".zip")])
	pages = [begin
		doc = EzXML.parsexml(zip_readentry(reader, name, String))
		p = findfirst("//p:Page", EzXML.root(doc), PAGE)
		lines = [l["id"] for l in findall("//p:TextLine", EzXML.root(doc), PAGE)]
		(manuscript = DIVA_MANUSCRIPTS[match(r"PAGE-gt-(?<m>[A-Z]+\d+)", file)[:m]], page = chopsuffix(basename(name), ".xml"),
			split = occursin("privateTest", file) ? "private-test" : basename(dirname(name)),
			width = parse(Int, p["imageWidth"]), height = parse(Int, p["imageHeight"]),
			text_regions = length(findall("//p:TextRegion", EzXML.root(doc), PAGE)),
			decorations = length(findall("//p:GraphicRegion", EzXML.root(doc), PAGE)),
			main_lines = count(startswith("textline_"), lines), comment_lines = count(startswith("comment_"), lines))
	end for file in zips for reader in (ZipReader(read(file)),) for name in zip_names(reader) if endswith(name, ".xml")]
	return sort!(pages; by = p -> (p.manuscript, p.page))
end

const ALTO = ["a" => "http://www.loc.gov/standards/alto/ns-v4#"]

"""
	biblia(; folder)

BiblIA, pages of medieval Hebrew manuscripts of the Bibliothèque nationale de France (BnF) and the Vatican Library
(BAV), transcribed line by line in ALTO XML: an archive of 546 MB downloaded once into `folder` from Zenodo and read
without unpacking it. Returns `(; pages, lines)`: a row per page with its `script` (Ashkenazy, Italian or Sephardi),
`library`, `shelfmark`, `date`, `genre` (Biblical or Rabbinic), `split` (train or test), its numbers of `lines` and
`characters`, its `first_line`, and its `image` (an entry of the archive for the BnF's pages, a link for the BAV's);
and a row per line with its `page`, number (`line`), `script`, `shelfmark` and `text`.
"""
function biblia(; folder::AbstractString)
	reader = ZipReader(Mmap.mmap(kept("https://zenodo.org/records/5167263/files/BiblIA_dataset.zip", joinpath(folder, "BiblIA_dataset.zip"))))
	entries = Dict(basename(n) => n for n in zip_names(reader))
	catalogue = [split(line, '\t') for line in split(zip_readentry(reader, entries["catalogue.txt"], String), r"\r?\n") if !isempty(line)]
	header = strip.(catalogue[1])
	column(row, name) = String(strip(row[findfirst(==(name), header)]))
	function transcription(file)
		doc = EzXML.parsexml(zip_readentry(reader, entries[file], String))
		return [join((s["CONTENT"] for s in findall("a:String", line, ALTO)), " ") for line in findall("//a:TextLine", EzXML.root(doc), ALTO)]
	end
	texts = Dict(column(row, "filename") => transcription(column(row, "filename")) for row in catalogue[2:end])
	pages = map(catalogue[2:end]) do row
		file = column(row, "filename")
		text = texts[file]
		image = chopsuffix(file, ".xml") * ".jpg"
		(page = chopsuffix(file, ".xml"), script = column(row, "script_type"), library = column(row, "library"),
			shelfmark = column(row, "Shelfmark"), date = column(row, "Date"), genre = column(row, "Biblical_or_Rabbinic"),
			split = column(row, "test/train"), lines = length(text), characters = sum(length, text; init = 0),
			first_line = isempty(text) ? "" : first(text), image = haskey(entries, image) ? entries[image] : column(row, "link2img"))
	end
	lines = [(page = p.page, line = i, script = p.script, shelfmark = p.shelfmark, text = t)
		for p in pages for (i, t) in enumerate(texts[p.page * ".xml"])]
	return (; pages, lines)
end

"""
	muharaf(; folder)

The summaries and keywords of the pages of the public part of Muharaf, Manuscripts of Handwritten Arabic, an archive
of 0.8 MB downloaded once into `folder` from Zenodo and read without unpacking it: a row per page, by the name of its
image (`page`, as HM1B_10_03v), with its `keywords` and the `summary` of its transcription. The images and their
transcriptions are in the other archives of the record, of 1.3 GB (the lines) and 3.1 GB (the pages).
"""
function muharaf(; folder::AbstractString)
	reader = ZipReader(read(kept("https://zenodo.org/records/11492215/files/public_summary_and_keywords.zip",
		joinpath(folder, "public_summary_and_keywords.zip"))))
	entries = Set(zip_names(reader))
	text(name) = name in entries ? String(strip(zip_readentry(reader, name, String))) : ""
	map(sort!([chopsuffix(basename(n), ".summary.txt") for n in entries if endswith(n, ".summary.txt")])) do page
		(page = page, keywords = replace(text("public/$(page).keywords_response.txt"), ";" => ", "), summary = text("public/$(page).summary.txt"))
	end
end

"""
The array of a NumPy `.npy` file, in Julia's order of dimensions as NumPy's (the first index the slowest in NumPy is
the first here): of unsigned or signed integers or floats, little-endian, not in Fortran order.
"""
function npy(bytes::AbstractVector{UInt8})
	bytes[1:6] == [0x93; codeunits("NUMPY")] || throw(ArgumentError("not a NumPy file"))
	count, start = bytes[7] == 1 ? (Int(bytes[9]) + 256 * Int(bytes[10]), 11) : (Int(reinterpret(UInt32, bytes[9:12])[1]), 13)
	header = String(bytes[start:start + count - 1])
	occursin("'fortran_order': True", header) && throw(ArgumentError("a NumPy file in Fortran order"))
	descr = match(r"'descr':\s*'[<|](?<d>[uif]\d)'", header)[:d]
	shape = Tuple(parse(Int, d) for d in split(match(r"'shape':\s*\((?<s>[^)]*)\)", header)[:s], ',') if !isempty(strip(d)))
	types = Dict("u1" => UInt8, "i1" => Int8, "u2" => UInt16, "i2" => Int16, "u4" => UInt32, "i4" => Int32, "u8" => UInt64,
		"i8" => Int64, "f4" => Float32, "f8" => Float64)
	array = reshape(collect(reinterpret(types[descr], bytes[start + count:end])), reverse(shape))
	return ndims(array) == 1 ? array : permutedims(array, ndims(array):-1:1)
end

"""The array saved in a NumPy `.npz` file, as its single entry `arr_0`."""
npz(path::AbstractString) = npy(zip_readentry(ZipReader(read(path)), "arr_0.npy"))

"""
	kuzushiji(; folder)

Kuzushiji-49, the hiragana of 49 classes cut out of books of the Edo period by the ROIS-DS Center for Open Data in
the Humanities, each an image of 28 by 28 pixels, downloaded once into `folder` (66 MB to train on, 11 MB to test on).
Returns `(; classes, train, test)`: a row per class with its number (`class`, from 0), `character`, `codepoint` and
numbers of images in the two sets (`train`, `test`); and each set as `(; images, labels)`, the images an array of
grey levels, image by row by column, white strokes on black, and the labels the class of each.
"""
function kuzushiji(; folder::AbstractString)
	site = "http://codh.rois.ac.jp/kmnist/dataset/k49/"
	file(name) = kept(site * name, joinpath(folder, "kuzushiji", name))
	sets = Dict(s => (images = npz(file("k49-$(s)-imgs.npz")), labels = vec(npz(file("k49-$(s)-labels.npz")))) for s in ("train", "test"))
	map_lines = [split(line, ',') for line in Iterators.drop(eachline(file("k49_classmap.csv")), 1)]
	classes = map(map_lines) do c
		class = parse(Int, c[1])
		(class = class, character = String(c[3]), codepoint = String(c[2]), train = count(==(class), sets["train"].labels),
			test = count(==(class), sets["test"].labels))
	end
	return (; classes, train = sets["train"], test = sets["test"])
end

"""
	kuzushiji_image(set, i; path = tempname() * ".pgm")

The `i`th image of a set of [`kuzushiji`](@ref) (its `train` or `test`), written as a grey-scale PGM file to `path`,
which is returned.
"""
function kuzushiji_image(set, i::Integer; path::AbstractString = tempname() * ".pgm")
	image = set.images[i, :, :]
	write(path, "P5 $(size(image, 2)) $(size(image, 1)) 255\n", vec(permutedims(UInt8.(image))))
	return path
end
