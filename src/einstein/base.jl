
# einstein.jl - utils for working with expressions in Einstein notation

const IDX_NAMES = [:i, :j, :k, :l, :m, :n, :p, :q, :r, :s]


function isindexed(ex)
    return exprlike(ex) && (ex.head == :ref || any(isindexed, ex.args))
end

isvectorized(ex) = exprlike(ex) && !isindexed(ex)


function add_indices(ex, s2i::Dict)
    st = [(k => Expr(:ref, k, v...)) for (k, v) in s2i]
    return subs(ex, st)
end


function with_indices(x::Symbol, start_idx::Int, num_idxs::Int)
    return Expr(:ref, x, IDX_NAMES[start_idx:start_idx+num_idxs-1]...)
end

with_indices(x::Symbol, num_idxs::Int) = with_indices(x, 1, num_idxs)

## """Collect index names used in expression"""
## function collect_indexes!(idxs::Vector{Symbol}, ex)
##     if isa(ex, Expr)  # otherwise ignore
##         if ex.head == :ref
##             append!(idxs, ex.args[2:end])
##         else
##             for arg in ex.args
##                 collect_indexes!(idxs, arg)
##             end
##         end
##     end
## end

## function collect_indexes(ex)
##     idxs = Array(Symbol, 0)
##     collect_indexes!(idxs, ex)
##     return idxs
## end


function indexed_vars!(res::Vector{Expr}, ex)
    if exprlike(ex)
        if ex.head == :ref
            push!(res, ex)
        else
            for arg in ex.args
                indexed_vars!(res, arg)
            end
        end
    end
end

function indexed_vars(ex)
    res = Array(Expr, 0)
    indexed_vars!(res, ex)
    return res
end

# all_indexes(ex) = [ref.args[2:end] for ref in indexed_vars(ex)]

function get_indices(ex)
    idxs = [ref.args[2:end] for ref in indexed_vars(ex)]
    return convert(Vector{Vector{Symbol}}, idxs)
end


## function sum_indexes(ex::Expr)
##     @assert ex.head == :call
##     # only product of 2 tensors implies that repeating indexes need to be summed
##     # e.g. in `c[i] = a[i] + b[i]` index i means "for each", not "sum"
##     if ex.args[1] == :*
##         idxs = flatten([collect_indexes(arg) for arg in ex.args[2:end]])
##         counts = countdict(idxs)
##         repeated = filter((idx, c) -> c > 1, counts)
##         return collect(Symbol, keys(repeated))
##     else
##         return Symbol[]
##     end
## end


## """Accepts single call expressions, e.g. :(A[i,k] * B[k,j]) or :(exp(C[i]))"""
## function forall_and_sum_indexes(ex::Expr)
##     @assert ex.head == :call
##     @assert reduce(&, [isa(arg, Expr) && arg.head == :ref
##                        for arg in ex.args[2:end]])
##     all_idxs = unique(collect_indexes(ex))
##     sum_idxs = sum_indexes(ex)
##     forall_idxs = setdiff(all_idxs, sum_idxs)
##     return forall_idxs, sum_idxs
## end


## forall_indices(ex::Expr) = forall_and_sum_indices(ex)[1]



function forall_indices{T}(op::Symbolic, depidxs::Vector{Vector{T}})
    if op == :*
        counts = countdict(flatten(depidxs))
        repeated = filter((idx, c) -> c == 1, counts)
        return collect(Symbol, keys(repeated))
    else
        return unique(flatten(Symbol, depidxs))
    end
end

## function forall_indices(ex::Expr)
##     # depidxs = flatten1(map(forall_indices, ex.args))
##     if ex.head == :call
##         depidxs = flatten1(map(forall_indices, ex.args))
##         return forall_indices(ex.args[1], depidxs)
##     else
##         return depidxs
##     end
## end

function forall_indices(ex::Expr)
    if ex.head == :ref
        # TODO: take only nonrepeating
        return convert(Vector{Symbol}, ex.args[2:end])
    elseif ex.head == :call
        depidxs = [forall_indices(x) for x in ex.args[2:end]]
        return forall_indices(ex.args[1], depidxs)
    else
        return unique(flatten([forall_indices(x) for x in ex.args[2:end]]))
    end
end

forall_indices(x) = Symbol[]

function sum_indices{T}(op::Symbolic, depidxs::Vector{Vector{T}})
    if op == :*
        counts = countdict(flatten(depidxs))
        repeated = filter((idx, c) -> c > 1, counts)
        return collect(Symbol, keys(repeated))
    else
        return Symbol[]
    end
end

function sum_indices(ex::Expr)
    if ex.head == :ref
        # TODO: take repeating indices
        return Symbol[]
    elseif ex.head == :call
        sum_depidxs = unique(flatten([sum_indices(x) for x in ex.args[2:end]]))
        forall_depidxs = [forall_indices(x) for x in ex.args[2:end]]
        new_sum_idxs = sum_indices(ex.args[1], forall_depidxs)
        return unique(flatten([sum_depidxs, new_sum_idxs]))
    else
        return Symbol[]
    end
end

sum_indices(x) = Symbol[]


# guards

if VERSION < v"0.5-"
    is_comparison(ex) = isa(ex, Expr) && ex.head == :comparison
else
    const COMPARISON_SYMBOLS = Set([:(==), :(!=), :(>), :(>=), :(<), :(<=)])
    is_comparison(ex) = (isa(ex, Expr) && ex.head == :call &&
                         in(ex.args[1], COMPARISON_SYMBOLS))
end

function get_guards!(guards::Vector{Expr}, ex::Expr)
    if is_comparison(ex)
        push!(guards, ex)
    else
        for arg in ex.args
            get_guards!(guards, arg)
        end
    end
    return guards
end

get_guards!(guards::Vector{Expr}, x) = guards
get_guards(ex) = get_guards!(Expr[], ex)


function without_guards(ex)
    return without(ex, :(i == j); phs=[:i, :j])
end


# LHS inference (not used for now)

function infer_lhs(ex::Expr; outvar=:_R)
    idxs = forall_indices(ex)
    return Expr(:ref, outvar, idxs...)
end


function with_lhs(ex::Expr; outvar=:_R)
    lhs = infer_lhs(ex; outvar=outvar)
    return Expr(:(=), lhs, ex)
end
