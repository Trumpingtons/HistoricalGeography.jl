const EARTHDATA = "https://urs.earthdata.nasa.gov"
const EARTHDATA_TOKEN = Ref("")

"""
	earthdata_token()

A token of NASA's Earthdata Login, with which the files of Earthdata are downloaded: `ENV["EARTHDATA_TOKEN"]`
when it is set, otherwise one asked of Earthdata Login with the account of `ENV["EARTHDATA_USERNAME"]` and
`ENV["EARTHDATA_PASSWORD"]` (an existing token of the account, or a new one), kept for the session.

An account is free, at urs.earthdata.nasa.gov. In Pollis, the username and password are set with the key on the
Powered by line of a panel that uses Earthdata, and kept on the user's computer.
"""
function earthdata_token()
	isempty(EARTHDATA_TOKEN[]) || return EARTHDATA_TOKEN[]
	get(ENV, "EARTHDATA_TOKEN", "") == "" || return (EARTHDATA_TOKEN[] = ENV["EARTHDATA_TOKEN"])
	for v in ("EARTHDATA_USERNAME", "EARTHDATA_PASSWORD")
		get(ENV, v, "") == "" && error("NASA's Earthdata needs an account: set ENV[\"EARTHDATA_USERNAME\"] and ENV[\"EARTHDATA_PASSWORD\"] (or ENV[\"EARTHDATA_TOKEN\"]); an account is free at $(EARTHDATA). In Pollis, set them with the key on the Powered by line")
	end
	out = IOBuffer()
	login = base64encode(ENV["EARTHDATA_USERNAME"] * ":" * ENV["EARTHDATA_PASSWORD"])
	r = Downloads.request(EARTHDATA * "/api/users/find_or_create_token"; method = "POST", output = out,
		headers = [AGENT, "Authorization" => "Basic $(login)"], throw = false)
	r isa Downloads.Response || error("Earthdata Login could not be reached: $(r.message)")
	answer = String(take!(out))
	token = match(r"\"access_token\"\s*:\s*\"([^\"]+)\"", answer)
	r.status == 200 && token !== nothing || error("Earthdata Login refused the account of ENV[\"EARTHDATA_USERNAME\"] (HTTP $(r.status)): $(first(answer, 300))")
	return (EARTHDATA_TOKEN[] = token[1])
end

"""The file at `url` of NASA's Earthdata, downloaded once to `path` with a token of [`earthdata_token`](@ref)."""
earthdata_file(url::AbstractString, path::AbstractString) =
	isfile(path) ? path : kept(url, path; headers = ["Authorization" => "Bearer $(earthdata_token())"])
