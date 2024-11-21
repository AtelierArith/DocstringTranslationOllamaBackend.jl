module DocstringTranslationOllamaBackend

using Base.Docs: DocStr, Binding
using REPL: find_readme
import REPL
using Markdown

using HTTP
using JSON3
using DataFrames
using ProgressMeter

const OLLAMA_BASE_URL = get(ENV, "OLLAMA_BASE_URL", "http://localhost:11434")
const DEFAULT_MODEL = Ref{String}("gemma2:9b")
const DEFAULT_LANG = Ref{String}("English")

export @switchlang!, @revertlang!
export listmodel, switchmodel!

function delete_model!(model)
    try
        res = HTTP.delete(
            joinpath(OLLAMA_BASE_URL, "api", "delete"),
            Dict("Content-Type" => "application/json", "Accept" => "application/json"),
            Dict("model" => model) |> JSON3.write,
        )
        if res.status == 200
            @info "Model has been deleted successfully"
        end
    catch e
        if e isa HTTP.Exceptions.HTTPError
            body = e.response.body |> JSON3.read
            @info body[:error] * "." * "Maybe $(model) already deleted?"
        end
    end
end

function pull_model(model, out::IO = stdout)
    @info "Pulling" model

    buf = PipeBuffer()
    t = @async HTTP.post(
        joinpath(OLLAMA_BASE_URL, "api", "pull"),
        Dict("Content-Type" => "application/json", "Accept" => "application/json"),
        Dict("model" => model, "insecure" => false, "stream" => true) |> JSON3.write,
        response_stream = buf,
    )

    function model_receiver(c::Channel)
        chunk = ""
        while true
            if eof(buf)
                sleep(0.125)
            else
                chunk = readline(buf, keep = true)
                json_part = JSON3.read(chunk)
                json_part[:status] == "success" && break
                put!(c, json_part)
                chunk = ""
            end
        end
    end

    chunks = Channel(model_receiver)
    parts = String[]
    current_digest = ""
    p = Progress(1)
    for json in chunks
        # @show json
        occursin("pulling manifest", json[:status]) && continue
        if occursin("pulling", json[:status])
            digest = json[:status]
            if current_digest != digest
                # update digest
                current_digest = digest
                finish!(p)
                @debug "pulling:" current_digest
                # update Progress object
                p = Progress(json[:total]; desc = current_digest)
            else
                sleep(0.1)
                haskey(json, :completed) && update!(p, json[:completed])
            end
        end
    end
    wait(t)
    @debug "Done"
end

function listmodel(; verbose = false)
    res = HTTP.get(joinpath(OLLAMA_BASE_URL, "api", "tags"))
    json_body = JSON3.read(res.body)
    @assert haskey(json_body, :models)
    df = DataFrame(sort(json_body[:models], lt = (x, y) -> x[:size] < y[:size]))
    if verbose
        return df
    else
        df = DataFrame(
            :model => df[:, :model],
            :format_bytes => Base.format_bytes.(df[:, :size]),
        )
    end
end

function switchlang!(lang::Union{String,Symbol})
    DEFAULT_LANG[] = String(lang)
end

function switchlang!(node::QuoteNode)
    lang = node.value
    switchlang!(lang)
end

"""
    @switchlang!(lang)

Modify the behavior of the `Docs.parsedoc(d::DocStr)` to insert translation engine.
"""
macro switchlang!(lang)
    switchlang!(lang)
    @eval function Docs.parsedoc(d::DocStr)
        if d.object === nothing
            md = Docs.formatdoc(d)
            md.meta[:module] = d.data[:module]
            md.meta[:path] = d.data[:path]
            d.object = md
        end
        translate_with_ollama(d.object, string($(lang)))
    end

    @eval function REPL.summarize(io::IO, m::Module, binding::Binding; nlines::Int = 200)
        readme_path = find_readme(m)
        public = Base.ispublic(binding.mod, binding.var) ? "public" : "internal"
        if isnothing(readme_path)
            println(io, "No docstring or readme file found for $public module `$m`.\n")
        else
            println(io, "No docstring found for $public module `$m`.")
        end
        exports = filter!(!=(nameof(m)), names(m))
        if isempty(exports)
            println(io, "Module does not have any public names.")
        else
            println(io, "# Public names")
            print(io, "  `")
            join(io, exports, "`, `")
            println(io, "`\n")
        end
        if !isnothing(readme_path)
            readme_lines = readlines(readme_path)
            isempty(readme_lines) && return  # don't say we are going to print empty file
            println(io, "# Displaying contents of readme found at `$(readme_path)`")
            translated_md = translate_with_ollama(join(first(readme_lines, nlines), '\n'), string($(lang)))
            readme_lines = split(string(translated_md), '\n')
            for line in first(readme_lines, nlines)
                println(io, line)
            end
            length(readme_lines) > nlines && println(io, "\n[output truncated to first $nlines lines]")
        end
    end
end

"""
    @revertlang!

re-evaluate the original implementation for 
`Docs.parsedoc(d::DocStr)`
"""
macro revertlang!()
    switchlang!("English")
    @eval function Docs.parsedoc(d::DocStr)
        if d.object === nothing
            md = Docs.formatdoc(d)
            md.meta[:module] = d.data[:module]
            md.meta[:path] = d.data[:path]
            d.object = md
        end
        d.object
    end

    @eval function REPL.summarize(io::IO, m::Module, binding::Binding; nlines::Int = 200)
        readme_path = find_readme(m)
        public = Base.ispublic(binding.mod, binding.var) ? "public" : "internal"
        if isnothing(readme_path)
            println(io, "No docstring or readme file found for $public module `$m`.\n")
        else
            println(io, "No docstring found for $public module `$m`.")
        end
        exports = filter!(!=(nameof(m)), names(m))
        if isempty(exports)
            println(io, "Module does not have any public names.")
        else
            println(io, "# Public names")
            print(io, "  `")
            join(io, exports, "`, `")
            println(io, "`\n")
        end
        if !isnothing(readme_path)
            readme_lines = readlines(readme_path)
            isempty(readme_lines) && return  # don't say we are going to print empty file
            println(io, "# Displaying contents of readme found at `$(readme_path)`")
            for line in first(readme_lines, nlines)
                println(io, line)
            end
            length(readme_lines) > nlines && println(io, "\n[output truncated to first $nlines lines]")
        end
    end
end

function revertlang!()
    DEFAULT_LANG[] = "English"
end

function switchmodel!(model::Union{String,Symbol})
    @info "Switing model to $(model)"
    if model ∉ listmodel()[!, :model]
        pull_model(model)
    end
    DEFAULT_MODEL[] = string(model)
end

function default_model()
    return DEFAULT_MODEL[]
end

function default_lang()
    return DEFAULT_LANG[]
end

function default_promptfn(
    m::Union{Markdown.MD, AbstractString},
    language::String = default_lang(),
)
    prompt = """
You are an expert in the Julia programming language. You are a translation expert. Please provide a faithful translation of the following Markdown in $(language). The translation should faithfully preserve the formatting of the original Markdown. Do not add or remove unnecessary text. Only return a faithful translation:

$(m)

"""
    return prompt
end

function translate_with_ollama(
    doc::Union{Markdown.MD, AbstractString},
    language::String = default_lang(),
    model::String = default_model(),
    promptfn::Function = default_promptfn,
)
    prompt = promptfn(doc)
    chat_response = HTTP.post(
        joinpath("http://localhost:11434", "api", "chat"),
        Dict("Content-Type" => "application/json", "Accept" => "application/json"),
        Dict(
            "model" => model,
            "messages" => [Dict("role" => "user", "content" => prompt)],
            "tools" => [],
            "stream" => false,
        ) |> JSON3.write,
    )
    chat_json_body = JSON3.read(chat_response.body)
    Markdown.parse(chat_json_body[:message][:content])
end

function __init__()
    # launch ollama
    @info "Launching ollama with \"ollama ls\" command"
    read(`ollama ls`)
    @info "Done"
end

end # module DocstringTranslationOllamaBackend
