# The sources of papyrology: the databases of papyri.info, the Demotic sentences of the Thesaurus Linguae Aegyptiae,
# the scans of the Herculaneum papyri, and data sets of letters, dates and lines of papyri, each downloaded once into a
# folder

"""The folder of a database of papyri.info, taken once out of the archive of its data (about 180 MB), downloaded once into `folder`."""
function idp(database::AbstractString, folder::AbstractString)
	archive = kept("https://codeload.github.com/papyri/idp.data/tar.gz/refs/heads/master", joinpath(folder, "idp.data.tar.gz"))
	return extracted(archive, joinpath(folder, database), "idp.data-master/$(database)")
end

"""
	ddbdp(; folder)

The texts of the Duke Databank of Documentary Papyri (DDbDP), from the data of papyri.info, downloaded once into
`folder`: a row per text with its Trismegistos number (`tm`), `edition`, `series`, `language`, number of `words`, and
the start of its `text` as written (200 characters), the regularised spellings and the editors' corrections left out.
"""
function ddbdp(; folder::AbstractString)
	xml_records(xml_files(idp("DDbDP", folder))) do doc
		edition = element(doc, "//t:div[@type='edition']")
		language = language_of(edition)
		text = edition_text(edition)
		(tm = field(doc, "//t:idno[@type='TM']"), edition = field(doc, "//t:body/t:head//t:title"),
			series = String(first(split(field(doc, "//t:idno[@type='ddb-hybrid']"), ';'))), language = language,
			words = length(split(text)), text = first(text, 200))
	end
end

"""
	hgv(; folder)

The records of the Heidelberger Gesamtverzeichnis der griechischen Papyrusurkunden Ägyptens (HGV), from the data of
papyri.info, downloaded once into `folder`: a row per record with its Trismegistos number (`tm`), `title`, `place`,
`material`, and the first and last years of its date (`from`, `to`, negative before the Common Era).
"""
function hgv(; folder::AbstractString)
	xml_records(xml_files(idp("HGV_meta_EpiDoc", folder))) do doc
		from, to = origin_years(doc)
		(tm = field(doc, "//t:idno[@type='TM']"), title = field(doc, "//t:titleStmt/t:title"), place = field(doc, "//t:origPlace"),
			material = field(doc, "//t:material"), from = from, to = to)
	end
end

"""
	dclp(; folder)

The literary papyri of the Digital Corpus of Literary Papyri (DCLP), from the data of papyri.info, downloaded once
into `folder`: a row per papyrus with its Trismegistos number (`tm`), its number in the Leuven Database of Ancient
Books (`ldab`), the `author` and `work` it holds, its `contents`, `material`, years (`from`, `to`) and the `language`
of its text, empty when it has no text yet.
"""
function dclp(; folder::AbstractString)
	xml_records(xml_files(idp("DCLP", folder))) do doc
		from, to = origin_years(doc)
		(tm = field(doc, "//t:idno[@type='TM']"), ldab = field(doc, "//t:idno[@type='LDAB']"),
			author = field(doc, "//t:bibl[@subtype='ancient']/t:author"), work = field(doc, "//t:bibl[@subtype='ancient']/t:title"),
			contents = field(doc, "//t:term[@type='overview']"), material = field(doc, "//t:material"), from = from, to = to,
			language = field(doc, "//t:div[@type='edition']/@xml:lang"))
	end
end

"""
	apis(; folder)

The catalogue records of the Advanced Papyrological Information System (APIS), from the data of papyri.info,
downloaded once into `folder`: a row per record with its number (`apis`), `collection`, `title`, `inventory` number,
`language`, years (`from`, `to`) and number of `images`.
"""
function apis(; folder::AbstractString)
	xml_records(xml_files(idp("APIS", folder))) do doc
		from, to = origin_years(doc)
		id = field(doc, "//t:idno[@type='apisid']")
		(apis = id, collection = String(first(split(id, '.'))), title = field(doc, "//t:titleStmt/t:title"),
			inventory = field(doc, "//t:idno[@type='invNo']"), language = field(doc, "//t:textLang/@mainLang"), from = from, to = to,
			images = length(findall("//t:graphic", EzXML.root(doc), TEI)))
	end
end

"""
	apd(; folder)

The documents of the Arabic Papyrology Database (APD), from the data of papyri.info, downloaded once into `folder`:
a row per document with its number (`apd`), `title`, `material`, `place` and years (`from`, `to`).
"""
function apd(; folder::AbstractString)
	xml_records(xml_files(idp("APD", folder))) do doc
		from, to = origin_years(doc)
		(apd = field(doc, "//t:idno[@type='apd']"), title = field(doc, "//t:titleStmt/t:title"), material = field(doc, "//t:material"),
			place = field(doc, "//t:origPlace"), from = from, to = to)
	end
end

"""
	bibliographie_papyrologique(; folder)

The records of the Bibliographie Papyrologique (BP), from the data of papyri.info, downloaded once into `folder`: a
row per record with its number (`bp`), `type` (as book or article), the surnames of its authors (`author`, joined by
`; `), its `title` and `date`.
"""
function bibliographie_papyrologique(; folder::AbstractString)
	xml_records(xml_files(idp("Biblio", folder))) do doc
		top = EzXML.root(doc)
		(bp = field(doc, "//t:idno[@type='pi']"), type = haskey(top, "type") ? top["type"] : "",
			author = join((EzXML.nodecontent(n) for n in findall("//t:author/t:surname", top, TEI)), "; "),
			title = field(doc, "(//t:title)[1]"), date = field(doc, "(//t:date)[1]"))
	end
end

"""
	tla_demotic(con; folder, table = "demotic")

The intact Demotic sentences of the corpus 18 of the Thesaurus Linguae Aegyptiae (TLA), a file of 7 MB downloaded
once into `folder` from Hugging Face, written to the table `table` of `con`: a row per sentence with its
`transliteration`, German `translation`, `lemmatization`, parts of speech (`UPOS`), and the dates of its text
(`dateNotBefore`, `dateNotAfter`), among other columns. Returns the number of sentences.
"""
function tla_demotic(con; folder::AbstractString, table::AbstractString = "demotic")
	file = kept("https://huggingface.co/datasets/thesaurus-linguae-aegyptiae/tla-demotic-v18-premium/resolve/main/train.jsonl",
		joinpath(folder, "tla-demotic-v18.jsonl"))
	DBInterface.execute(con, """CREATE OR REPLACE TABLE "$(table)" AS SELECT * FROM read_json('$(quoted(file))')""")
	return only(rows(con, """SELECT count(*) AS n FROM "$(table)" """).n)
end

"""
	vesuvius(; folder)

The samples of the open data of the Vesuvius Challenge, the CT scans of the Herculaneum papyri, from its index
(about 85 KB compressed), downloaded again into `folder` each time as it grows: a row per scroll or fragment with its
name (`sample`), `kind`, its numbers of `scans`, `volumes` and `segments`, and the `licences` of its volumes. Each
sample's files are under s3://vesuvius-challenge-open-data/<sample>/, and over https at
https://vesuvius-challenge-open-data.s3.amazonaws.com/index.html.
"""
function vesuvius(; folder::AbstractString)
	path = joinpath(mkpath(folder), "vesuvius-metadata.json")
	compressed = take!(Downloads.download("https://vesuvius-challenge-open-data.s3.amazonaws.com/metadata.min.json", IOBuffer(); headers = [AGENT]))
	write(path, transcode(GzipDecompressor, compressed))
	samples = JSON.parse(read(path, String))["samples"]
	entries(d, key) = (v = get(d, key, nothing); v isa AbstractDict ? v : Dict{String, Any}())
	licence(v) = string(get(entries(entries(v, "properties"), "license"), "name", ""))
	records = map(collect(keys(samples))) do key
		d = samples[key]
		volumes = entries(d, "volumes")
		(sample = String(key), kind = string(get(entries(entries(d, "sample"), "properties"), "type", "")),
			scans = length(entries(d, "scans")), volumes = length(volumes), segments = length(entries(d, "segments")),
			licences = join(sort!(unique(filter(!isempty, [licence(v) for v in values(volumes)]))), "; "))
	end
	return sort!(records; by = r -> (r.kind, r.sample))
end

"""
	icdar2023(; folder)

The data set of the ICDAR 2023 Competition on Detection and Recognition of Greek Letters on Papyri, an archive of
424 MB downloaded once into `folder` from Zenodo; its images stay in it. The letters located and named on the images
are read from its COCO files. Returns `(; images, letters, test_images, test_letters)`: a row per image of the
training set with its file (`image`), `width`, `height` and number of `letters`; a row per letter of the training set
with its `image`, `letter` and box (`x`, `y`, `width`, `height`, in pixels); and the numbers of images and of letters
of the answers of the test set, which give their letters by image ids its list of images does not have.
"""
function icdar2023(; folder::AbstractString)
	archive = kept("https://zenodo.org/records/13825619/files/ICDAR2023_Competition_on_Detection_and_Recognition_of_Greek_Letters_on_Papyri_Dataset.zip?download=1",
		joinpath(folder, "ICDAR2023-Greek-Letters-on-Papyri.zip"))
	reader = ZipReader(Mmap.mmap(archive))
	training = JSON.parse(zip_readentry(reader, entry_ending(reader, "2a.Training/HomerCompTraining.json"), String))
	test = JSON.parse(zip_readentry(reader, entry_ending(reader, "2c.Answers/AnswersToTesting.json"), String))
	names = Dict(c["id"] => string(c["name"]) for c in training["categories"])
	files = Dict(i["id"] => string(i["file_name"]) for i in training["images"])
	found = Dict{Any, Int}()
	foreach(a -> found[a["image_id"]] = get(found, a["image_id"], 0) + 1, training["annotations"])
	images = sort!([(image = string(i["file_name"]), width = Int(i["width"]), height = Int(i["height"]), letters = get(found, i["id"], 0))
		for i in training["images"]]; by = i -> i.image)
	letters = [(image = get(files, a["image_id"], ""), letter = get(names, a["category_id"], ""), x = Float64(a["bbox"][1]),
		y = Float64(a["bbox"][2]), width = Float64(a["bbox"][3]), height = Float64(a["bbox"][4])) for a in training["annotations"]]
	return (; images, letters, test_images = length(test["images"]), test_letters = length(test["annotations"]))
end

"""
	helldate(con; folder, table = "helldate")

Hell-Date, Hellenistic dated papyri, an archive of 2.7 MB downloaded once into `folder` from Zenodo, written to the
table `table` of `con`: a row per image with its file (`image`), its papyrus (`checklist`, `TM`), the years it is
dated to (`year_from`, `year_to`), its `nome`, kind of document (`kind`), the `collection` that holds it and its
`inventory` number, the `licence` of the image and its `link`. Returns the number of images.
"""
function helldate(con; folder::AbstractString, table::AbstractString = "helldate")
	reader = ZipReader(read(kept("https://zenodo.org/records/15830980/files/Hell-Date.zip?download=1", joinpath(folder, "Hell-Date.zip"))))
	data, metadata = (joinpath(folder, "hell-date-$(name)") for name in ("data.csv", "metadata.csv"))
	foreach(((path, name),) -> isfile(path) || write(path, zip_readentry(reader, name)), [(data, "data.csv"), (metadata, "metadata.csv")])
	# data.csv ends its lines in CR LF but its last line in nothing, which DuckDB reads only when it is not strict
	DBInterface.execute(con, """CREATE OR REPLACE TABLE "$(table)" AS
		SELECT m.image_name AS image, m.checklist, m.TM, m."Year post quem" AS year_from, m."Year ante quem" AS year_to,
			m."Production Nome (supposed)" AS nome, m.Function AS kind, d.Collection AS collection, d."Inventory Number" AS inventory,
			d."License name" AS licence, d."Image link" AS link
		FROM read_csv('$(quoted(metadata))', header = true) m
		JOIN read_csv('$(quoted(data))', header = true, strict_mode = false) d USING (image_name) ORDER BY year_from, image""")
	return only(rows(con, """SELECT count(*) AS n FROM "$(table)" """).n)
end

"""
	zenon(; folder)

The Zenon papyri for handwritten text recognition, a PageXML transcription and an image for each papyrus, as
Transkribus drew the lines on the images, downloaded once into `folder` from Zenodo (about 5 MB): a row per papyrus
with its name (`papyrus`), its numbers of `lines` and `words`, its `first_line`, and whether its `image` is there.
"""
function zenon(; folder::AbstractString)
	dir = joinpath(folder, "zenon-htr")
	for f in fetched("https://zenodo.org/api/records/6565706")["files"]
		kept(string(f["links"]["self"]), joinpath(dir, string(f["key"])))
	end
	map(filter(endswith(".xml"), readdir(dir; join = true))) do file
		lines = [EzXML.nodecontent(n) for n in findall("//p:TextLine/p:TextEquiv/p:Unicode", EzXML.root(EzXML.readxml(file)), PAGE)]
		(papyrus = first(splitext(basename(file))), lines = length(lines), words = sum(l -> length(split(l)), lines; init = 0),
			first_line = isempty(lines) ? "" : first(lines), image = isfile(replace(file, r"\.xml$" => ".jpg")))
	end
end
