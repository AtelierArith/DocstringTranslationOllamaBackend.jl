# DocstringTranslationOllamaBackend.jl

## Description

This Julia package inserts Large Language Model (LLM) hooks into the API in the `Base.Docs module`, giving non-English speaking users the opportunity to help smooth API comprehension.

## Prerequisite

### Install Julia

Install Julia using juliaup.

```sh
$ curl -fsSL https://install.julialang.org | sh -s -- --yes
```

### Ollama

This package utilizes [Ollama](https://ollama.com/)
Navigate to https://ollama.com/download and follow the instruction. Once it has been installed, we can use `ollama` command. Let's run `ollama --version`

```sh
$ ollama --version
ollama version is 0.4.2
```

By default, We use local LLM model as [gemma2:9b](https://ollama.com/library/gemma2:9b). Therefore, please pull the model in advance. Namely:

```sh
$ ollama pull gemma2:9b
```

## Usage

Start Julia REPL

```sh
$ cd path/to/directory
$ julia
               _
   _       _ _(_)_     |  Documentation: https://docs.julialang.org
  (_)     | (_) (_)    |
   _ _   _| |_  __ _   |  Type "?" for help, "]?" for Pkg help.
  | | | | | | |/ _` |  |
  | | |_| | | | (_| |  |  Version 1.11.1 (2024-10-16)
 _/ |\__'_|_|_|\__'_|  |  Official https://julialang.org/ release
|__/                   |

julia> using Pkg; Pkg.activate("."); Pkg.instantiate()

julia> using DocstringTranslationOllamaBackend
[ Info: Launching ollama with "ollama ls" command
[ Info: Done
```

Call `@switchlang!` macro with your preferred language.

### Example: Japanese(日本語)

```julia
julia> @switchlang! :Japanese

help?> sin
search: sin sinc sind sinh sign asin in min sinpi using isinf

  sin(x)

  x (ラジアンで表された値) の正弦を計算します。

  sind、sinpi、sincos、cis、asin も参照してください。

  例
  ≡≡

  julia> round.(sin.(range(0, 2pi, length=9)'), digits=3)
  1×9 Matrix{Float64}:
   0.0  0.707  1.0  0.707  0.0  -0.707  -1.0  -0.707  -0.0

  julia> sind(45)
  0.7071067811865476

  julia> sinpi(1/4)
  0.7071067811865475

  julia> round.(sincos(pi/6), digits=3)
  (0.5, 0.866)

  julia> round(cis(pi/6), digits=3)
  0.866 + 0.5im

  julia> round(exp(im*pi/6), digits=3)
  0.866 + 0.5im

  ─────────────────────────────────────────────────────────────

  sin(A::AbstractMatrix)

  正方行列 A のマトリックスサインを計算します。

  A が対称行列またはエルミート行列であれば、固有値分解 (eigen)
  が使用して sine を計算します。それ以外の場合は、exp
  を呼び出すことで sine を決定します。

  例
  ≡≡

  julia> sin(fill(1.0, (2,2)))
  2×2 Matrix{Float64}:
   0.454649  0.454649
   0.454649  0.454649

julia>
```

### Example: German(ドイツ語)

```julia
help?> sin
search: sin sinc sind sinh sign asin in min sinpi using isinf

  sin(x)

  Berechnung des Sinus von x, wobei x in Radians liegt.

  Siehe auch sind, sinpi, sincos, cis, asin.

  Beispiele
  ≡≡≡≡≡≡≡≡≡

  julia> round.(sin.(range(0, 2pi, length=9)'), digits=3)
  1×9 Matrix{Float64}:
   0.0  0.707  1.0  0.707  0.0  -0.707  -1.0  -0.707  -0.0

  julia> sind(45)
  0.7071067811865476

  julia> sinpi(1/4)
  0.7071067811865475

  julia> round.(sincos(pi/6), digits=3)
  (0.5, 0.866)

  julia> round(cis(pi/6), digits=3)
  0.866 + 0.5im

  julia> round(exp(im*pi/6), digits=3)
  0.866 + 0.5im

  ─────────────────────────────────────────────────────────────

  sin(A::AbstractMatrix)

  Berechnet die Matrix-Sinus von einer quadratischen Matrix A.

  Wenn A symmetrisch oder hermitesch ist, wird ihre
  Eigenwertzerlegung (eigen) verwendet, um den Sinus zu
  berechnen. Andernfalls wird der Sinus durch einen Aufruf von
  exp bestimmt.

  Beispiele
  ≡≡≡≡≡≡≡≡≡

  julia> sin(fill(1.0, (2,2)))
  2×2 Matrix{Float64}:
   0.454649  0.454649
   0.454649  0.454649

julia>
```

### English(英語)

You can revert the default `@doc` functionality anytime. Just call `@revertlang!` macro.

```julia
julia> @revertlang!

help?> sin
search: sin sinc sind sinh sign asin in min sinpi using isinf

  sin(x)

  Compute sine of x, where x is in radians.

  See also sind, sinpi, sincos, cis, asin.

  Examples
  ≡≡≡≡≡≡≡≡

  julia> round.(sin.(range(0, 2pi, length=9)'), digits=3)
  1×9 Matrix{Float64}:
   0.0  0.707  1.0  0.707  0.0  -0.707  -1.0  -0.707  -0.0

  julia> sind(45)
  0.7071067811865476

  julia> sinpi(1/4)
  0.7071067811865475

  julia> round.(sincos(pi/6), digits=3)
  (0.5, 0.866)

  julia> round(cis(pi/6), digits=3)
  0.866 + 0.5im

  julia> round(exp(im*pi/6), digits=3)
  0.866 + 0.5im

  ─────────────────────────────────────────────────────────────

  sin(A::AbstractMatrix)

  Compute the matrix sine of a square matrix A.

  If A is symmetric or Hermitian, its eigendecomposition
  (eigen) is used to compute the sine. Otherwise, the sine is
  determined by calling exp.

  Examples
  ≡≡≡≡≡≡≡≡

  julia> sin(fill(1.0, (2,2)))
  2×2 Matrix{Float64}:
   0.454649  0.454649
   0.454649  0.454649

julia>
```

## Switching another LLM.

On machines without a GPU accelerator, one may want to switch to another lightweight model, such as ‘gemma2:2b’. However, the translation accuracy will be reduced.

```julia
julia> using Pkg; Pkg.activate(".")
julia> using DocstringTranslationOllamaBackend
julia> switchmodel!("gemma2:2b")
```