using SpecialFunctions, Documenter
using DocumenterCitations

# `using SpecialFunctions` for all doctests
DocMeta.setdocmeta!(SpecialFunctions, :DocTestSetup, :(using SpecialFunctions); recursive=true)

# ENV["OPENAI_API_KEY"] = "sk-<blah>"
using DocstringTranslation
@switchlang! :Hindi
DocstringTranslation.switchtargetpackage!(SpecialFunctions)

bib = CitationBibliography(
       joinpath(@__DIR__, "src", "refs.bib");
       style = :authoryear,
)

makedocs(modules=[SpecialFunctions],
         sitename="SpecialFunctions.jl",
         authors="Jeff Bezanson, Stefan Karpinski, Viral B. Shah, et al.",
         format = Documenter.HTML(; assets = String[]),
         pages=["Home" => "index.md",
                "Overview" => "functions_overview.md",
                "Reference" => "functions_list.md"],
         plugins=[bib],
         checkdocs=:exports,
         warnonly = [:citations]
        )

deploydocs(repo="github.com/JuliaMath/SpecialFunctions.jl.git")
