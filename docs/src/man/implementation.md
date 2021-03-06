# Details of the implementation

## Orthogonalization
To denote a basis of vectors, e.g. to represent a given Krylov subspace, there is an abstract
type `Basis{T}`
```@docs
KrylovKit.Basis
```

Many Krylov based algorithms use an orthogonal basis to parametrize the Krylov subspace. In that
case, the specific implementation `OrthonormalBasis{T}` can be used:
```@docs
KrylovKit.OrthonormalBasis{T}
```

We can orthogonalize or orthonormalize a given vector to another vector (assumed normalized)
or to a given [`OrthonormalBasis`](@ref).
```@docs
KrylovKit.orthogonalize
KrylovKit.orthonormalize
```

## Dense linear algebra

KrylovKit relies on Julia's `LinearAlgebra` module from the standard library for most of its
dense linear algebra dependencies. 

## Krylov factorizations
The central ingredient in a Krylov based algorithm is a Krylov factorization or decomposition
of a linear map. Such partial factorizations are represented as a `KrylovFactorization`, of
which `LanczosFactorization` and `ArnoldiFactorization` are two concrete implementations:
```@docs
KrylovKit.KrylovFactorization
```
A `KrylovFactorization` can be destructered into its defining components using iteration, but
these can also be accessed using the following functions
```@docs
basis
rayleighquotient
residual
normres
rayleighextension
```

## Krylov iterators
Given a linear map ``A`` and a starting vector ``x₀``, a Krylov factorization is obtained by sequentially
building a Krylov subspace ``{x₀, A x₀, A² x₀, ...}``. Rather then using this set of vectors
as a basis, an orthonormal basis is generated by a process known as Lanczos or Arnoldi iteration
(for symmetric/hermitian and for general matrices, respectively). These processes are represented
as iterators in Julia:
```@docs
KrylovKit.KrylovIterator
```
The following functions allow to manipulate a `KrylovFactorization` obtained from such a
`KrylovIterator`:

```@docs
expand!
shrink!
initialize!
initialize
```
