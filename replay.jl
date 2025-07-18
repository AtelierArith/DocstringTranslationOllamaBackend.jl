using Replay

instructions = [
	"using DocstringTranslation",
	"@switchlang! :ja",
	"@doc sin",
	"using LinearAlgebra",
	"@switchlang! :Spanish",
	"@doc eigen",
	"@switchlang! :Hindi",
	"? cos"
]

replay(instructions, use_ghostwriter=true)
