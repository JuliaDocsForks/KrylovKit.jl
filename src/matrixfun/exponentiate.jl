"""
    function exponentiate(A, t::Number, x; kwargs...)
    function exponentiate(A, t::Number, x, algorithm)

Compute ``y = exp(t*A) x``, where `A` is a general linear map, i.e. a `AbstractMatrix` or just
a general function or callable object and `x` is of any Julia type with vector like behavior.

### Arguments:
The linear map `A` can be an `AbstractMatrix` (dense or sparse) or a general function or callable
object that implements the action of the linear map on a vector. If `A` is an `AbstractMatrix`,
`x` is expected to be an `AbstractVector`, otherwise `x` can be of any type that behaves as a
vector and supports the required methods (see KrylovKit docs).

The time parameter `t` can be real or complex, and it is better to choose `t` e.g. imaginary
and `A` hermitian, then to absorb the imaginary unit in an antihermitian `A`. For the former,
the Lanczos scheme is used to built a Krylov subspace, in which an approximation to the exponential
action of the linear map is obtained. The argument `x` can be of any type and should be in the
domain of `A`.


### Return values:
The return value is always of the form `y, info = eigsolve(...)` with
*   `y`: the result of the computation, i.e. `y = exp(t*A)*x`
*   `info`: an object of type [`ConvergenceInfo`], which has the following fields
    -   `info.converged::Int`: 0 or 1 if the solution `y` was approximated up to the requested
        tolerance `tol`.
    -   `info.residual::Nothing`: value `nothing`, there is no concept of a residual in this case
    -   `info.normres::Real`: an estimate (upper bound) of the error between the approximate and exact solution
    -   `info.numops::Int`: number of times the linear map was applied, i.e. number of times
        `f` was called, or a vector was multiplied with `A`
    -   `info.numiter::Int`: number of times the Krylov subspace was restarted (see below)
!!! warning "Check for convergence"
    No warning is printed if not all requested eigenvalues were converged, so always check
    if `info.converged >= howmany`.

### Keyword arguments:
Keyword arguments and their default values are given by:
*   `krylovdim = 30`: the maximum dimension of the Krylov subspace that will be constructed.
    Note that the dimension of the vector space is not known or checked, e.g. `x₀` should not
    necessarily support the `Base.length` function. If you know the actual problem dimension
    is smaller than the default value, it is useful to reduce the value of `krylovdim`, though
    in principle this should be detected.
*   `tol = 1e-12`: the requested accuracy (corresponding to the 2-norm of the residual for
    Schur vectors, not the eigenvectors). If you work in e.g. single precision (`Float32`),
    you should definitely change the default value.
*   `maxiter = 100`: the number of times the Krylov subspace can be rebuilt; see below for
    further details on the algorithms.
*   `issymmetric`: if the linear map is symmetric, only meaningful if `T<:Real`
*   `ishermitian`: if the linear map is hermitian
The default value for the last two depends on the method. If an `AbstractMatrix` is used,
`issymmetric` and `ishermitian` are checked for that matrix, ortherwise the default values are
`issymmetric = false` and `ishermitian = T <: Real && issymmetric`.

### Algorithm
The last method, without default values and keyword arguments, is the one that is finally called,
and can also be used directly. Here, one specifies the algorithm explicitly as either [`Lanczos`](@ref),
for real symmetric or complex hermitian problems, or [`Arnoldi`](@ref), for general problems.
Note that these names refer to the process for building the Krylov subspace.

!!! warning "`Arnoldi` not yet implented"
"""
function exponentiate end

function exponentiate(A, t::Number, v; kwargs...)
    alg = eigselector(A, promote_type(typeof(t), eltype(v)); kwargs...)
    exponentiate(A, t, v, alg)
end

function exponentiate(A, t::Number, v, alg::Lanczos)
    # process initial vector and determine result type
    β = norm(v)
    Av = apply(A, v) # used to determine return type
    numops = 1
    T = promote_type(eltype(Av), typeof(β), typeof(t))
    S = real(T)
    w = mul!(similar(Av, T), v, 1/β)

    # krylovdim and related allocations
    krylovdim = alg.krylovdim
    UU = Matrix{S}(undef, (krylovdim, krylovdim))
    yy1 = Vector{T}(undef, krylovdim)
    yy2 = Vector{T}(undef, krylovdim)

    # initialize iterator
    iter = LanczosIterator(A, w, alg.orth, true)
    fact = initialize(iter)
    numops += 1
    sizehint!(fact, krylovdim)

    # time step parameters
    sgn = sign(t)
    τ::S = abs(t)
    Δτ::S = τ

    # tolerance
    η::S = alg.tol / τ # tolerance per unit step
    if η < length(w)*eps(typeof(η))
        η = length(w)*eps(typeof(η))
        warn("tolerance too small, increasing to $(η*τ)")
    end
    totalerr = zero(η)

    δ::S = 0.9 # safety factor

    # start outer iteration loop
    maxiter = alg.maxiter
    numiter = 0
    while true
        numiter += 1
        Δτ = numiter == maxiter ? τ : min(Δτ, τ)

        # Lanczos or Arnoldi factorization
        while normres(fact) > η && length(fact) < krylovdim
            fact = expand!(iter, fact)
            numops += 1
        end
        K = fact.k # current Krylov dimension
        V = basis(fact)
        m = length(fact)

        # Small matrix exponential and error estimation
        U = copyto!(view(UU, 1:m, 1:m), I)
        H = rayleighquotient(fact) # tridiagonal
        D, U = eig!(H, U)

        # Estimate largest allowed time step
        ϵ::S = zero(η)
        while true
            ϵ₁ = zero(eltype(H))
            ϵ₂ = zero(eltype(H))
            @inbounds for k = 1:K
                ϵ₁ += U[K,k] * exp(sgn * Δτ/2 * D[k]) * conj(U[1,k])
                ϵ₂ += U[K,k] * exp(sgn * Δτ * D[k]) * conj(U[1,k])
            end
            ϵ = normres(fact) * ( 2*abs(ϵ₁)/3 + abs(ϵ₂)/6 ) # error per unit time: see Lubich

            if ϵ < δ * η || numiter == maxiter
                break
            else # reduce time step
                Δτ = round(δ * (η / ϵ)^(1/krylovdim) * Δτ; sigdigits=2)
            end
        end

        # Apply time step
        totalerr += Δτ * ϵ
        y1 = view(yy1, 1:m)
        y2 = view(yy2, 1:m)
        @inbounds for k = 1:m
            y1[k] = exp(sgn*Δτ*D[k])*conj(U[1,k])
        end
        y2 = mul!(y2, U, y1)

        # Finalize step
        w = mul!(w, V, y2)
        τ -= Δτ

        if iszero(τ) # should always be true if numiter == maxiter
            w = rmul!(w, β)
            converged = totalerr < alg.tol ? 1 : 0
            return w, ConvergenceInfo(converged, nothing, totalerr, numiter, numops)
        else
            normw = norm(w)
            β *= normw
            w = rmul!(w, inv(normw))
            fact = initialize!(iter, fact)
        end
    end
end
