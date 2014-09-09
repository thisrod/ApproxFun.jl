include("bary.jl")
include("clenshaw.jl")
include("ultraspherical.jl")




##  Constructors



##TODO: No zero length funs
type IFun{T<:Union(Float64,Complex{Float64})} <: AbstractFun
    coefficients::Vector{T}
    space::FunctionSpace
end



IFun{T<:Union(Int64,Complex{Int64})}(coefs::Vector{T},d::FunctionSpace)=IFun(1.0*coefs,d)


function IFun(f::Function,d::IntervalDomainSpace,n::Integer)
    pts=points(d,n)
    f1=f(pts[1])
    T=typeof(f1)
        
    if T <: Vector
        IFun{typeof(f1[1]),typeof(d)}[IFun(x->f(x)[k],d,n) for k=1:length(f1)]
    elseif T <: Array
        IFun{typeof(f1[1,1]),typeof(d)}[IFun(x->f(x)[k,j],d,n) for k=1:size(f1,1),j=1:size(f1,2)]    
    else
        vals=T[f(x) for x in pts]
        IFun(chebyshevtransform(vals),d)
    end
end

IFun(f::IFun,d::IntervalDomainSpace)=IFun(coefficients(f),d)


IFun(f,d::IntervalDomain)=IFun(f,ChebyshevSpace(d))
IFun(f,d::IntervalDomain,n)=IFun(f,ChebyshevSpace(d),n)

IFun(f::Function,n::Integer)=IFun(f,Interval(),n)
IFun{T<:Number}(f::Function,d::Vector{T},n::Integer)=IFun(f,Interval(d),n)
IFun(cfs::Vector)=IFun(1.0*cfs,Interval())
IFun{T<:Number}(cfs::Vector,d::Vector{T})=IFun(1.0*cfs,Interval(d))
IFun(f::Function)=IFun(f,Interval())
IFun{T<:Number}(f::Function,d::Vector{T})=IFun(f,Interval(d))


IFun{T<:Number}(f::IFun,d::Vector{T})=IFun(coefficients(f),d)
IFun(f::IFun)=IFun(coefficients(f))

IFun(c::Number)=IFun([c])
IFun(c::Number,d::IntervalDomain)=IFun([c],d)
IFun(c::Number,d)=IFun([c],d)

## List constructor

IFun{T<:IntervalDomain}(c::Number,dl::Vector{T})=map(d->IFun(c,d),dl)
IFun{T<:IntervalDomain}(f,dl::Vector{T})=map(d->IFun(f,d),dl)

## Adaptive constructors

function randomIFun(f::Function,d::IntervalDomain)
    @assert d == Interval()

    #TODO: implement other domains
    
    IFun(chebyshevtransform(randomadaptivebary(f)),d)
end


function veczerocfsIFun(f::Function,d::IntervalDomain)
    #reuse function values

    tol = 200*eps()

    for logn = 4:20
        cf = IFun(f, d, 2^logn + 1)
        cfs=coefficients(cf)
        
        if norm(cfs[:,end-8:end],Inf) < tol*norm(cfs[:,1:8],Inf)
            nrm=norm(cfs,Inf)
            return map!(g->chop!(g,10eps()*nrm),cf)
        end
    end
    
    warn("Maximum length reached")
    
    IFun(f,d,2^21 + 1)
end

function zerocfsIFun(f::Function,d::IntervalDomain)
    #reuse function values

    if isa(f(fromcanonical(d,0.)),Vector)
        return veczerocfsIFun(f,d)
    end

    tol = 200*eps()

    for logn = 4:20
        cf = IFun(f, d, 2^logn + 1)
        
        if maximum(abs(cf.coefficients[end-8:end])) < tol*maximum(abs(cf.coefficients[1:8]))
            return chop!(cf,10eps()*maximum(abs(cf.coefficients)))
        end
    end
    
    warn("Maximum length reached")
    
    IFun(f,d,2^21 + 1)
end




function abszerocfsIFun(f::Function,d::IntervalDomain)
    #reuse function values

    tol = 200eps();

    for logn = 4:20
        cf = IFun(f, d, 2^logn + 1)
        
        if maximum(abs(cf.coefficients[end-8:end])) < tol
            return chop!(cf,10eps())
        end
    end
    
    warn("Maximum length reached")
    
    IFun(f,d,2^21 + 1)
end


function IFun(f::Function, d::IntervalDomain; method="zerocoefficients")
    if f==identity
        identity_fun(d)
    elseif f==zero
        IFun([0.0],d)
    elseif f==one
        IFun([1.0],d)    
    elseif method == "zerocoefficients"
        zerocfsIFun(f,d)
    elseif method == "abszerocoefficients"
        abszerocfsIFun(f,d)
    else
        randomIFun(f,d)    
    end
end

##Coefficient routines

coefficients(f::IFun)=coefficients(f,ChebyshevSpace(domain(f)))

##Convert routines


Base.convert{T<:Number}(::Type{IFun{T}},x::Number)=IFun([one(T)*x],ConstantSpace())
Base.convert(::Type{IFun{Complex{Float64}}},f::IFun)=IFun(convert(Vector{Complex{Float64}},f.coefficients),f.space)
Base.promote_rule{T<:Number}(::Type{IFun{Complex{Float64}}},::Type{IFun{T}})=IFun{Complex{Float64}}
Base.promote_rule{T<:Number,IF<:IFun}(::Type{IF},::Type{T})=IF

for op in (:(Base.zero),:(Base.one))
    @eval begin
        ($op){T}(::Type{IFun{T}})=IFun([$op(T)],ConstantSpace())
    end
end


##Evaluation


Base.getindex(f::IFun,x)=evaluate(f,x)
evaluate(f::IFun,x)=clenshaw(coefficients(f),tocanonical(f,x))


Base.first(f::IFun)=foldr(-,coefficients(f))
Base.last(f::IFun)=reduce(+,coefficients(f))


space(f::IFun)=f.space
spacescompatible(f::IFun,g::IFun)=typeof(f.space)<:ConstantSpace || typeof(g.space)<:ConstantSpace || f.space == g.space
domainscompatible(f::IFun,g::IFun)=domain(f)==AnyDomain() || domain(g)==AnyDomain() || domain(f) == domain(g)

##Data routines
values(f::IFun)=ichebyshevtransform(coefficients(f)) 
points(f::IFun)=points(domain(f),length(f))
Base.length(f::IFun)=length(f.coefficients)



## Manipulate length


pad!(f::IFun,n::Integer)=pad!(f.coefficients,n)
pad(f::IFun,n::Integer)=IFun(pad(f.coefficients,n),f.space)


function chop!(f::IFun,tol::Real)
    chop!(f.coefficients,tol)
    if length(f.coefficients) == 0
        f.coefficients = [0.]
    end
    
    f
end
chop(f::IFun,tol)=chop!(IFun(copy(f.coefficients),f.space),tol)
chop!(f::IFun)=chop!(f,eps())


## Addition and multiplication




for op = (:+,:-)
    @eval begin
        function ($op)(f::IFun,g::IFun)
            @assert domainscompatible(f,g)
        
            n = max(length(f),length(g))
            f2 = pad(f,n); g2 = pad(g,n)
            
            IFun(($op)(coefficients(f2),coefficients(g2)),f.space)
        end

        function ($op){N<:Number,T<:Number}(f::IFun{T},c::N)
            n=length(f)
            
            v=Array(promote_type(N,T),n==0?1:n)
            cfs=coefficients(f)
            v[1] =($op)(n==0?$zero(T):cfs[1],c)
            
            if n>1
                v[2:end]=cfs[2:end]
            end
            
            IFun(v,domain(f))
        end
    end
end 



function .*(f::IFun,g::IFun)
    @assert f.space == g.space
    #TODO Coefficient space version
    n = length(f) + length(g) - 1
    f2 = pad(f,n); g2 = pad(g,n)
    
    chop!(IFun(chebyshevtransform(values(f2).*values(g2)),f.space),10eps())
end

fasttimes(f2,g2)=IFun(chebyshevtransform(values(f2).*values(g2)),f2.space)




for op = (:*,:.*,:./,:/)
    @eval ($op)(f::IFun,c::Number) = IFun(($op)(f.coefficients,c),f.space)
end 

-(f::IFun)=IFun(-f.coefficients,f.space)
-(c::Number,f::IFun)=-(f-c)


for op = (:*,:.*,:+)
    @eval ($op)(c::Number,f::IFun)=($op)(f,c)
end




function .^(f::IFun,k::Integer)
    if k == 0
        1.
    elseif k > 0
        f.*f.^(k-1)
    else
        f./f.^(k+1)
    end
end


## Norm

import Base.norm

norm(f::IFun)=real(sqrt(sum(f.*conj(f))))



## Mapped functions

import Base.imag, Base.real, Base.conj

for op = (:real,:imag,:conj) 
    ##TODO: this assumes real space
    @eval ($op)(f::IFun) = IFun(($op)(f.coefficients),f.space)
end

Base.abs2(f::IFun{Float64})=f.^2
Base.abs2(f::IFun{Complex{Float64}})=real(f).^2+imag(f).^2

##  integration

differentiate(f::IFun)=IFun(differentiate(f.space,f.coefficients),f.space)
integrate(f::IFun)=IFun(integrate(f.space,f.coefficients),f.space)
function Base.sum(sp::IntervalDomainSpace,cfs::Vector)
    cf=integrate(sp,cfs)
    last(cf) - first(cf)
end


function Base.cumsum(f::IFun)
    cf = integrate(f)
    cf - first(cf)
end

Base.sum(f::IFun)=sum(f.space,f.coefficients)




function differentiate(f::IFun,k::Integer)
    @assert k >= 0
    (k==0)?f:differentiate(differentiate(f),k-1)
end

Base.diff(f::IFun,n...)=differentiate(f,n...)



==(f::IFun,g::IFun) =  (f.coefficients == g.coefficients && f.space == g.space)



include("roots.jl")
