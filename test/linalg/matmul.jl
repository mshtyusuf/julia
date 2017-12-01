# This file is a part of Julia. License is MIT: https://julialang.org/license

using Test, Random

using Base.LinAlg: mul!, Adjoint, Transpose

## Test Julia fallbacks to BLAS routines

@testset "matrices with zero dimensions" begin
    @test ones(0,5)*ones(5,3) == zeros(0,3)
    @test ones(3,5)*ones(5,0) == zeros(3,0)
    @test ones(3,0)*ones(0,4) == zeros(3,4)
    @test ones(0,5)*ones(5,0) == zeros(0,0)
    @test ones(0,0)*ones(0,4) == zeros(0,4)
    @test ones(3,0)*ones(0,0) == zeros(3,0)
    @test ones(0,0)*ones(0,0) == zeros(0,0)
    @test Matrix{Float64}(uninitialized, 5, 0) |> t -> t't == zeros(0,0)
    @test Matrix{Float64}(uninitialized, 5, 0) |> t -> t*t' == zeros(5,5)
    @test Matrix{ComplexF64}(uninitialized, 5, 0) |> t -> t't == zeros(0,0)
    @test Matrix{ComplexF64}(uninitialized, 5, 0) |> t -> t*t' == zeros(5,5)
end
@testset "2x2 matmul" begin
    AA = [1 2; 3 4]
    BB = [5 6; 7 8]
    AAi = AA+(0.5*im).*BB
    BBi = BB+(2.5*im).*AA[[2,1],[2,1]]
    for A in (copy(AA), view(AA, 1:2, 1:2)), B in (copy(BB), view(BB, 1:2, 1:2))
        @test A*B == [19 22; 43 50]
        @test *(Transpose(A), B) == [26 30; 38 44]
        @test *(A, Transpose(B)) == [17 23; 39 53]
        @test *(Transpose(A), Transpose(B)) == [23 31; 34 46]
    end
    for Ai in (copy(AAi), view(AAi, 1:2, 1:2)), Bi in (copy(BBi), view(BBi, 1:2, 1:2))
        @test Ai*Bi == [-21+53.5im -4.25+51.5im; -12+95.5im 13.75+85.5im]
        @test *(Adjoint(Ai), Bi) == [68.5-12im 57.5-28im; 88-3im 76.5-25im]
        @test *(Ai, Adjoint(Bi)) == [64.5+5.5im 43+31.5im; 104-18.5im 80.5+31.5im]
        @test *(Adjoint(Ai), Adjoint(Bi)) == [-28.25-66im 9.75-58im; -26-89im 21-73im]
        @test_throws DimensionMismatch [1 2; 0 0; 0 0] * [1 2]
    end
    CC = ones(3, 3)
    @test_throws DimensionMismatch mul!(CC, AA, BB)
end
@testset "3x3 matmul" begin
    AA = [1 2 3; 4 5 6; 7 8 9].-5
    BB = [1 0 5; 6 -10 3; 2 -4 -1]
    AAi = AA+(0.5*im).*BB
    BBi = BB+(2.5*im).*AA[[2,1,3],[2,3,1]]
    for A in (copy(AA), view(AA, 1:3, 1:3)), B in (copy(BB), view(BB, 1:3, 1:3))
        @test A*B == [-26 38 -27; 1 -4 -6; 28 -46 15]
        @test *(Adjoint(A), B) == [-6 2 -25; 3 -12 -18; 12 -26 -11]
        @test *(A, Adjoint(B)) == [-14 0 6; 4 -3 -3; 22 -6 -12]
        @test *(Adjoint(A), Adjoint(B)) == [6 -8 -6; 12 -9 -9; 18 -10 -12]
    end
    for Ai in (copy(AAi), view(AAi, 1:3, 1:3)), Bi in (copy(BBi), view(BBi, 1:3, 1:3))
        @test Ai*Bi == [-44.75+13im 11.75-25im -38.25+30im; -47.75-16.5im -51.5+51.5im -56+6im; 16.75-4.5im -53.5+52im -15.5im]
        @test *(Adjoint(Ai), Bi) == [-21+2im -1.75+49im -51.25+19.5im; 25.5+56.5im -7-35.5im 22+35.5im; -3+12im -32.25+43im -34.75-2.5im]
        @test *(Ai, Adjoint(Bi)) == [-20.25+15.5im -28.75-54.5im 22.25+68.5im; -12.25+13im -15.5+75im -23+27im; 18.25+im 1.5+94.5im -27-54.5im]
        @test *(Adjoint(Ai), Adjoint(Bi)) == [1+2im 20.75+9im -44.75+42im; 19.5+17.5im -54-36.5im 51-14.5im; 13+7.5im 11.25+31.5im -43.25-14.5im]
        @test_throws DimensionMismatch [1 2 3; 0 0 0; 0 0 0] * [1 2 3]
    end
    CC = ones(4, 4)
    @test_throws DimensionMismatch mul!(CC, AA, BB)
end

# Generic AbstractArrays
module MyArray15367
    using Test, Random

    struct MyArray{T,N} <: AbstractArray{T,N}
        data::Array{T,N}
    end

    Base.size(A::MyArray) = size(A.data)
    Base.getindex(A::MyArray, indexes...) = A.data[indexes...]

    A = MyArray(rand(4,5))
    b = rand(5)
    @test A*b ≈ A.data*b
end

@testset "Generic integer matrix multiplication" begin
    AA = [1 2 3; 4 5 6] .- 3
    BB = [2 -2; 3 -5; -4 7]
    for A in (copy(AA), view(AA, 1:2, 1:3)), B in (copy(BB), view(BB, 1:3, 1:2))
        @test A*B == [-7 9; -4 9]
        @test *(Transpose(A), Transpose(B)) == [-6 -11 15; -6 -13 18; -6 -15 21]
    end
    AA = ones(Int, 2, 100)
    BB = ones(Int, 100, 3)
    for A in (copy(AA), view(AA, 1:2, 1:100)), B in (copy(BB), view(BB, 1:100, 1:3))
        @test A*B == [100 100 100; 100 100 100]
    end
    AA = rand(1:20, 5, 5) .- 10
    BB = rand(1:20, 5, 5) .- 10
    CC = Matrix{Int}(uninitialized, size(AA, 1), size(BB, 2))
    for A in (copy(AA), view(AA, 1:5, 1:5)), B in (copy(BB), view(BB, 1:5, 1:5)), C in (copy(CC), view(CC, 1:5, 1:5))
        @test *(Transpose(A), B) == A'*B
        @test *(A, Transpose(B)) == A*B'
        # Preallocated
        @test mul!(C, A, B) == A*B
        @test mul!(C, Transpose(A), B) == A'*B
        @test mul!(C, A, Transpose(B)) == A*B'
        @test mul!(C, Transpose(A), Transpose(B)) == A'*B'
        @test Base.LinAlg.mul!(C, Adjoint(A), Transpose(B)) == A'*B.'

        #test DimensionMismatch for generic_matmatmul
        @test_throws DimensionMismatch Base.LinAlg.mul!(C, Adjoint(A), Transpose(ones(Int,4,4)))
        @test_throws DimensionMismatch Base.LinAlg.mul!(C, Adjoint(ones(Int,4,4)), Transpose(B))
    end
    vv = [1,2]
    CC = Matrix{Int}(uninitialized, 2, 2)
    for v in (copy(vv), view(vv, 1:2)), C in (copy(CC), view(CC, 1:2, 1:2))
        @test @inferred(mul!(C, v, Adjoint(v))) == [1 2; 2 4]
    end
end

@testset "generic_matvecmul" begin
    AA = rand(5,5)
    BB = rand(5)
    for A in (copy(AA), view(AA, 1:5, 1:5)), B in (copy(BB), view(BB, 1:5))
        @test_throws DimensionMismatch Base.LinAlg.generic_matvecmul!(zeros(6),'N',A,B)
        @test_throws DimensionMismatch Base.LinAlg.generic_matvecmul!(B,'N',A,zeros(6))
    end
    vv = [1,2,3]
    CC = Matrix{Int}(uninitialized, 3, 3)
    for v in (copy(vv), view(vv, 1:3)), C in (copy(CC), view(CC, 1:3, 1:3))
        @test mul!(C, v, Transpose(v)) == v*v'
    end
    vvf = map(Float64,vv)
    CC = Matrix{Float64}(uninitialized, 3, 3)
    for vf in (copy(vvf), view(vvf, 1:3)), C in (copy(CC), view(CC, 1:3, 1:3))
        @test mul!(C, vf, Transpose(vf)) == vf*vf'
    end
end

@testset "fallbacks & such for BlasFloats" begin
    AA = rand(Float64,6,6)
    BB = rand(Float64,6,6)
    CC = zeros(Float64,6,6)
    for A in (copy(AA), view(AA, 1:6, 1:6)), B in (copy(BB), view(BB, 1:6, 1:6)), C in (copy(CC), view(CC, 1:6, 1:6))
        @test Base.LinAlg.mul!(C, Transpose(A), Transpose(B)) == A.'*B.'
        @test Base.LinAlg.mul!(C, A, Adjoint(B)) == A*B.'
        @test Base.LinAlg.mul!(C, Adjoint(A), B) == A.'*B
    end
end

@testset "matrix algebra with subarrays of floats (stride != 1)" begin
    A = reshape(map(Float64,1:20),5,4)
    Aref = A[1:2:end,1:2:end]
    Asub = view(A, 1:2:5, 1:2:4)
    b = [1.2,-2.5]
    @test (Aref*b) == (Asub*b)
    @test *(Transpose(Asub), Asub) == *(Transpose(Aref), Aref)
    @test *(Asub, Transpose(Asub)) == *(Aref, Transpose(Aref))
    Ai = A .+ im
    Aref = Ai[1:2:end,1:2:end]
    Asub = view(Ai, 1:2:5, 1:2:4)
    @test *(Adjoint(Asub), Asub) == *(Adjoint(Aref), Aref)
    @test *(Asub, Adjoint(Asub)) == *(Aref, Adjoint(Aref))
end

@testset "issue #15286" begin
    A = reshape(map(Float64, 1:20), 5, 4)
    C = zeros(8, 8)
    sC = view(C, 1:2:8, 1:2:8)
    B = reshape(map(Float64,-9:10),5,4)
    @test mul!(sC, Transpose(A), A) == A'*A
    @test mul!(sC, Transpose(A), B) == A'*B

    Aim = A .- im
    C = zeros(ComplexF64,8,8)
    sC = view(C, 1:2:8, 1:2:8)
    B = reshape(map(Float64,-9:10),5,4) .+ im
    @test mul!(sC, Adjoint(Aim), Aim) == Aim'*Aim
    @test mul!(sC, Adjoint(Aim), B) == Aim'*B
end

@testset "syrk & herk" begin
    AA = reshape(1:1503, 501, 3).-750.0
    res = Float64[135228751 9979252 -115270247; 9979252 10481254 10983256; -115270247 10983256 137236759]
    for A in (copy(AA), view(AA, 1:501, 1:3))
        @test *(Transpose(A), A) == res
        @test *(A', Transpose(A')) == res
    end
    cutoff = 501
    A = reshape(1:6*cutoff,2*cutoff,3).-(6*cutoff)/2
    Asub = view(A, 1:2:2*cutoff, 1:3)
    Aref = A[1:2:2*cutoff, 1:3]
    @test *(Transpose(Asub), Asub) == *(Transpose(Aref), Aref)
    Ai = A .- im
    Asub = view(Ai, 1:2:2*cutoff, 1:3)
    Aref = Ai[1:2:2*cutoff, 1:3]
    @test *(Adjoint(Asub), Asub) == *(Adjoint(Aref), Aref)

    @test_throws DimensionMismatch Base.LinAlg.syrk_wrapper!(zeros(5,5),'N',ones(6,5))
    @test_throws DimensionMismatch Base.LinAlg.herk_wrapper!(zeros(5,5),'N',ones(6,5))
end

@testset "matmul for types w/o sizeof (issue #1282)" begin
    AA = fill(complex(1,1), 10, 10)
    for A in (copy(AA), view(AA, 1:10, 1:10))
        A2 = A^2
        @test A2[1,1] == 20im
    end
end

@testset "scale!" begin
    AA = zeros(5, 5)
    BB = ones(5)
    CC = rand(5, 6)
    for A in (copy(AA), view(AA, 1:5, 1:5)), B in (copy(BB), view(BB, 1:5)), C in (copy(CC), view(CC, 1:5, 1:6))
        @test_throws DimensionMismatch scale!(A, B, C)
    end
end

# issue #6450
@test dot(Any[1.0,2.0], Any[3.5,4.5]) === 12.5

@testset "dot" for elty in (Float32, Float64, ComplexF32, ComplexF64)
    x = convert(Vector{elty},[1.0, 2.0, 3.0])
    y = convert(Vector{elty},[3.5, 4.5, 5.5])
    @test_throws DimensionMismatch dot(x, 1:2, y, 1:3)
    @test_throws BoundsError dot(x, 1:4, y, 1:4)
    @test_throws BoundsError dot(x, 1:3, y, 2:4)
    @test dot(x, 1:2,y, 1:2) == convert(elty, 12.5)
    @test x.'*y == convert(elty, 29.0)
    @test_throws MethodError dot(rand(elty, 2, 2), randn(elty, 2, 2))
    X = convert(Vector{Matrix{elty}},[reshape(1:4, 2, 2), ones(2, 2)])
    res = convert(Matrix{elty}, [7.0 13.0; 13.0 27.0])
    @test dot(X, X) == res
end

vecdot_(x,y) = invoke(vecdot, Tuple{Any,Any}, x,y)
@testset "generic vecdot" begin
    AA = [1+2im 3+4im; 5+6im 7+8im]
    BB = [2+7im 4+1im; 3+8im 6+5im]
    for A in (copy(AA), view(AA, 1:2, 1:2)), B in (copy(BB), view(BB, 1:2, 1:2))
        @test vecdot(A,B) == dot(vec(A),vec(B)) == vecdot_(A,B) == vecdot(float.(A),float.(B))
        @test vecdot(Int[], Int[]) == 0 == vecdot_(Int[], Int[])
        @test_throws MethodError vecdot(Any[], Any[])
        @test_throws MethodError vecdot_(Any[], Any[])
        for n1 = 0:2, n2 = 0:2, d in (vecdot, vecdot_)
            if n1 != n2
                @test_throws DimensionMismatch d(1:n1, 1:n2)
            else
                @test d(1:n1, 1:n2) ≈ vecnorm(1:n1)^2
            end
        end
    end
end

@testset "Issue 11978" begin
    A = Matrix{Matrix{Float64}}(uninitialized, 2, 2)
    A[1,1] = Matrix(1.0I, 3, 3)
    A[2,2] = Matrix(1.0I, 2, 2)
    A[1,2] = Matrix(1.0I, 3, 2)
    A[2,1] = Matrix(1.0I, 2, 3)
    b = Vector{Vector{Float64}}(uninitialized, 2)
    b[1] = ones(3)
    b[2] = ones(2)
    @test A*b == Vector{Float64}[[2,2,1], [2,2]]
end

@test_throws ArgumentError Base.LinAlg.copytri!(ones(10,10),'Z')

@testset "gemv! and gemm_wrapper for $elty" for elty in [Float32,Float64,ComplexF64,ComplexF32]
    @test_throws DimensionMismatch Base.LinAlg.gemv!(ones(elty,10),'N',rand(elty,10,10),ones(elty,11))
    @test_throws DimensionMismatch Base.LinAlg.gemv!(ones(elty,11),'N',rand(elty,10,10),ones(elty,10))
    @test Base.LinAlg.gemv!(ones(elty,0),'N',rand(elty,0,0),rand(elty,0)) == ones(elty,0)
    @test Base.LinAlg.gemv!(ones(elty,10), 'N',ones(elty,10,0),ones(elty,0)) == zeros(elty,10)

    I0x0 = Matrix{elty}(I, 0, 0)
    I10x10 = Matrix{elty}(I, 10, 10)
    I10x11 = Matrix{elty}(I, 10, 11)
    @test Base.LinAlg.gemm_wrapper('N','N', I10x10, I10x10) == I10x10
    @test_throws DimensionMismatch Base.LinAlg.gemm_wrapper!(I10x10,'N','N', I10x11, I10x10)
    @test_throws DimensionMismatch Base.LinAlg.gemm_wrapper!(I10x10,'N','N', I0x0, I0x0)

    A = rand(elty,3,3)
    @test Base.LinAlg.matmul3x3('T','N',A, Matrix{elty}(I, 3, 3)) == A.'
end

@testset "#13593, #13488" begin
    aa = rand(3,3)
    bb = rand(3,3)
    for a in (copy(aa), view(aa, 1:3, 1:3)), b in (copy(bb), view(bb, 1:3, 1:3))
        @test_throws ArgumentError mul!(a, a, b)
        @test_throws ArgumentError mul!(a, b, a)
        @test_throws ArgumentError mul!(a, a, a)
    end
end

# Number types that lack conversion to the destination type
struct RootInt
    i::Int
end
import Base: *, transpose
(*)(x::RootInt, y::RootInt) = x.i*y.i
transpose(x::RootInt) = x
@test Base.promote_op(*, RootInt, RootInt) === Int

@testset "#14293" begin
    a = [RootInt(3)]
    C = [0]
    mul!(C, a, Transpose(a))
    @test C[1] == 9
    a = [RootInt(2),RootInt(10)]
    @test a*a' == [4 20; 20 100]
    A = [RootInt(3) RootInt(5)]
    @test A*a == [56]
end

function test_mul(C, A, B)
    mul!(C, A, B)
    @test Array(A) * Array(B) ≈ C
    @test A*B ≈ C
end

@testset "mul! vs * for special types" begin
    eltypes = [Float32, Float64, Int64]
    for k in [3, 4, 10]
        T = rand(eltypes)
        bi1 = Bidiagonal(rand(T, k), rand(T, k-1), rand([:U, :L]))
        bi2 = Bidiagonal(rand(T, k), rand(T, k-1), rand([:U, :L]))
        tri1 = Tridiagonal(rand(T,k-1), rand(T, k), rand(T, k-1))
        tri2 = Tridiagonal(rand(T,k-1), rand(T, k), rand(T, k-1))
        stri1 = SymTridiagonal(rand(T, k), rand(T, k-1))
        stri2 = SymTridiagonal(rand(T, k), rand(T, k-1))
        C = rand(T, k, k)
        specialmatrices = (bi1, bi2, tri1, tri2, stri1, stri2)
        for A in specialmatrices
            B = specialmatrices[rand(1:length(specialmatrices))]
            test_mul(C, A, B)
        end
        for S in specialmatrices
            l = rand(1:6)
            B = randn(k, l)
            C = randn(k, l)
            test_mul(C, S, B)
            A = randn(l, k)
            C = randn(l, k)
            test_mul(C, A, S)
        end
    end
    for T in eltypes
        A = Bidiagonal(rand(T, 2), rand(T, 1), rand([:U, :L]))
        B = Bidiagonal(rand(T, 2), rand(T, 1), rand([:U, :L]))
        C = randn(2,2)
        test_mul(C, A, B)
        B = randn(2, 9)
        C = randn(2, 9)
        test_mul(C, A, B)
    end
    let
        tri44 = Tridiagonal(randn(3), randn(4), randn(3))
        tri33 = Tridiagonal(randn(2), randn(3), randn(2))
        full43 = randn(4, 3)
        full24 = randn(2, 4)
        full33 = randn(3, 3)
        full44 = randn(4, 4)
        @test_throws DimensionMismatch mul!(full43, tri44, tri33)
        @test_throws DimensionMismatch mul!(full44, tri44, tri33)
        @test_throws DimensionMismatch mul!(full44, tri44, full43)
        @test_throws DimensionMismatch mul!(full43, tri33, full43)
        @test_throws DimensionMismatch mul!(full43, full43, tri44)
    end
end

# #18218
module TestPR18218
    using Test
    import Base.*, Base.+, Base.zero
    struct TypeA
        x::Int
    end
    Base.convert(::Type{TypeA}, x::Int) = TypeA(x)
    struct TypeB
        x::Int
    end
    struct TypeC
        x::Int
    end
    Base.convert(::Type{TypeC}, x::Int) = TypeC(x)
    zero(c::TypeC) = TypeC(0)
    zero(::Type{TypeC}) = TypeC(0)
    (*)(x::Int, a::TypeA) = TypeB(x*a.x)
    (*)(a::TypeA, x::Int) = TypeB(a.x*x)
    (+)(a::Union{TypeB,TypeC}, b::Union{TypeB,TypeC}) = TypeC(a.x+b.x)
    A = TypeA[1 2; 3 4]
    b = [1, 2]
    d = A * b
    @test typeof(d) == Vector{TypeC}
    @test d == TypeC[5, 11]
end
