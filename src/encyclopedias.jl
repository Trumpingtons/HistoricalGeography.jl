# The texts of encyclopedias: the Naturalis Historia of Pliny the Elder (the Perseus Digital Library), the Etymologiae
# of Isidore of Seville (LacusCurtius), the Yongle Encyclopedia (Chinese Wikisource), the Cyclopaedia of Ephraim
# Chambers (the Internet Archive) and the Encyclopédie of Diderot and d'Alembert (ARTFL), each read as a table of its
# parts, chapters, sections, pages, entries or articles

const PLINY_BOOKS = ["Preface and Contents", "The Universe", "Geography: Spain, Gaul, Italy", "Geography: Greece and Northern Europe",
	"Geography: Africa and the Near East", "Geography: Asia", "Man", "Land Animals", "Sea Creatures", "Birds", "Insects",
	"Exotic Trees", "Exotic Trees and Plants", "Vines and Wine", "Fruit Trees", "Forest Trees", "Cultivated Trees", "Grain and Agriculture",
	"Flax and Gardens", "Remedies from Garden Plants", "Flowers and Garlands", "Remedies from Plants", "Remedies from Cultivated Trees",
	"Remedies from Forest Trees", "Wild Plants", "Remedies from Plants", "Remedies from Plants", "Remedies from Man and Animals",
	"Remedies from Animals", "Magic and Remedies from Animals", "Remedies from Waters", "Remedies from Sea Creatures", "Gold and Silver",
	"Copper, Iron and Lead", "Painting and Colours", "Stones and Building", "Gems"]

"""
	pliny_book_title(book)

The subject of a book of the Naturalis Historia, 1 to 37, from Pliny's own table of contents in book 1.
"""
pliny_book_title(book::Integer) = get(PLINY_BOOKS, book, "Book $book")

"""The entities of an older TEI by which the English text names its characters, written out before it is read."""
const PLINY_ENTITIES = Dict("aelig" => "æ", "AElig" => "Æ", "oelig" => "œ", "OElig" => "Œ", "mdash" => "—", "ndash" => "–", "eacute" => "é",
	"egrave" => "è", "ecirc" => "ê", "euml" => "ë", "Euml" => "Ë", "aacute" => "á", "agrave" => "à", "acirc" => "â", "auml" => "ä",
	"iacute" => "í", "icirc" => "î", "iuml" => "ï", "Iuml" => "Ï", "ograve" => "ò", "ocirc" => "ô", "ouml" => "ö", "Ouml" => "Ö",
	"uacute" => "ú", "ugrave" => "ù", "ucirc" => "û", "uuml" => "ü", "Uuml" => "Ü", "yuml" => "ÿ", "ccedil" => "ç", "ntilde" => "ñ",
	"emacr" => "ē", "deg" => "°", "prime" => "′", "sect" => "§", "pound" => "£", "cdot" => "·")

pliny_written_out(xml::AbstractString) = replace(replace(xml, r"<!DOCTYPE.*?\]>"s => ""),
	r"&(?<name>[A-Za-z]+);" => m -> m in ("&amp;", "&lt;", "&gt;", "&quot;") ? m : get(PLINY_ENTITIES, m[2:end-1], ""))

"""The text of a part of a TEI, without its notes, page breaks and headings; the notes kept apart in `notes`."""
function tei_text(node, notes = String[])
	out = IOBuffer()
	for child in EzXML.eachnode(node)
		if EzXML.istext(child)
			print(out, EzXML.nodecontent(child))
		elseif EzXML.iselement(child)
			name = EzXML.nodename(child)
			if name == "note"
				push!(notes, replace(strip(EzXML.nodecontent(child)), r"\s+" => " "))
			elseif !(name in ("head", "pb", "milestone", "lb"))
				print(out, tei_text(child, notes))
			end
		end
	end
	return String(take!(out))
end

"""The paragraphs of a part of a TEI, apart by a blank line; the notes kept apart in `notes`."""
tei_paragraphs(node, notes = String[]) = join((replace(strip(tei_text(p, notes)), r"\s+" => " ") for p in findall(".//*[local-name()='p']", node, TEI)), "\n\n")

"""
	pliny_chapters(language; books = 1:37, folder)

The chapters of the books `books` of the Naturalis Historia of Pliny the Elder, from the two texts of the Perseus
Digital Library in TEI (the English of Bostock and Riley, 1855, and the Latin of Mayhoff's Teubner edition),
downloaded once into `folder/naturalishistoria`. With `language` "english", the English chapters, each with the
Latin chapters it gives in brackets in its heading (or the last Latin chapter before it) and their Latin text as
`other`; else the Latin chapters, with the titles and text of the English chapters in them. Each has its `book`,
`book_title`, `chapter`, `latin_chapters`, `title`, `text`, `other`, the `notes` of Bostock and Riley, and its
address on the Perseus Digital Library, `perseus`.
"""
function pliny_chapters(language::AbstractString; books = 1:37, folder::AbstractString)
	texts_folder = mkpath(joinpath(folder, "naturalishistoria"))
	source = "https://raw.githubusercontent.com/PerseusDL/canonical-latinLit/master/data/phi0978/phi001/phi0978.phi001.perseus-"
	for edition in ("eng1", "lat2")
		kept(source * edition * ".xml", joinpath(texts_folder, "$edition.xml"); agent = RESEARCH_AGENT)
	end
	english_doc = EzXML.parsexml(pliny_written_out(read(joinpath(texts_folder, "eng1.xml"), String)))
	latin_doc = EzXML.readxml(joinpath(texts_folder, "lat2.xml"))
	latin = Dict{Tuple{Int, String}, String}()
	for book in findall("//*[local-name()='div'][@subtype='book']", EzXML.root(latin_doc), TEI)
		b = parse(Int, book["n"])
		for chapter in findall("*[local-name()='div'][@subtype='chapter']", book, TEI)
			latin[(b, chapter["n"])] = tei_paragraphs(chapter)
		end
	end
	english = NamedTuple[]
	for book in findall("//div1[@type='book']", EzXML.root(english_doc), TEI)
		b = parse(Int, book["n"])
		current = "1"
		for chapter in findall("div2", book, TEI)
			head = findfirst("head", chapter, TEI)
			heading = head === nothing ? "" : replace(strip(EzXML.nodecontent(head)), r"\s+" => " ")
			in_latin = [String(m[1]) for m in eachmatch(r"\((\d+)\.\)", heading)]
			isempty(in_latin) || (current = last(in_latin))
			notes = String[]
			text = tei_paragraphs(chapter, notes)
			push!(english, (book = b, chapter = chapter["n"], latin_chapters = isempty(in_latin) ? [current] : in_latin,
				title = replace(heading, r"^CHAP\.\s*\d+\.\s*(\(\d+\.\)\s*)*(—|\.)?\s*" => ""), text = text, notes = notes))
		end
	end
	language == "english" && return [(book = e.book, book_title = pliny_book_title(e.book), chapter = e.chapter, latin_chapters = join(e.latin_chapters, ", "),
		title = e.title, text = e.text, other = join((get(latin, (e.book, c), "") for c in e.latin_chapters), "\n\n"), notes = e.notes,
		perseus = "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0137:book=$(e.book):chapter=$(e.chapter)")
		for e in english if e.book in books]
	return [(book = b, book_title = pliny_book_title(b), chapter = c, latin_chapters = c,
		title = join((e.title for e in english if e.book == b && c in e.latin_chapters), "; "), text = t,
		other = join((e.text for e in english if e.book == b && c in e.latin_chapters), "\n\n"), notes = String[],
		perseus = "https://www.perseus.tufts.edu/hopper/text?doc=Perseus:text:1999.02.0138:book=$b:chapter=$c")
		for ((b, c), t) in sort(collect(latin); by = x -> (x[1][1], something(tryparse(Int, x[1][2]), 0))) if b in books]
end

"""
	pliny_page(chapter, marks; language)

Writes a chapter of [`pliny_chapters`](@ref) as a page to read in Pollis's browser: its text in the language
searched, with the matches of the patterns `marks` marked, beside its text in the other language, and the notes of
Bostock and Riley below. Returns the file of the page, in `tempdir()`.
"""
function pliny_page(chapter, marks; language::AbstractString)
	column(text, mark) = join(("<p>$(mark ? marked_html(p, marks) : escaped_html(p))</p>" for p in split(text, "\n\n") if !isempty(strip(p))), "\n")
	searched, other = language == "english" ? ("English", "Latin") : ("Latin", "English")
	page = joinpath(tempdir(), "naturalishistoria-chapter.html")
	write(page, """<!doctype html><html><head><meta charset="utf-8"><title>Pliny, Naturalis Historia $(chapter.book).$(chapter.chapter)</title>
		<style>body{font:16px/1.6 Georgia,serif;max-width:72em;margin:2em auto;padding:0 1em}p.meta,h3{font:14px sans-serif;color:#666}
		.columns{display:grid;grid-template-columns:1fr 1fr;gap:2em}.notes{font-size:14px;color:#444}mark{background:#f5d76e}</style></head><body>
		<h2>$(marked_html(chapter.title, marks))</h2>
		<p class="meta">Book $(chapter.book), $(escaped_html(chapter.book_title)) · chapter $(escaped_html(chapter.chapter))$(language == "english" ? " (Latin chapter $(chapter.latin_chapters))" : "")
		· <a href="$(chapter.perseus)">The chapter on the Perseus Digital Library</a></p>
		<div class="columns"><div><h3>$searched</h3>$(column(chapter.text, true))</div><div><h3>$other</h3>$(column(chapter.other, false))</div></div>
		$(isempty(chapter.notes) ? "" : "<h3>Notes of Bostock and Riley</h3><div class=\"notes\">" * join(("<p>$(escaped_html(n))</p>" for n in chapter.notes), "\n") * "</div>")
		</body></html>""")
	return page
end

const ISIDORE_BOOKS = ["Grammar", "Rhetoric and Dialectic", "Mathematics", "Medicine", "Laws and Times",
	"Books and Ecclesiastical Offices", "God, Angels and Saints", "The Church and Sects", "Languages, Nations, Kingdoms, Armies, Citizens, Kinship",
	"Words", "Man and Portents", "Animals", "The World and its Parts", "The Earth and its Parts", "Buildings and Fields", "Stones and Metals",
	"Agriculture", "War and Games", "Ships, Buildings and Clothing", "Provisions and Tools"]

"""
	isidore_book_title(book)

The subject of a book of the Etymologiae, 1 to 20, from Lindsay's titles.
"""
isidore_book_title(book::Integer) = get(ISIDORE_BOOKS, book, "Book $book")

isidore_page_url(b::Integer) = "https://penelope.uchicago.edu/Thayer/L/Roman/Texts/Isidore/$b%2A.html"

"""
The text of a passage of a page of LacusCurtius: without its comments and tags (whose quoted attributes, Thayer's
notes, may hold a >), its entities written out, without invisible characters, and its spaces as one, none before a
stop or after a bracket.
"""
function lacuscurtius_text(html::AbstractString)
	s = replace(html, r"<!--.*?-->"s => " ", r"<(?:[^>\"']|\"[^\"]*\"|'[^']*')*>"s => " ")
	s = replace(s, r"&#x(?<h>[0-9A-Fa-f]+);" => e -> string(Char(parse(Int, e[4:end-1]; base = 16))))
	s = replace(s, r"&#(?<d>\d+);" => e -> string(Char(parse(Int, e[3:end-1]))))
	s = replace(s, "&nbsp;" => " ", "&shy;" => "", "&amp;" => "&", "&lt;" => "<", "&gt;" => ">", "&quot;" => "\"", "&mdash;" => "—", "&ndash;" => "–")
	return String(strip(replace(replace(s, r"\p{Cf}" => "", r"\s+" => " "), r"\s+(?=[.,;:?!)])" => "", r"(?<=\()\s+" => "")))
end

"""
The sections of a book of the Etymologiae, by its chapter anchors and section anchors: a section's text runs to the
next anchor, and the first section of a chapter is the text before its second; the text of the page ends at the
table after the last section.
"""
function isidore_book(b::Integer, file::AbstractString)
	html = read(file, String)
	found = NamedTuple[]
	last_section = findlast("CLASS=\"sec\"", html)
	last_section === nothing && return found
	start = something(findfirst("<A CLASS=\"chapter\"", html), findlast("</H1>", html))
	stop = something(findnext("<TABLE", html, last(last_section)), lastindex(html):lastindex(html))
	text = html[first(start):prevind(html, first(stop))]
	anchors = collect(eachmatch(r"<A CLASS=\"(?<kind>chapter|sec)\" NAME=\"(?:(?<c>\d+)\.)?(?<n>\d+)\">\s*\d+\s*</A>"s, text))
	chapter, chapter_title, number, from_index = "", "", "1", 1
	title_end = 0  # where the title of the chapter ends, which its first section leaves out
	function add(upto)
		# the text, without the stop after the chapter's title and the marks º of Thayer's notes
		t = replace(lacuscurtius_text(text[max(from_index, title_end + 1):prevind(text, upto)]), r"^[.:]\s*" => "", r"\s*º" => "")
		isempty(t) || push!(found, (book = b, book_title = isidore_book_title(b), chapter = chapter, chapter_title = chapter_title,
			section = number, text = t, link = isidore_page_url(b) * "#" * (isempty(chapter) ? number : "$chapter.$number")))
	end
	for a in anchors
		add(a.offset)
		if a[:kind] == "chapter"
			chapter, number = String(a[:n]), "1"
			title = match(r"<SPAN CLASS=\"smallcaps\">(?<t>.*?)</SPAN>"s, text, a.offset)
			has_title = title !== nothing && title.offset < a.offset + 400
			chapter_title = has_title ? lacuscurtius_text(title[:t]) : ""
			title_end = has_title ? title.offset + ncodeunits(title.match) - 1 : 0
		else
			number = String(a[:n])
		end
		from_index = a.offset + ncodeunits(a.match)
	end
	add(ncodeunits(text) + 1)
	return found
end

"""
	isidore_sections(books = 1:20; folder)

The sections of the books `books` of the Etymologiae of Isidore of Seville, in Lindsay's Latin text (1911) as Bill
Thayer's LacusCurtius gives it, a page a book, downloaded once into `folder/etymologiae`, half a second apart: each
with its `book`, `book_title`, `chapter`, `chapter_title`, `section`, `text`, and its address on LacusCurtius, `link`.
"""
function isidore_sections(books = 1:20; folder::AbstractString)
	texts_folder = mkpath(joinpath(folder, "etymologiae"))
	for b in 1:20
		file = joinpath(texts_folder, "$b.html")
		isfile(file) && continue
		kept(isidore_page_url(b), file; agent = RESEARCH_AGENT)
		sleep(0.5)  # a pause between requests
	end
	return reduce(vcat, (isidore_book(b, joinpath(texts_folder, "$b.html")) for b in books); init = NamedTuple[])
end

"""
	isidore_page(section, sections, marks)

Writes the chapter of a section of [`isidore_sections`](@ref) as a page to read in Pollis's browser: its sections
numbered, the section given set apart, and the matches of the patterns `marks` marked. Returns the file of the page,
in `tempdir()`.
"""
function isidore_page(chosen, sections, marks)
	in_chapter = [s for s in sections if s.book == chosen.book && s.chapter == chosen.chapter]
	heading = "Etymologiae $(chosen.book)" * (isempty(chosen.chapter) ? "" : ".$(chosen.chapter)") * ".$(chosen.section)"
	page = joinpath(tempdir(), "etymologiae-section.html")
	write(page, """<!doctype html><html><head><meta charset="utf-8"><title>$(escaped_html(heading))</title>
		<style>body{font:16px/1.6 Georgia,serif;max-width:46em;margin:2em auto;padding:0 1em}p.meta{font:14px sans-serif;color:#666}
		p.found{background:rgba(232,163,61,.12);padding:.3em .6em}sup{color:#888;font:12px sans-serif}mark{background:#f5d76e}</style></head><body>
		<h2>$(escaped_html(chosen.chapter_title))</h2>
		<p class="meta">Book $(chosen.book), $(escaped_html(chosen.book_title))$(isempty(chosen.chapter) ? "" : ", chapter $(chosen.chapter)") · section $(chosen.section)
		· <a href="$(chosen.link)">The section on LacusCurtius</a></p>
		$(join(("<p$(s.section == chosen.section ? " class=\"found\"" : "")><sup>$(s.section)</sup> $(marked_html(s.text, marks))</p>" for s in in_chapter), "\n"))
		</body></html>""")
	return page
end

"""The address of a page of Chinese Wikisource."""
zh_wikisource_link(title::AbstractString) = "https://zh.wikisource.org/wiki/" * percent_encoded(replace(title, " " => "_"))

"""
	yongle_juan_address(juan)

The address of the page of a juan of the Yongle Encyclopedia on Chinese Wikisource, with the pages of its scan.
"""
yongle_juan_address(juan::Integer) = zh_wikisource_link("永樂大典/卷" * lpad(juan, 5, '0'))

"""
	yongle_search(words; juan = "")

The pages of the scans of the Yongle Encyclopedia on Chinese Wikisource whose text has `words`, in the juan `juan`
when it is given, the most relevant first, 500 a request, up to the 10,000 Wikisource lists: each with its `rank`, its
`juan`, its `page` in the scan of the juan, and its `title` on Wikisource. Returns `(total, pages)`.
"""
function yongle_search(words::AbstractString; juan::AbstractString = "")
	prefix = "Page:永樂大典" * (isempty(juan) ? "" : lpad(juan, 5, '0') * ".pdf/")
	pages = NamedTuple[]
	total, offset = 0, 0
	while true
		answer = mediawiki("zh.wikisource.org", ["action" => "query", "list" => "search", "srsearch" => "$words prefix:$prefix", "srnamespace" => 104,
			"srprop" => "", "srlimit" => 500, "sroffset" => offset])
		total = answer["query"]["searchinfo"]["totalhits"]
		for r in answer["query"]["search"]
			m = match(r"永樂大典(?<juan>\d+)\.pdf/(?<page>\d+)", r["title"])
			m === nothing || push!(pages, (rank = length(pages) + 1, juan = parse(Int, m[:juan]), page = parse(Int, m[:page]), title = r["title"]))
		end
		haskey(answer, "continue") || break
		offset = answer["continue"]["sroffset"]
		offset >= 10000 && break
	end
	return (total = total, pages = identity.(pages))
end

"""The words of a query as typed, without its operators, brackets and quotes, for counting and marking them in Chinese, which has no spaces."""
yongle_terms(words::AbstractString) = filter(t -> !(t in ("AND", "OR", "NOT")) && !isempty(t), [String(strip(t, ['"', '-'])) for t in split(replace(words, r"[()]" => " "))])

"""
The wikitext of a page as text: without its header and tags, the double-line notes in brackets 〔〕 and joined when
they follow each other, the other templates (the scans' images) left out, from the innermost out.
"""
function yongle_text(wikitext::AbstractString)
	template(t) = (m = match(r"^\{\{\s*(?<name>[^{}|]*?)\s*(?:\|(?<arguments>[^{}]*))?\}\}$"s, t);
		m[:name] == "雙行註文" ? "〔" * replace(something(m[:arguments], ""), "|" => "") * "〕" : "")
	s = replace(wikitext, r"<noinclude>.*?</noinclude>"s => "", r"<[^>]*>" => "")
	while occursin(r"\{\{[^{}]*\}\}", s)
		s = replace(s, r"\{\{[^{}]*\}\}" => template)
	end
	return String(strip(replace(s, r"〕\s*〔" => "", r"\n\s*\n+" => "\n")))
end

"""
	yongle_texts(pages, words)

The texts of `pages` (those of [`yongle_search`](@ref)), 50 a request to Chinese Wikisource, numbered in their
order: each with its `juan`, `page`, the `heading` of its juan when the page has it, its `hits` (the times it has the
words of the query as typed), its `rank` in the search, its `text`, the double-line notes in brackets 〔〕, and its
address on `wikisource`.
"""
function yongle_texts(pages, words::AbstractString)
	terms = yongle_terms(words)
	texts = Dict{String, String}()
	for batch in Iterators.partition(pages, 50)
		answer = mediawiki("zh.wikisource.org", ["action" => "query", "prop" => "revisions", "rvprop" => "content", "rvslots" => "main",
			"titles" => join((p.title for p in batch), "|")])
		for p in answer["query"]["pages"]
			haskey(p, "revisions") && (texts[p["title"]] = yongle_text(p["revisions"][1]["slots"]["main"]["content"]))
		end
	end
	return map(enumerate(pages)) do (i, p)
		text = get(texts, p.title, "")
		heading = match(r"永樂大典卷之[^\s　]+(?:[\s　]+[^\s　〔]+)?", text)
		(number = i, juan = p.juan, page = p.page, heading = heading === nothing ? "" : String(heading.match),
			hits = sum((count(t, text) for t in terms); init = 0), rank = p.rank, text = text, wikisource = zh_wikisource_link(p.title))
	end
end

"""
	yongle_page(page, words)

Writes a page of [`yongle_texts`](@ref) as a page to read in Pollis's browser: a paragraph each line, the double-line
notes smaller, and the words of the query as typed marked. Returns the file of the page, in `tempdir()`.
"""
function yongle_page(chosen, words::AbstractString)
	terms = yongle_terms(words)
	marked(s) = isempty(terms) ? escaped_html(s) : replace(escaped_html(s),
		Regex(join((replace(t, r"[\\^$.|?*+()\[\]{}]" => s"\\\g<0>") for t in terms), "|")) => s"<mark>\g<0></mark>")
	paragraphs = join(("<p>" * replace(marked(line), r"〔(?<note>[^〕]*)〕" => s"<small>\g<note></small>") * "</p>" for line in split(chosen.text, "\n")), "\n")
	page = joinpath(tempdir(), "yongle-page.html")
	write(page, """<!doctype html><html lang="zh-Hant"><head><meta charset="utf-8"><title>永樂大典 $(chosen.juan)</title>
		<style>body{font:18px/1.9 "Songti TC","Noto Serif TC",serif;max-width:46em;margin:2em auto;padding:0 1em}p.meta{font:14px sans-serif;color:#666}
		small{font-size:.8em;color:#555}mark{background:#f5d76e}</style></head><body><h2>$(escaped_html(chosen.heading))</h2>
		<p class="meta">Juan $(chosen.juan), page $(chosen.page) of the scan · <a href="$(chosen.wikisource)">The page on Wikisource</a></p>
		$paragraphs</body></html>""")
	return page
end

"""
The two volumes of Chambers's Cyclopaedia (1728) in the scans of the Getty Research Institute at the Internet
Archive, each with the first letters of its entries, I and J one letter in 1728.
"""
const CHAMBERS_VOLUMES = [(volume = 1, item = "gri_33125011113764", letters = "A–H", first_letters = "A"),
	(volume = 2, item = "gri_33125011134307", letters = "I–Z", first_letters = "IJ")]

"""
	chambers_entries(; folder)

The entries of the Cyclopaedia of Ephraim Chambers (1728), from the text that the Internet Archive read from the
scans of the Getty Research Institute, its two volumes downloaded once into `folder/cyclopaedia`: a paragraph starts
an entry when it opens with a headword in capitals and a comma, and the paragraphs after it belong to it. Each with
its `volume`, `headword`, the `field` it names (in Anatomy, among the Antients), the `leaf` of the scan where it
starts, its `text` and the address of its page at the Internet Archive, `link`.
"""
function chambers_entries(; folder::AbstractString)
	texts_folder = mkpath(joinpath(folder, "cyclopaedia"))
	for v in CHAMBERS_VOLUMES, suffix in ("_hocr_searchtext.txt.gz", "_hocr_pageindex.json.gz")
		kept("https://archive.org/download/$(v.item)/$(v.item)$suffix", joinpath(texts_folder, v.item * suffix); agent = RESEARCH_AGENT)
	end
	read_gzip(file) = String(transcode(GzipDecompressor, read(file)))
	headword = r"^(?<head>[A-Z][A-Z'\-]+(?:[ \-][A-Z][A-Z'\-]+)*) ?,"
	field_of = r"^[^,]*,\s*(?:or [^,]*,\s*)?(?:in|among)\s+(?:the\s+)?(?:antient\s+|ancient\s+)?(?<field>[A-Z][a-z]+)"
	cleaned(s) = replace(replace(s, r"(?<=\p{Ll})- (?=\p{Ll})" => ""), r"\s+" => " ")  # words joined across lines, one space
	entries = NamedTuple[]
	for v in CHAMBERS_VOLUMES
		text = read_gzip(joinpath(texts_folder, v.item * "_hocr_searchtext.txt.gz"))
		page_starts = [p[1] for p in JSON.parse(read_gzip(joinpath(texts_folder, v.item * "_hocr_pageindex.json.gz")))]
		head, field, leaf, paragraphs, offset, started = "(Front Matter)", "", 0, String[], 0, false
		add() = isempty(paragraphs) || push!(entries, (volume = v.volume, headword = String(head), field = String(field), leaf = leaf,
			text = join(paragraphs, "\n"), link = "https://archive.org/details/$(v.item)/page/n$leaf"))
		for line in split(text, '\n')
			m = match(headword, line)
			started = started || (m !== nothing && first(m[:head]) in v.first_letters && length(m[:head]) > 2)
			if started && m !== nothing
				add()
				f = match(field_of, line)
				head, field, leaf, paragraphs = m[:head], f === nothing ? "" : f[:field], searchsortedlast(page_starts, offset) - 1, String[]
			end
			isempty(strip(line)) || push!(paragraphs, cleaned(line))
			offset += length(line) + 1
		end
		add()
	end
	return identity.(entries)
end

const ARTFL = "https://artflsrv04.uchicago.edu/philologic5/encyclopedie0226"

"""A request to ARTFL's PhiloLogic service, with a pause of half a second before it."""
function philologic(report::AbstractString, parameters)
	sleep(0.5)
	answer = JSON.parse(answered("$ARTFL/reports/$report.py?" * query_string([["report" => report, "format" => "json"]; parameters])).body)
	haskey(answer, "title") && occursin("Bad Request", answer["title"]) && error("ARTFL: ", answer["description"])
	return answer
end

"""
	encyclopedie_search(words; class = "", author = "")

The articles of the Encyclopédie of Diderot and d'Alembert that have `words`, from ARTFL's counts of the hits of each
word or phrase by class, broken up by article: words joined by AND (also when nothing joins them), OR and NOT, with
brackets; a phrase, or a word with an apostrophe or a hyphen, as words next to one another; in quotes as written,
with its accents. In the class of knowledge `class` and by the author `author` when they are given. Each article,
in the order of the Encyclopédie, with its `id`, `volume`, `headword`, `author`, `attribution`, `class`,
`machine_class` (ARTFL's), `entry_type`, `hits` (the times it has the words) and its address on `artfl`.
"""
function encyclopedie_search(words::AbstractString; class::AbstractString = "", author::AbstractString = "")
	articles = Dict{String, NamedTuple}()
	hits = Dict{String, Int}()
	function term_articles(token)
		term = strip(token, '"')
		phrase = occursin(r"[\s'’\-]", term)
		filters = [k => v for (k, v) in ("normclass" => class, "kafauth" => author) if !isempty(v)]
		answer = philologic("aggregation", [["q" => startswith(token, '"') ? "\"$term\"" : term, "group_by" => "normclass"];
			phrase ? ["method" => "phrase_ordered", "arg" => 0] : []; filters])
		found_ids = Set{String}()
		for group in get(answer, "results", []), a in group["break_up_field"]
			m = a["metadata_fields"]
			id = m["philo_div1_id"]
			push!(found_ids, id)
			hits[id] = get(hits, id, 0) + a["count"]
			articles[id] = (volume = parse(Int, m["vol"]), headword = string(m["head"]), author = string(something(get(m, "kafauth", ""), "")),
				attribution = string(something(get(m, "attribution", ""), "")), class = string(something(get(m, "normclass", ""), "")),
				machine_class = string(something(get(m, "generatedclass", ""), "")), entry_type = string(something(get(m, "objecttype", ""), "")))
		end
		return found_ids
	end
	# each word or phrase the set of its articles, AND their common articles, OR all of them, and NOT the articles of the
	# words before it without those of the words after it
	tokens = query_tokens(words)
	at = Ref(1)
	next_token() = at[] <= length(tokens) ? tokens[at[]] : nothing
	take_token() = (at[] += 1; tokens[at[] - 1])
	function either()
		a = both()
		while next_token() == "OR"
			take_token()
			b = both()
			(a.negated || b.negated) && error("NOT goes with words joined to it by AND: ", words)
			a = (ids = union(a.ids, b.ids), negated = false)
		end
		return a
	end
	function both()
		a = negated()
		while !(next_token() in (nothing, "OR", ")"))
			next_token() == "AND" && take_token()
			b = negated()
			a = a.negated && b.negated ? (ids = union(a.ids, b.ids), negated = true) : a.negated ? (ids = setdiff(b.ids, a.ids), negated = false) :
				b.negated ? (ids = setdiff(a.ids, b.ids), negated = false) : (ids = intersect(a.ids, b.ids), negated = false)
		end
		return a
	end
	function negated()
		next_token() == "NOT" || return single()
		take_token()
		a = negated()
		return (ids = a.ids, negated = !a.negated)
	end
	function single()
		next_token() === nothing && error("The words end too soon: ", words)
		if next_token() == "("
			take_token()
			a = either()
			next_token() == ")" || error("A bracket is not closed in ", words)
			take_token()
			return a
		end
		return (ids = term_articles(take_token()), negated = false)
	end
	result = either()
	at[] <= length(tokens) && error("The words have a bracket too many: ", words)
	result.negated && error("NOT needs words before it, joined by AND: ", words)
	return sort!([merge((id = id,), articles[id], (hits = hits[id], artfl = "$ARTFL/navigate/" * join(split(id), "/"))) for id in result.ids];
		by = a -> Tuple(parse.(Int, split(a.id))))
end

"""
	encyclopedie_article(id)

The text of an article of the Encyclopédie, by its `id` in [`encyclopedie_search`](@ref), in paragraphs, without
ARTFL's index fields and page images, and the addresses of the `scans` of its pages: `(text, scans)`.
"""
function encyclopedie_article(id::AbstractString)
	answer = philologic("navigation", ["philo_id" => id])
	html = replace(answer["text"], r"<span[^>]*class=\"xml-pb-image\"[^>]*>.*?</span>"s => " ", r"<span[^>]*class=\"xml-index\"[^>]*>(?:</span>)?"s => "")
	paragraphs = [strip(replace(replace(p, r"<[^>]+>"s => "", "&amp;" => "&", "&lt;" => "<", "&gt;" => ">", "&quot;" => "\"", "&nbsp;" => " "),
		r"\s+" => " ")) for p in split(html, r"</?p[^>]*>|<br\s*/?>")]
	images = get(get(answer, "imgs", Dict()), "current_obj_img", [])
	return (text = join(filter(!isempty, paragraphs), "\n"), scans = ["https://artflsrv04.uchicago.edu/images/encyclopedie/" * i for i in images])
end

"""
	encyclopedie_page(article, text, words)

Writes an article of [`encyclopedie_search`](@ref) and its `text` (of [`encyclopedie_article`](@ref)) as a page to
read in Pollis's browser, with the words of the query marked where they are, capitals apart, and accents apart
unless they were in quotes. Returns the file of the page, in `tempdir()`.
"""
function encyclopedie_page(chosen, article, words::AbstractString)
	folded(s) = lowercase(Base.Unicode.normalize(s; stripmark = true))
	terms = [(word = lowercase(strip(t, '"')), exact = startswith(t, '"')) for t in query_tokens(words) if !(t in ("AND", "OR", "NOT", "(", ")"))]
	marks = [(pattern = Regex("\\b" * replace(replace(t.exact ? t.word : folded(t.word), r"[\\^$.|?+()\[\]{}]" => s"\\\g<0>"), "*" => "\\w*",
		r"[\s'’\-]+" => "\\W+") * "\\b"), exact = t.exact) for t in terms]
	# the characters from and to which each match of a pattern runs in a text
	function char_spans(pattern, text)
		offsets = collect(eachindex(text))
		return [(searchsortedfirst(offsets, m.offset), searchsortedlast(offsets, m.offset + ncodeunits(m.match) - 1)) for m in eachmatch(pattern, text)]
	end
	function marked(s)
		f, lower = folded(s), lowercase(s)
		length(f) == length(s) == length(lower) || return escaped_html(s)  # a text whose letters change in number when folded is left unmarked
		spans = sort!(unique(reduce(vcat, (char_spans(m.pattern, m.exact ? lower : f) for m in marks); init = Tuple{Int, Int}[])))
		chars = collect(s)
		out, last_char = IOBuffer(), 0
		for (i, j) in spans
			i <= last_char && continue
			print(out, escaped_html(String(chars[last_char + 1:i - 1])), "<mark>", escaped_html(String(chars[i:j])), "</mark>")
			last_char = j
		end
		print(out, escaped_html(String(chars[last_char + 1:end])))
		return String(take!(out))
	end
	page = joinpath(tempdir(), "encyclopedie-article.html")
	write(page, """<!doctype html><html lang="fr"><head><meta charset="utf-8"><title>$(escaped_html(chosen.headword))</title>
		<style>body{font:16px/1.6 Georgia,serif;max-width:46em;margin:2em auto;padding:0 1em}p.meta{font:14px sans-serif;color:#666}
		mark{background:#f5d76e}</style></head><body><h2>$(escaped_html(chosen.headword))</h2>
		<p class="meta">Encyclopédie, volume $(chosen.volume)$(isempty(chosen.class) ? "" : ", " * escaped_html(chosen.class))$(isempty(chosen.author) ? "" : ", " * escaped_html(chosen.author) * " ($(chosen.attribution))")
		· <a href="$(chosen.artfl)">The article on ARTFL</a>$(isempty(article.scans) ? "" : " · <a href=\"$(first(article.scans))\">The scan of its first page</a>")</p>
		$(join(("<p>" * marked(p) * "</p>" for p in split(article.text, "\n")), "\n"))</body></html>""")
	return page
end
