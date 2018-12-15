include("smooth_data.jl")
include("mjo_a.jl")
include("mjo_ex.jl")
include("mjo_sim_pyplot.jl")
include("mjo_imex.jl")

# scheme1: always gives the explicit update. 
#        : (NL^{(n+1)} = EXPLICITscheme(NL^{(n)})
#        : It is either feEXNL or RK4_one
# scheme2: necessary to tell RK4_one to use EXNL instead of dxdt. 
function imex_step(
    state::MJO_State, 
    exstate::MJO_State,
    RHShat::MJO_State_im, 
    outhat::MJO_State_im,
    params::MJO_params, h_time::Float64,
    kx::Array{Complex{Float64},2}, ky::Array{Float64,2}, 
    a::Array{Float64,2}, b::Array{Float64,2}, g::Array{Float64,2},
    f::Array{Float64,2}, d::Array{Float64,2};
    scheme1=feEXNL::Function, # Default is f_euler OR USE RK4_one
    scheme2=true,             # Default is f_euler OR USE EXNL
    )
    Fr = params.Fr;
    # Calculate RHS.
    exstate = scheme1(params, state, exstate, h_time; scheme2=scheme2);
    # Into Fourier/Cos/Sin Space
    dcsft(exstate, RHShat)

    # Implicit solve
    # Applying Lower^{-1}
    #y1 = a .* RHShat.m1;
    #y2 = a .* RHShat.n1
    y3 = a .* (RHShat.h1 - (1/params.Fr) * (
        kx .* RHShat.m1 + ky .* RHShat.n1));
    y4 = RHShat.m2 - kx .* y3;
    y5 = RHShat.n2 + ky .* y3;
    y6 = RHShat.h2 - (1/params.Fr)* (kx .* y4 + ky .* y5);

    # Backward Substitution.
    outhat.h2[:,:] = c .*y6;
    outhat.n2[:,:] = y5 .+ ky .* b* outhat.h2;
    outhat.m2[:,:] = y4 -  kx .* b.* outhat.h2;
    outhat.h1[:,:] = y3 - (1 .- a)* outhat.h2;
    outhat.n1[:,:] = RHShat.n1 + ky.*(outhat.h1 + outhat.h2);
    outhat.m1[:,:] = RHShat.m1 - kx.*(outhat.h1 + outhat.h2);

    # Into Physical Space
    idcsft(exstate, outhat)
    return outhat, exstate
end

function testimex_step(h_time::Float64, every::Int, name::String)
    params = gen_params(h_time);
    IC    = genInitSr(scheme="imex");
    IChat = genInitSr(scheme="im");
    state           = deepcopy(IC);     exstate = deepcopy(IC);
    RHShat          = deepcopy(IChat);  outhat  = deepcopy(IChat);
    kx, ky, a, b, c = imex_init(params, h_time);
    #savecontour(state, name*string(1))
    @printf("i=   1: max = %4.2e, maxhat = %4.2e\n", 
                    maximum(abs.(state.m1)), maximum(norm.(outhat.m1)))
    for i = 2 : Int(ceil((365*24*60*60)/(h_time*2*10^5))) # one year's time
        outhat, state = imex_step(
            state, exstate, RHShat, outhat, 
            params, h_time, kx, ky, a, b, c
            #, scheme1=RK4_one, scheme2=EXNL
            );
        if rem(i, every) ==1
            if istherenan(outhat)==true || isthereinf(outhat)==true
                return i, outhat
            elseif istherenan(state)==true || isthereinf(state)==true
                return i, state
            else
                @printf("i= %3d : max = %4.2e, maxhat = %4.2e\n", 
                    i, maximum(abs.(state.m1)), maximum(norm.(outhat.m1)))
            end
            #savecontour(state, name*string(i), draw=:pcolormesh)#1+div(i,every)))
        end
    end
    return outhat, state
end


function imex(
    IC::MJO_State, IChat::MJO_State_im, params::MJO_params, h_time::Float64, 
    N::Int, every::Int;
    scheme1=feEXNL::Function, #OR USE RK4_one
    scheme2=true, #OR USE EXNL
    )
    state           = deepcopy(IC);     exstate = deepcopy(IC);
    RHShat          = deepcopy(IChat);  outhat  = deepcopy(IChat);
    kx, ky, a, b, c = imex_init(params, h_time);
    evol         = Array{MJO_State,1}(undef, div(N, every)+1)
    evol[1]      = IC;
    for i = 2 : N+1
        state = imex_step(
            state, exstate, RHShat, outhat, 
            params, h_time, kx, ky, a, b, c,
            scheme1=scheme1, scheme2=scheme2
            );
        if istherenan(state)==true||isthereinf(state)==true
            print(i)
            return evol[1:div(i,every)]
        end
        if rem(i, every) ==1
            #=if istherenan(state)==true||isthereinf(state)==true
                print(i)
                return evol[1:div(i,every)]
            end=#
            evol[1+div(i,every)] = state
            #end
        end
    end
    return evol
end



function f_euler_contour(
    initial_state:: MJO_State, 
    params::MJO_params, 
    h::Float64, 
    N::Int, 
    every::Int,
    str::String
    )
    tend = deepcopy(initial_state)
    state = deepcopy(initial_state)
    savecontour(initial_state, str*"1")
    for i = 2 : N+1
        dxdt(params, state, tend);
        if istherenan(tend)==true || isthereinf(tend)==true
            error("We've got a NaN at "*string(i)*"!!! \n")
        end
        state = state + h * tend;
        if rem(i,every)==1
            savecontour(state, str*string(1+div(i,every)))
        end
    end
    return state
end

function RK4_contour(
    initial_state:: MJO_State, 
    params::MJO_params, 
    h::Float64, 
    N::Int, 
    every::Int,
    str::String
    )
    tend = deepcopy(initial_state)
    state = deepcopy(initial_state)
    savecontour(initial_state, str*"1")
    for i = 2 : N+1
        RK4_one(state, tend, params, h)
        if istherenan(tend)==true || isthereinf(tend)==true
            error("We've got a NaN at "*string(i)*"!!! \n")
        end
        state = state + h * tend;
        if rem(i,every)==1
            savecontour(state, str*string(1+div(i,every)))
        end
    end
    return state
end


