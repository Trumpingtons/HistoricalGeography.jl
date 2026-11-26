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
	ecodices(library; folder)

The manuscripts of a library of e-codices (see [`ecodices_libraries`](@ref)), from their IIIF manifests, each
downloaded once into `folder`, a second apart: a row per manuscript with its shelfmark (`manuscript`), title, date,
century, place of origin, language, material, number of pages, dimensions, number of images, summary, DOI and the
address of its manifest. A field that comes more than once, as the century of a manuscript of two centuries, has its
values joined by `; `.
"""
function ecodices(library::AbstractString; folder::AbstractString)
	map(ecodices_file(ECODICES * "collection/$(library).json", folder)["manifests"]) do entry
		m = ecodices_file(entry["@id"], folder)
		(manuscript = m["label"], title = manifest_field(m, "Title (English)"), date = manifest_field(m, "Date of Origin (English)"),
			century = manifest_field(m, "Century"), origin = manifest_field(m, "Place of Origin (English)"),
			language = manifest_field(m, "Text Language"), material = manifest_field(m, "Material"),
			pages = manifest_field(m, "Number of Pages"), dimensions = manifest_field(m, "Dimensions"),
			images = length(m["sequences"][1]["canvases"]), summary = manifest_field(m, "Summary (English)"),
			doi = manifest_field(m, "DOI"), manifest = entry["@id"])
	end
end

"""
	ecodices_image(manifest, n; folder, width = 1000)

The `n`th image of the manuscript of a IIIF manifest of e-codices (the column `manifest` of [`ecodices`](@ref)),
`width` pixels wide, downloaded once into `folder` from the IIIF image server; returns the file and the image's
label, as `(; file, label)`.
"""
function ecodices_image(manifest::AbstractString, n::Integer; folder::AbstractString, width::Integer = 1000)
	canvas = ecodices_file(manifest, folder)["sequences"][1]["canvases"][n]
	url = replace(canvas["images"][1]["resource"]["@id"], "/full/full/" => "/full/$(width),/")
	name = chopsuffix(basename(dirname(dirname(dirname(dirname(url))))), ".jp2") * "-$(width).jpg"
	path = joinpath(folder, "e-codices", name)
	isfile(path) || sleep(1)
	return (file = kept(url, path), label = string(canvas["label"]))
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
