# What the panels of texts share, those of antique books, newspaper archives and encyclopedias: the query of words
# that tests a text and marks where it has them, the counts by period drawn as bars, the page that shows a text with
# its words marked, and the texts saved with the table of their rows

"""The User-Agent of the requests to the sources of texts: that of a research script, which names no one."""
const RESEARCH_AGENT = "User-Agent" => "research-script/1.0"

"""
	TextQuery

A query of words, as [`text_query`](@ref) reads it. Called on a text, it is true when the text answers it; its
`patterns` are those of its words and phrases, which [`query_hits`](@ref) counts and [`reading_page`](@ref) marks.
"""
struct TextQuery
	words::String
	test::Function
	patterns::Vector{Regex}
end

(query::TextQuery)(text::AbstractString) = query.test(text)
Base.show(io::IO, query::TextQuery) = print(io, "TextQuery(", repr(query.words), ")")

"""
	word_pattern(term; prefix = false, early_modern = false, f_for_s = false)

The pattern of a word or of a phrase in quotes, whole and without regard to capitals: a `*` stands for any ending,
and the words of a phrase may be apart by spaces, line breaks or a hyphen. With `prefix`, it matches the words that
start with it, as a search that finds the forms of a word; with `early_modern`, u and v, i and j, and s and the long
s are the same letter, as the printers of the 16th to 18th centuries used them; with `f_for_s`, an s is also an f,
as OCR reads the long s.
"""
function word_pattern(term::AbstractString; prefix::Bool = false, early_modern::Bool = false, f_for_s::Bool = false)
	letter(c) = early_modern && c in "uv" ? "[uv]" : early_modern && c in "ij" ? "[ij]" : early_modern && c in "sſ" ? "[sſ]" :
		f_for_s && c == 's' ? "[sf]" : c == '*' ? "\\w*" : c in "\\^\$.|?+()[]{}" ? "\\" * c : string(c)
	words = (join(letter(c) for c in lowercase(w)) for w in split(strip(term, '"')))
	return Regex("(?<!\\w)" * join(words, "[\\s\\-]+") * (prefix ? "\\w*" : "(?!\\w)"), "i")
end

"""The words and phrases of a query, in their order, with its brackets and its operators AND, OR and NOT."""
query_tokens(words::AbstractString) = [String(m.match) for m in eachmatch(r"\"[^\"]+\"|\(|\)|[^\s()\"]+", words)]

"""
	query_patterns(words; prefix = false, early_modern = false, f_for_s = false)

The [`word_pattern`](@ref) of each word and phrase of a query, without its brackets and its operators AND, OR and
NOT, nor a `-` before a word: the patterns that mark where a text has the words a search service found it by.
"""
query_patterns(words::AbstractString; kw...) =
	[word_pattern(t; kw...) for t in (strip(t, ['"', '-']) for t in query_tokens(words) if !(t in ("AND", "OR", "NOT", "(", ")"))) if !isempty(t)]

"""
	literal_patterns(terms)

The patterns of the words `terms` as they are written, whole and without regard to capitals: those a search
service says it found, which [`reading_page`](@ref) then marks.
"""
literal_patterns(terms) = [Regex("(?<!\\w)" * replace(t, r"[\\^$.|?*+()\[\]{}]" => s"\\\g<0>") * "(?!\\w)", "i") for t in terms if !isempty(t)]

"""
	text_query(words; prefix = false, early_modern = false, f_for_s = false)

The query of `words` as a [`TextQuery`](@ref): words and phrases in quotes (each a [`word_pattern`](@ref), with a `*`
for any ending), joined by AND (also when nothing joins them), OR and NOT, and grouped by brackets. A query with no
words is true of every text. Throws an error when the brackets do not close or the words end too soon.
"""
function text_query(words::AbstractString; prefix::Bool = false, early_modern::Bool = false, f_for_s::Bool = false)
	words = String(strip(words))
	tokens = query_tokens(words)
	patterns = Regex[]
	isempty(tokens) && return TextQuery(words, _ -> true, patterns)
	at = Ref(1)
	next_token() = at[] <= length(tokens) ? tokens[at[]] : nothing
	take_token() = (at[] += 1; tokens[at[] - 1])
	function term(token)
		r = word_pattern(token; prefix, early_modern, f_for_s)
		push!(patterns, r)
		return text -> occursin(r, text)
	end
	function either()
		test = both()
		while next_token() == "OR"
			take_token()
			a, b = test, both()
			test = text -> a(text) || b(text)
		end
		return test
	end
	function both()
		test = negated()
		while !(next_token() in (nothing, "OR", ")"))
			next_token() == "AND" && take_token()
			a, b = test, negated()
			test = text -> a(text) && b(text)
		end
		return test
	end
	function negated()
		next_token() == "NOT" || return single()
		take_token()
		a = negated()
		return text -> !a(text)
	end
	function single()
		next_token() === nothing && error("The words end too soon: ", words)
		if next_token() == "("
			take_token()
			test = either()
			next_token() == ")" || error("A bracket is not closed in ", words)
			take_token()
			return test
		end
		return term(take_token())
	end
	test = either()
	at[] <= length(tokens) && error("The words have a bracket too many: ", words)
	return TextQuery(words, test, patterns)
end

"""
	query_hits(query, text)

The number of times `text` has the words of `query` (a [`TextQuery`](@ref), or patterns): the matches of all its
patterns.
"""
query_hits(patterns::AbstractVector{Regex}, text::AbstractString) = sum((count(p, text) for p in patterns); init = 0)
query_hits(query::TextQuery, text::AbstractString) = query_hits(query.patterns, text)

"""
	period_counts(counts, from, to; each = nothing)

The values of `counts` (pairs `year => number`, or the years themselves, one for each thing counted) summed by
period from `from` to `to`: each year, or each decade over more than 60 years, or each `each` years when it is
given; as pairs `"1863" => n`, `"1860s" => n` or `"1775–1799" => n`, periods with none included.
"""
function period_counts(counts::AbstractDict, from::Integer, to::Integer; each::Union{Integer, Nothing} = nothing)
	each = something(each, to - from > 60 ? 10 : 1)
	label(y) = each == 1 ? string(y) : each == 10 ? "$(y)s" : "$(y)–$(y + each - 1)"
	return [label(y) => sum((get(counts, x, 0) for x in max(y, from):min(y + each - 1, to)); init = 0) for y in fld(from, each) * each:each:to]
end
period_counts(years::AbstractVector, from::Integer, to::Integer; kw...) = period_counts(Dict(tally(skipmissing(years))), from, to; kw...)

"""
	print_bars([io], counts; width = 40)

The pairs `label => number` of `counts`, a line each, with a bar as long as the number, the largest `width`
characters long; those with none before the first with some and after the last are left out.
"""
function print_bars(io::IO, counts; width::Integer = 40)
	some = findall(c -> last(c) > 0, counts)
	isempty(some) && return
	counts = counts[first(some):last(some)]
	widest = max(maximum(last, counts), 1)
	labels = maximum(c -> length(string(first(c))), counts)
	for (label, n) in counts
		println(io, rpad(string(label), labels + 1), lpad(n, 9), " ", repeat("█", round(Int, width * n / widest)))
	end
end
print_bars(counts; kw...) = print_bars(stdout, counts; kw...)

"""
	ranked(rows, order; at_most = length(rows), date = :year)

The first `at_most` of `rows` in `order`, numbered from 1 in the column `number`: "relevance", the most hits first
(the column `hits`); "oldest" or "newest", by the column `date`, those without a date last; anything else, as they
are.
"""
function ranked(rows, order::AbstractString; at_most::Integer = length(rows), date::Symbol = :year)
	dated(r) = (d = getproperty(r, date); d === nothing || ismissing(d) ? nothing : d)
	sorted = order == "relevance" ? sort(rows; by = r -> -r.hits) :
		order in ("oldest", "newest") ? [sort(filter(r -> dated(r) !== nothing, rows); by = dated, rev = order == "newest"); filter(r -> dated(r) === nothing, rows)] :
		rows
	return [merge((number = i,), r) for (i, r) in enumerate(first(sorted, min(at_most, length(sorted))))]
end

"""
	without(rows, columns...)

The rows without the `columns`, as those of a text, too long to show in a table.
"""
without(rows, columns::Symbol...) = [Base.structdiff(r, NamedTuple{columns}) for r in rows]

"""The HTML of a text: its `&`, `<`, `>` and `"` written as entities."""
escaped_html(s::AbstractString) = replace(s, "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", "\"" => "&quot;")

"""The HTML of a text with the matches of `patterns` marked, each found on the text before it is written as HTML."""
function marked_html(s::AbstractString, patterns)
	# each match from its first character to its last, whose bytes may be more than one, as in Cyrillic or Greek
	spans = sort!(unique(m.offset:prevind(s, m.offset + ncodeunits(m.match)) for p in patterns for m in eachmatch(p, s)); by = first)
	out, last_end = IOBuffer(), 0
	for r in spans
		first(r) <= last_end && continue
		print(out, escaped_html(s[nextind(s, last_end):prevind(s, first(r))]), "<mark>", escaped_html(s[first(r):last(r)]), "</mark>")
		last_end = last(r)
	end
	print(out, escaped_html(s[nextind(s, last_end):end]))
	return String(take!(out))
end

const READING_CSS = "body{font:16px/1.6 Georgia,serif;max-width:46em;margin:2em auto;padding:0 1em}p.meta,p.passages{font:14px sans-serif;color:#666}" *
	"p.passages a{margin-right:.5em}h3{font:bold 14px sans-serif;color:#666;border-top:1px solid #ccc;padding-top:1em}mark{background:#f5d76e}"

"""
	reading_page(title, paragraphs; marks = Regex[], meta = "", link = nothing, passages = true, mark_title = false, language = "", file)

Writes the text `paragraphs` as a page to read in Pollis's browser, with the matches of the patterns `marks` marked
(those of a [`TextQuery`](@ref), [`query_patterns`](@ref) or [`literal_patterns`](@ref)): the `title`, marked too
with `mark_title`; a line `meta` about the text, followed by the `link` (`text => address`) to it at its source;
with `passages`, a line of numbered links to the paragraphs that have the words; and the paragraphs. A text in parts
(an issue's pages, say) is given as pairs `heading => paragraphs`. Returns `(file, passages)`: the file of the page,
in `tempdir()` unless `file` is given, and the numbers of the paragraphs that have the words.
"""
function reading_page(title::AbstractString, paragraphs::AbstractVector; marks = Regex[], meta::AbstractString = "",
		link::Union{Pair, Nothing} = nothing, passages::Bool = true, mark_title::Bool = false, language::AbstractString = "",
		file::AbstractString = joinpath(tempdir(), "reading-page.html"))
	parts = eltype(paragraphs) <: Pair ? paragraphs : ["" => paragraphs]
	body, found, k = IOBuffer(), Int[], 0
	for (heading, part) in parts
		isempty(heading) || print(body, "<h3>", escaped_html(heading), "</h3>\n")
		for p in part
			isempty(strip(p)) && continue
			k += 1
			any(r -> occursin(r, p), marks) && push!(found, k)
			print(body, "<p id=\"p$k\">", marked_html(p, marks), "</p>\n")
		end
	end
	links = join(("<a href=\"#p$i\">$n</a>" for (n, i) in enumerate(first(found, 300))), "")
	write(file, """<!doctype html><html$(isempty(language) ? "" : " lang=\"$language\"")><head><meta charset="utf-8"><title>$(escaped_html(title))</title>
		<style>$READING_CSS</style></head><body><h2>$(mark_title ? marked_html(title, marks) : escaped_html(title))</h2>
		<p class="meta">$(escaped_html(meta))$(link === nothing ? "" : "$(isempty(meta) ? "" : " · ")<a href=\"$(escaped_html(last(link)))\">$(escaped_html(first(link)))</a>")</p>
		$(passages ? "<p class=\"passages\">$(length(found)) passages have the words$(isempty(found) ? "" : ": ") $links</p>" : "")
		$(String(take!(body)))</body></html>""")
	return (file = file, passages = found)
end

"""
	plain_name(text, at_most = 60)

A name for a file or folder from `text`: its letters and digits in lower case, the rest as `-`, at most `at_most`
characters long.
"""
plain_name(text::AbstractString, at_most::Integer = 60) = first(strip(replace(lowercase(text), r"[^\p{L}\p{N}]+" => "-"), '-'), at_most)

"""
	write_table(file, rows, columns = all but :text)

The `columns` of `rows` written to `file` as CSV, a value in quotes each, a `missing` or `nothing` as an empty one.
"""
function write_table(file::AbstractString, rows, columns = isempty(rows) ? () : filter(!=(:text), keys(first(rows))))
	quoted(value) = "\"" * replace(string(something(coalesce(value, ""), "")), "\"" => "\"\"") * "\""
	open(file, "w") do io
		println(io, join(columns, ","))
		foreach(r -> println(io, join((quoted(getproperty(r, c)) for c in columns), ",")), rows)
	end
	return file
end

"""
	save_texts(folder, rows; count = length(rows), name, header, text = r -> r.text, table = "texts.csv", columns, pause = 0)

The texts of the first `count` of `rows` saved in `folder`, a file each, and the table of all the rows: a text's
file is named by the row's `number` and `name(row)`, and starts with the lines `header(row)` (those not empty), then
the text `text(row)`. A file saved before is kept, so that running it again saves only the texts that did not come:
those whose `text` throws an error or is empty, listed as `missed`. `pause` seconds pass after each text that is
fetched. The table, `table`, has the `columns` of the rows, all but `text` by default. Returns `(folder, saved,
missed)`.
"""
function save_texts(folder::AbstractString, rows; count::Integer = length(rows), name::Function, header::Function, text::Function = r -> r.text,
		table::AbstractString = "texts.csv", columns = isempty(rows) ? () : filter(!=(:text), keys(first(rows))), pause::Real = 0)
	mkpath(folder)
	saving = first(rows, min(count, length(rows)))
	missed = Int[]
	for r in saving
		file = joinpath(folder, lpad(r.number, 5, '0') * "-" * name(r) * ".txt")
		isfile(file) && continue
		body = try
			text(r)
		catch e
			e isa InterruptException && rethrow()
			""
		end
		isempty(body) && (push!(missed, r.number); continue)
		write(file, join(filter(!isempty, string.(header(r))), "\n"), "\n\n", body, "\n")
		pause > 0 && sleep(pause)
	end
	write_table(joinpath(folder, table), rows, columns)
	return (folder = folder, saved = length(saving) - length(missed), missed = missed)
end

"""A text written for a URL: its letters, digits and `-_.~` as they are, every other byte as `%XX`."""
percent_encoded(text::AbstractString) = join(isascii(c) && (isletter(c) || isdigit(c) || c in "-_.~") ? string(c) :
	join("%" * uppercase(string(b; base = 16, pad = 2)) for b in codeunits(string(c))) for c in text)

"""The query string of the pairs `parameters`, each key and value written for a URL."""
query_string(parameters) = join(("$(percent_encoded(string(k)))=$(percent_encoded(string(v)))" for (k, v) in parameters), "&")

"""A number of bytes as MB, or as GB from `gigabytes` bytes on."""
size_text(bytes::Real; gigabytes::Real = 1e9) = bytes < gigabytes ? "$(round(bytes / 1e6; digits = 1)) MB" : "$(round(bytes / 1e9; digits = 2)) GB"

"""The text at `url`, read without keeping it, given up after `timeout` seconds."""
fetched_text(url::AbstractString; headers = [RESEARCH_AGENT], timeout::Real = 60) =
	String(take!(Downloads.download(url, IOBuffer(); headers, timeout)))

"""
The answer of a request to `url`, read also when it is an error, and the response: the answer is the body as text,
`(body, status, headers)`, the headers' names in lower case.
"""
function answered(url::AbstractString; headers = [RESEARCH_AGENT], timeout::Real = 120, method::AbstractString = "GET")
	buffer = IOBuffer()
	response = Downloads.request(url; output = buffer, headers, timeout, method, throw = false)
	response isa Downloads.Response || error(url, ": ", response.message)
	return (body = String(take!(buffer)), status = response.status, headers = Dict(lowercase(k) => v for (k, v) in response.headers))
end

"""The rows of a CSV text, fields apart by commas, those in quotes with commas, line breaks and quotes written twice in them."""
function csv_rows(text::AbstractString)
	rows, row, field, in_quotes = Vector{String}[], String[], IOBuffer(), false
	state = iterate(text)
	while state !== nothing
		c, k = state
		state = iterate(text, k)
		if in_quotes && c == '"'
			if state !== nothing && first(state) == '"'
				print(field, '"')
				state = iterate(text, last(state))
			else
				in_quotes = false
			end
		elseif in_quotes || !(c in ",\"\n\r")
			print(field, c)
		elseif c == '"'
			in_quotes = true
		elseif c == ','
			push!(row, String(take!(field)))
		elseif c == '\n'
			push!(row, String(take!(field)))
			push!(rows, row)
			row = String[]
		end
	end
	(isempty(row) && bytesavailable(field) == 0) ||(push!(row, String(take!(field))); push!(rows, row))
	return rows
end

"""
The entries of the zip archive `file` written under `dir`, at their paths in it; an entry whose path leaves `dir`
is left out.
"""
function unzipped(file::AbstractString, dir::AbstractString)
	reader = ZipReader(Mmap.mmap(file))
	for name in zip_names(reader)
		(endswith(name, "/") || startswith(name, "/") || occursin("..", name) || startswith(name, "__MACOSX")) && continue
		path = joinpath(dir, name)
		mkpath(dirname(path))
		write(path, zip_readentry(reader, name))
	end
	return dir
end
