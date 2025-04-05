module DocstringTranslationOllamaBackend

using Base.Docs: DocStr, Binding
using REPL: find_readme
import REPL
using Markdown

using OrderedCollections
using HTTP
using JSON3
using ProgressMeter

const OLLAMA_BASE_URL = get(ENV, "OLLAMA_BASE_URL", "http://localhost:11434")
const DEFAULT_MODEL = Ref{String}("gemma3:4b")
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

function listmodel()
    res = HTTP.get(joinpath(OLLAMA_BASE_URL, "api", "tags"))
    json_body = JSON3.read(res.body)
    @assert haskey(json_body, :models)
    name_size = map(sort(json_body[:models], lt = (x, y) -> x[:size] < y[:size])) do obj
        String(obj[:model]) => String(Base.format_bytes(obj[:size]))
    end
    OrderedDict(name_size...)
end

function switchlang!(lang::Union{String,Symbol})
    DEFAULT_LANG[] = String(lang)
end

"""
    @switchlang!(lang)

Modify the behavior of the `Docs.parsedoc(d::DocStr)` to insert translation engine.
"""
macro switchlang!(lang)
    @eval function Docs.parsedoc(d::DocStr)
        if d.object === nothing
            md = Docs.formatdoc(d)
            md.meta[:module] = d.data[:module]
            md.meta[:path] = d.data[:path]
            d.object = md
        end
        translate_with_ollama_streaming(d.object)
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
            translated_md =
                translate_with_ollama_streaming(join(first(readme_lines, nlines), '\n'))
            readme_lines = split(string(translated_md), '\n')
            for line in readme_lines
                println(io, line)
            end
        end
    end
    quote
        local _lang = $(esc(lang))
        switchlang!(_lang)
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
            length(readme_lines) > nlines &&
                println(io, "\n[output truncated to first $nlines lines]")
        end
    end
end

function revertlang!()
    DEFAULT_LANG[] = "English"
end

function switchmodel!(model::Union{String,Symbol})
    @info "Switing model to $(model)"
    if model ∉ keys(listmodel())
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

function postprocess_content(content::AbstractString)
    # Replace each match with the text wrapped in a math code block
    return replace(
        content,
        r":\$(.*?):\$"s => s"```math\1```",
        r"\$\$(.*?)\$\$"s => s"```math\1```",
    )
end

function default_system_promptfn(language::String = default_lang())
    prompt = """
Please provide a faithful translation of the following JuliaLang Markdown in $(language) line by line.
The translation should retain the formatting of the original Markdown.
Keep special characters such as "\$", "@", ",", ".", "[" or "]".
Keep contents quoted by "`"
Keep source code quoted by codefence, especially "math", "julia", "julia-repl" and "jldoctest" These codefences are special words.
Continue until the translation is complete.
Just return the result. Keep in mind only return a faithful translation in $(language).
"""
    return prompt
end

function translate_with_ollama(
    doc::Union{Markdown.MD,AbstractString},
    language::String = default_lang(),
    model::String = default_model(),
    system_promptfn::Function = default_system_promptfn,
)
    prompt = system_promptfn(language)
    chat_response = HTTP.post(
        joinpath(OLLAMA_BASE_URL, "api", "chat"),
        Dict("Content-Type" => "application/json", "Accept" => "application/json"),
        Dict(
            "model" => model,
            "messages" => [
                Dict("role" => "system", "content" => prompt)
                Dict("role" => "user", "content" => """$(doc)""")
            ],
            "tools" => [],
            "stream" => false,
        ) |> JSON3.write,
    )
    chat_json_body = JSON3.read(chat_response.body)
    content = chat_json_body[:message][:content]
    # Post processing
    # The content may contains $$ ... $$
    docstr = postprocess_content(content)
    Markdown.parse(docstr)
end

function translate_with_ollama_streaming(
    doc::Union{Markdown.MD,AbstractString},
    language::String = default_lang(),
    model::String = default_model(),
    system_promptfn::Function = default_system_promptfn,
)
    buf = PipeBuffer()
    prompt = system_promptfn(language)
    t = @async HTTP.post(
        joinpath(OLLAMA_BASE_URL, "api", "chat"),
        Dict("Content-Type" => "application/json", "Accept" => "application/json"),
        Dict(
            "model" => model,
            "messages" => [
                Dict("role" => "system", "content" => prompt)
                Dict("role" => "user", "content" => "$(doc)")
            ],
            "tools" => [],
            "stream" => true,
        ) |> JSON3.write,
        response_stream = buf,
    )

    errormonitor(t)

    function sse_receiver(c::Channel)
        chunk = ""
        while true
            if eof(buf)
                sleep(0.125)
            else
                chunk = readline(buf, keep = true)
                if true
                    json_part = JSON3.read(chunk)
                    put!(c, json_part)
                    json_part.done && break
                    chunk = ""
                end
            end
        end
    end

    chunks = Channel(sse_receiver)
    msg_json = JSON3.Object()
    parts = String[]
    for json in chunks
        if !json.done
            text = hasproperty(json, :response) ? json.response : json.message.content
            write(stdout, text)
            push!(parts, text)
        else
            write(stdout, "\n")
            msg_dict = copy(json)
            if hasproperty(json, :response)
                msg_dict[:response] = join(parts)
            else
                msg_dict[:message][:content] = join(parts)
            end
            msg_json = msg_dict |> JSON3.write |> JSON3.read
        end
    end

    wait(t)
    content = msg_json[:message][:content]
    # Post processing
    # The content may contains $$ ... $$
    docstr = postprocess_content(content)
    return Markdown.parse(docstr)
end

function __init__()
    #@info "Launch ollama with \"ollama ls\" command"
    #read(`ollama ls`)
    # launch ollama
    @info "Launch ollama with \"ollama serve\" command"

    outbuf = IOBuffer()
    errbuf = IOBuffer()
    launchcmd = `ollama serve`
    @async begin
        try
            _ = run(pipeline(launchcmd, stdout = outbuf, stderr = errbuf), wait = true)
        catch e
            if e isa ProcessFailedException
                if occursin("address already in use", String(take!(errbuf)))
                    @info "Ollama is running"
                else
                    error("$(launchcmd) failed")
                end
            else
                rethrow(e)
            end
        end
        model = default_model()
        if model ∉ listmodel().model
            pull_model(model)
        end
    end

    @info "Done"
    println()
end

end # module DocstringTranslationOllamaBackend
