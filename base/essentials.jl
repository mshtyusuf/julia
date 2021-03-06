# This file is a part of Julia. License is MIT: https://julialang.org/license

using Core: CodeInfo

const Callable = Union{Function,Type}

const Bottom = Union{}

abstract type AbstractSet{T} end
abstract type AbstractDict{K,V} end

# The real @inline macro is not available until after array.jl, so this
# internal macro splices the meta Expr directly into the function body.
macro _inline_meta()
    Expr(:meta, :inline)
end
macro _noinline_meta()
    Expr(:meta, :noinline)
end

macro _gc_preserve_begin(arg1)
    Expr(:gc_preserve_begin, esc(arg1))
end

macro _gc_preserve_end(token)
    Expr(:gc_preserve_end, esc(token))
end

"""
    @nospecialize

Applied to a function argument name, hints to the compiler that the method
should not be specialized for different types of that argument.
This is only a hint for avoiding excess code generation.
Can be applied to an argument within a formal argument list, or in the
function body.
When applied to an argument, the macro must wrap the entire argument
expression.
When used in a function body, the macro must occur in statement position and
before any code.

```julia
function example_function(@nospecialize x)
    ...
end

function example_function(@nospecialize(x = 1), y)
    ...
end

function example_function(x, y, z)
    @nospecialize x y
    ...
end
```
"""
macro nospecialize(var, vars...)
    if isa(var, Expr) && var.head === :(=)
        var.head = :kw
    end
    Expr(:meta, :nospecialize, var, vars...)
end

macro _pure_meta()
    Expr(:meta, :pure)
end
# another version of inlining that propagates an inbounds context
macro _propagate_inbounds_meta()
    Expr(:meta, :inline, :propagate_inbounds)
end

"""
    convert(T, x)

Convert `x` to a value of type `T`.

If `T` is an [`Integer`](@ref) type, an [`InexactError`](@ref) will be raised if `x`
is not representable by `T`, for example if `x` is not integer-valued, or is outside the
range supported by `T`.

# Examples
```jldoctest
julia> convert(Int, 3.0)
3

julia> convert(Int, 3.5)
ERROR: InexactError: convert(Int64, 3.5)
Stacktrace:
 [1] convert(::Type{Int64}, ::Float64) at ./float.jl:703
```

If `T` is a [`AbstractFloat`](@ref) or [`Rational`](@ref) type,
then it will return the closest value to `x` representable by `T`.

```jldoctest
julia> x = 1/3
0.3333333333333333

julia> convert(Float32, x)
0.33333334f0

julia> convert(Rational{Int32}, x)
1//3

julia> convert(Rational{Int64}, x)
6004799503160661//18014398509481984
```

If `T` is a collection type and `x` a collection, the result of `convert(T, x)` may alias
`x`.
```jldoctest
julia> x = Int[1,2,3];

julia> y = convert(Vector{Int}, x);

julia> y === x
true
```
Similarly, if `T` is a composite type and `x` a related instance, the result of
`convert(T, x)` may alias part or all of `x`.
```jldoctest
julia> x = sparse(1.0I, 5, 5);

julia> typeof(x)
SparseMatrixCSC{Float64,Int64}

julia> y = convert(SparseMatrixCSC{Float64,Int64}, x);

julia> z = convert(SparseMatrixCSC{Float32,Int64}, y);

julia> y === x
true

julia> z === x
false

julia> z.colptr === x.colptr
true
```
"""
function convert end

convert(::Type{Any}, @nospecialize(x)) = x
convert(::Type{T}, x::T) where {T} = x

"""
    @eval [mod,] ex

Evaluate an expression with values interpolated into it using `eval`.
If two arguments are provided, the first is the module to evaluate in.
"""
macro eval(ex)
    :(eval($__module__, $(Expr(:quote,ex))))
end
macro eval(mod, ex)
    :(eval($(esc(mod)), $(Expr(:quote,ex))))
end

argtail(x, rest...) = rest
tail(x::Tuple) = argtail(x...)

# TODO: a better / more infer-able definition would pehaps be
#   tuple_type_head(T::Type) = fieldtype(T::Type{<:Tuple}, 1)
tuple_type_head(T::UnionAll) = (@_pure_meta; UnionAll(T.var, tuple_type_head(T.body)))
function tuple_type_head(T::Union)
    @_pure_meta
    return Union{tuple_type_head(T.a), tuple_type_head(T.b)}
end
function tuple_type_head(T::DataType)
    @_pure_meta
    T.name === Tuple.name || throw(MethodError(tuple_type_head, (T,)))
    return unwrapva(T.parameters[1])
end

tuple_type_tail(T::UnionAll) = (@_pure_meta; UnionAll(T.var, tuple_type_tail(T.body)))
function tuple_type_tail(T::Union)
    @_pure_meta
    return Union{tuple_type_tail(T.a), tuple_type_tail(T.b)}
end
function tuple_type_tail(T::DataType)
    @_pure_meta
    T.name === Tuple.name || throw(MethodError(tuple_type_tail, (T,)))
    if isvatuple(T) && length(T.parameters) == 1
        return T
    end
    return Tuple{argtail(T.parameters...)...}
end

tuple_type_cons(::Type, ::Type{Union{}}) = Union{}
function tuple_type_cons(::Type{S}, ::Type{T}) where T<:Tuple where S
    @_pure_meta
    Tuple{S, T.parameters...}
end

function unwrap_unionall(@nospecialize(a))
    while isa(a,UnionAll)
        a = a.body
    end
    return a
end

function rewrap_unionall(@nospecialize(t), @nospecialize(u))
    if !isa(u, UnionAll)
        return t
    end
    return UnionAll(u.var, rewrap_unionall(t, u.body))
end

# replace TypeVars in all enclosing UnionAlls with fresh TypeVars
function rename_unionall(@nospecialize(u))
    if !isa(u,UnionAll)
        return u
    end
    body = rename_unionall(u.body)
    if body === u.body
        body = u
    else
        body = UnionAll(u.var, body)
    end
    var = u.var::TypeVar
    nv = TypeVar(var.name, var.lb, var.ub)
    return UnionAll(nv, body{nv})
end

const _va_typename = Vararg.body.body.name
function isvarargtype(@nospecialize(t))
    t = unwrap_unionall(t)
    isa(t, DataType) && (t::DataType).name === _va_typename
end

isvatuple(t::DataType) = (n = length(t.parameters); n > 0 && isvarargtype(t.parameters[n]))
function unwrapva(@nospecialize(t))
    t2 = unwrap_unionall(t)
    isvarargtype(t2) ? t2.parameters[1] : t
end

typename(a) = error("typename does not apply to this type")
typename(a::DataType) = a.name
function typename(a::Union)
    ta = typename(a.a)
    tb = typename(a.b)
    ta === tb ? tb : error("typename does not apply to unions whose components have different typenames")
end
typename(union::UnionAll) = typename(union.body)

convert(::Type{T}, x::T) where {T<:Tuple{Any, Vararg{Any}}} = x
convert(::Type{T}, x::Tuple{Any, Vararg{Any}}) where {T<:Tuple} =
    (convert(tuple_type_head(T), x[1]), convert(tuple_type_tail(T), tail(x))...)

# TODO: the following definitions are equivalent (behaviorally) to the above method
# I think they may be faster / more efficient for inference,
# if we could enable them, but are they?
# TODO: These currently can't be used (#21026, #23017) since with
#     z(::Type{<:Tuple{Vararg{T}}}) where {T} = T
#   calling
#     z(Tuple{Val{T}} where T)
#   fails, even though `Type{Tuple{Val}} == Type{Tuple{Val{S}} where S}`
#   and so T should be `Val` (aka `Val{S} where S`)
#convert(_::Type{Tuple{S}}, x::Tuple{S}) where {S} = x
#convert(_::Type{Tuple{S}}, x::Tuple{Any}) where {S} = (convert(S, x[1]),)
#convert(_::Type{T}, x::T) where {S, N, T<:Tuple{S, Vararg{S, N}}} = x
#convert(_::Type{Tuple{S, Vararg{S, N}}},
#        x::Tuple{Any, Vararg{Any, N}}) where
#       {S, N} = cnvt_all(S, x...)
#convert(_::Type{Tuple{Vararg{S, N}}},
#        x::Tuple{Vararg{Any, N}}) where
#       {S, N} = cnvt_all(S, x...)
# TODO: These currently can't be used since
#   Type{NTuple} <: (Type{Tuple{Vararg{S}}} where S) is true
#   even though the value S doesn't exist
#convert(_::Type{Tuple{Vararg{S}}},
#        x::Tuple{Any, Vararg{Any}}) where
#       {S} = cnvt_all(S, x...)
#convert(_::Type{Tuple{Vararg{S}}},
#        x::Tuple{Vararg{Any}}) where
#       {S} = cnvt_all(S, x...)
#cnvt_all(T) = ()
#cnvt_all(T, x, rest...) = (convert(T, x), cnvt_all(T, rest...)...)
# TODO: These may be necessary if the above are enabled
#convert(::Type{Tuple{}}, ::Tuple{}) = ()
#convert(::Type{Tuple{Vararg{S}}} where S, ::Tuple{}) = ()

"""
    oftype(x, y)

Convert `y` to the type of `x` (`convert(typeof(x), y)`).

# Examples
```jldoctest
julia> x = 4;

julia> y = 3.;

julia> oftype(x, y)
3

julia> oftype(y, x)
4.0
```
"""
oftype(x, y) = convert(typeof(x), y)

unsigned(x::Int) = reinterpret(UInt, x)
signed(x::UInt) = reinterpret(Int, x)

# conversions used by ccall
ptr_arg_cconvert(::Type{Ptr{T}}, x) where {T} = cconvert(T, x)
ptr_arg_unsafe_convert(::Type{Ptr{T}}, x) where {T} = unsafe_convert(T, x)
ptr_arg_unsafe_convert(::Type{Ptr{Void}}, x) = x

"""
    cconvert(T,x)

Convert `x` to a value to be passed to C code as type `T`, typically by calling `convert(T, x)`.

In cases where `x` cannot be safely converted to `T`, unlike [`convert`](@ref), `cconvert` may
return an object of a type different from `T`, which however is suitable for
[`unsafe_convert`](@ref) to handle. The result of this function should be kept valid (for the GC)
until the result of [`unsafe_convert`](@ref) is not needed anymore.
This can be used to allocate memory that will be accessed by the `ccall`.
If multiple objects need to be allocated, a tuple of the objects can be used as return value.

Neither `convert` nor `cconvert` should take a Julia object and turn it into a `Ptr`.
"""
function cconvert end

cconvert(T::Type, x) = convert(T, x) # do the conversion eagerly in most cases
cconvert(::Type{<:Ptr}, x) = x # but defer the conversion to Ptr to unsafe_convert
unsafe_convert(::Type{T}, x::T) where {T} = x # unsafe_convert (like convert) defaults to assuming the convert occurred
unsafe_convert(::Type{T}, x::T) where {T<:Ptr} = x  # to resolve ambiguity with the next method
unsafe_convert(::Type{P}, x::Ptr) where {P<:Ptr} = convert(P, x)

"""
    reinterpret(type, A)

Change the type-interpretation of a block of memory.
For arrays, this constructs a view of the array with the same binary data as the given
array, but with the specified element type.
For example,
`reinterpret(Float32, UInt32(7))` interprets the 4 bytes corresponding to `UInt32(7)` as a
[`Float32`](@ref).

# Examples
```jldoctest
julia> reinterpret(Float32, UInt32(7))
1.0f-44

julia> reinterpret(Float32, UInt32[1 2 3 4 5])
1×5 reinterpret(Float32, ::Array{UInt32,2}):
 1.4013e-45  2.8026e-45  4.2039e-45  5.60519e-45  7.00649e-45
```
"""
reinterpret(::Type{T}, x) where {T} = bitcast(T, x)
reinterpret(::Type{Unsigned}, x::Float16) = reinterpret(UInt16,x)
reinterpret(::Type{Signed}, x::Float16) = reinterpret(Int16,x)

"""
    sizeof(T)

Size, in bytes, of the canonical binary representation of the given DataType `T`, if any.

# Examples
```jldoctest
julia> sizeof(Float32)
4

julia> sizeof(ComplexF64)
16
```

If `T` does not have a specific size, an error is thrown.

```jldoctest
julia> sizeof(Base.LinAlg.LU)
ERROR: argument is an abstract type; size is indeterminate
Stacktrace:
[...]
```
"""
sizeof(x) = Core.sizeof(x)

function append_any(xs...)
    # used by apply() and quote
    # must be a separate function from append(), since apply() needs this
    # exact function.
    out = Vector{Any}(uninitialized, 4)
    l = 4
    i = 1
    for x in xs
        for y in x
            if i > l
                ccall(:jl_array_grow_end, Void, (Any, UInt), out, 16)
                l += 16
            end
            Core.arrayset(true, out, y, i)
            i += 1
        end
    end
    ccall(:jl_array_del_end, Void, (Any, UInt), out, l-i+1)
    out
end

# simple Array{Any} operations needed for bootstrap
@eval setindex!(A::Array{Any}, @nospecialize(x), i::Int) = Core.arrayset($(Expr(:boundscheck)), A, x, i)

"""
    precompile(f, args::Tuple{Vararg{Any}})

Compile the given function `f` for the argument tuple (of types) `args`, but do not execute it.
"""
function precompile(@nospecialize(f), args::Tuple)
    ccall(:jl_compile_hint, Int32, (Any,), Tuple{Core.Typeof(f), args...}) != 0
end

function precompile(argt::Type)
    ccall(:jl_compile_hint, Int32, (Any,), argt) != 0
end

"""
    esc(e)

Only valid in the context of an `Expr` returned from a macro. Prevents the macro hygiene
pass from turning embedded variables into gensym variables. See the [Macros](@ref man-macros)
section of the Metaprogramming chapter of the manual for more details and examples.
"""
esc(@nospecialize(e)) = Expr(:escape, e)

"""
    @boundscheck(blk)

Annotates the expression `blk` as a bounds checking block, allowing it to be elided by [`@inbounds`](@ref).

!!! note
    The function in which `@boundscheck` is written must be inlined into
    its caller in order for `@inbounds` to have effect.

# Examples
```jldoctest
julia> @inline function g(A, i)
           @boundscheck checkbounds(A, i)
           return "accessing (\$A)[\$i]"
       end
       f1() = return g(1:2, -1)
       f2() = @inbounds return g(1:2, -1)
f2 (generic function with 1 method)

julia> f1()
ERROR: BoundsError: attempt to access 2-element UnitRange{Int64} at index [-1]
Stacktrace:
 [1] throw_boundserror(::UnitRange{Int64}, ::Tuple{Int64}) at ./abstractarray.jl:435
 [2] checkbounds at ./abstractarray.jl:399 [inlined]
 [3] g at ./none:2 [inlined]
 [4] f1() at ./none:1

julia> f2()
"accessing (1:2)[-1]"
```

!!! warning

    The `@boundscheck` annotation allows you, as a library writer, to opt-in to
    allowing *other code* to remove your bounds checks with [`@inbounds`](@ref).
    As noted there, the caller must verify—using information they can access—that
    their accesses are valid before using `@inbounds`. For indexing into your
    [`AbstractArray`](@ref) subclasses, for example, this involves checking the
    indices against its [`size`](@ref). Therefore, `@boundscheck` annotations
    should only be added to a [`getindex`](@ref) or [`setindex!`](@ref)
    implementation after you are certain its behavior is correct.
"""
macro boundscheck(blk)
    return Expr(:if, Expr(:boundscheck), esc(blk))
end

"""
    @inbounds(blk)

Eliminates array bounds checking within expressions.

In the example below the in-range check for referencing
element `i` of array `A` is skipped to improve performance.

```julia
function sum(A::AbstractArray)
    r = zero(eltype(A))
    for i = 1:length(A)
        @inbounds r += A[i]
    end
    return r
end
```

!!! warning

    Using `@inbounds` may return incorrect results/crashes/corruption
    for out-of-bounds indices. The user is responsible for checking it manually.
    Only use `@inbounds` when it is certain from the information locally available
    that all accesses are in bounds.
"""
macro inbounds(blk)
    return Expr(:block,
        Expr(:inbounds, true),
        esc(blk),
        Expr(:inbounds, :pop))
end

"""
    @label name

Labels a statement with the symbolic label `name`. The label marks the end-point
of an unconditional jump with [`@goto name`](@ref).
"""
macro label(name::Symbol)
    return esc(Expr(:symboliclabel, name))
end

"""
    @goto name

`@goto name` unconditionally jumps to the statement at the location [`@label name`](@ref).

`@label` and `@goto` cannot create jumps to different top-level statements. Attempts cause an
error. To still use `@goto`, enclose the `@label` and `@goto` in a block.
"""
macro goto(name::Symbol)
    return esc(Expr(:symbolicgoto, name))
end

# SimpleVector

function getindex(v::SimpleVector, i::Int)
    @boundscheck if !(1 <= i <= length(v))
        throw(BoundsError(v,i))
    end
    t = @_gc_preserve_begin v
    x = unsafe_load(convert(Ptr{Ptr{Void}},data_pointer_from_objref(v)) + i*sizeof(Ptr))
    x == C_NULL && throw(UndefRefError())
    o = unsafe_pointer_to_objref(x)
    @_gc_preserve_end t
    return o
end

function length(v::SimpleVector)
    t = @_gc_preserve_begin v
    l = unsafe_load(convert(Ptr{Int},data_pointer_from_objref(v)))
    @_gc_preserve_end t
    return l
end
endof(v::SimpleVector) = length(v)
start(v::SimpleVector) = 1
next(v::SimpleVector,i) = (v[i],i+1)
done(v::SimpleVector,i) = (length(v) < i)
isempty(v::SimpleVector) = (length(v) == 0)
axes(v::SimpleVector) = (OneTo(length(v)),)
linearindices(v::SimpleVector) = axes(v, 1)
axes(v::SimpleVector, d) = d <= 1 ? axes(v)[d] : OneTo(1)

function ==(v1::SimpleVector, v2::SimpleVector)
    length(v1)==length(v2) || return false
    for i = 1:length(v1)
        v1[i] == v2[i] || return false
    end
    return true
end

map(f, v::SimpleVector) = Any[ f(v[i]) for i = 1:length(v) ]

getindex(v::SimpleVector, I::AbstractArray) = Core.svec(Any[ v[i] for i in I ]...)

"""
    isassigned(array, i) -> Bool

Test whether the given array has a value associated with index `i`. Return `false`
if the index is out of bounds, or has an undefined reference.

# Examples
```jldoctest
julia> isassigned(rand(3, 3), 5)
true

julia> isassigned(rand(3, 3), 3 * 3 + 1)
false

julia> mutable struct Foo end

julia> v = similar(rand(3), Foo)
3-element Array{Foo,1}:
 #undef
 #undef
 #undef

julia> isassigned(v, 1)
false
```
"""
function isassigned end

function isassigned(v::SimpleVector, i::Int)
    @boundscheck 1 <= i <= length(v) || return false
    t = @_gc_preserve_begin v
    x = unsafe_load(convert(Ptr{Ptr{Void}},data_pointer_from_objref(v)) + i*sizeof(Ptr))
    @_gc_preserve_end t
    return x != C_NULL
end

"""
    Colon()

Colons (:) are used to signify indexing entire objects or dimensions at once.

Very few operations are defined on Colons directly; instead they are converted
by [`to_indices`](@ref) to an internal vector type (`Base.Slice`) to represent the
collection of indices they span before being used.
"""
struct Colon
end
const (:) = Colon()

"""
    Val(c)

Return `Val{c}()`, which contains no run-time data. Types like this can be used to
pass the information between functions through the value `c`, which must be an `isbits`
value. The intent of this construct is to be able to dispatch on constants directly (at
compile time) without having to test the value of the constant at run time.

# Examples
```jldoctest
julia> f(::Val{true}) = "Good"
f (generic function with 1 method)

julia> f(::Val{false}) = "Bad"
f (generic function with 2 methods)

julia> f(Val(true))
"Good"
```
"""
struct Val{x}
end

Val(x) = (@_pure_meta; Val{x}())

# used by keyword arg call lowering
function vector_any(@nospecialize xs...)
    n = length(xs)
    a = Vector{Any}(uninitialized, n)
    @inbounds for i = 1:n
        Core.arrayset(false, a, xs[i], i)
    end
    a
end

"""
    invokelatest(f, args...; kwargs...)

Calls `f(args...; kwargs...)`, but guarantees that the most recent method of `f`
will be executed.   This is useful in specialized circumstances,
e.g. long-running event loops or callback functions that may
call obsolete versions of a function `f`.
(The drawback is that `invokelatest` is somewhat slower than calling
`f` directly, and the type of the result cannot be inferred by the compiler.)
"""
function invokelatest(f, args...; kwargs...)
    # We use a closure (`inner`) to handle kwargs.
    inner() = f(args...; kwargs...)
    Core._apply_latest(inner)
end

# iteration protocol

"""
    next(iter, state) -> item, state

For a given iterable object and iteration state, return the current item and the next iteration state.

# Examples
```jldoctest
julia> next(1:5, 3)
(3, 4)

julia> next(1:5, 5)
(5, 6)
```
"""
function next end

"""
    start(iter) -> state

Get initial iteration state for an iterable object.

# Examples
```jldoctest
julia> start(1:5)
1

julia> start([1;2;3])
1

julia> start([4;2;3])
1
```
"""
function start end

"""
    done(iter, state) -> Bool

Test whether we are done iterating.

# Examples
```jldoctest
julia> done(1:5, 3)
false

julia> done(1:5, 5)
false

julia> done(1:5, 6)
true
```
"""
function done end

"""
    isempty(collection) -> Bool

Determine whether a collection is empty (has no elements).

# Examples
```jldoctest
julia> isempty([])
true

julia> isempty([1 2 3])
false
```
"""
isempty(itr) = done(itr, start(itr))

"""
    values(iterator)

For an iterator or collection that has keys and values, return an iterator
over the values.
This function simply returns its argument by default, since the elements
of a general iterator are normally considered its "values".

# Examples
```jldoctest
julia> d = Dict("a"=>1, "b"=>2);

julia> values(d)
Base.ValueIterator for a Dict{String,Int64} with 2 entries. Values:
  2
  1

julia> values([2])
1-element Array{Int64,1}:
 2
```
"""
values(itr) = itr

"""
    Missing

A type with no fields whose singleton instance [`missing`](@ref) is used
to represent missing values.
"""
struct Missing end

"""
    missing

The singleton instance of type [`Missing`](@ref) representing a missing value.
"""
const missing = Missing()

"""
    ismissing(x)

Indicate whether `x` is [`missing`](@ref).
"""
ismissing(::Any) = false
ismissing(::Missing) = true
