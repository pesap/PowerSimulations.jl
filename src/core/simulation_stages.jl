######## Internal Simulation Object Structs ########
mutable struct StageInternal
    number::Int64
    executions::Int64
    execution_count::Int64
    synchronized_executions::Dict{Int64, Int64} # Number of executions per upper level stage step
    psi_container::Union{Nothing, PSIContainer}
    cache_dict::Dict{Type{<:AbstractCache}, AbstractCache}
    # Can probably be eliminated and use getter functions from
    # Simulation object. Need to determine if its always available in the stage update steps.
    chronolgy_dict::Dict{Int64, <:AbstractChronology}
    function StageInternal(number, executions, execution_count, psi_container)
        new(number, executions, execution_count, Dict{Int64, Int64}(), psi_container,
        Dict{Type{<:AbstractCache}, AbstractCache}(),
        Dict{Int64, AbstractChronology}())
    end
end

@doc raw"""
    Stage({M<:AbstractOperationsProblem}
        template::OperationsProblemTemplate
        sys::PSY.System
        optimizer::JuMP.OptimizerFactory
        internal::Union{Nothing, StageInternal}
        )

""" # TODO: Add DocString
mutable struct Stage{M<:AbstractOperationsProblem}
    template::OperationsProblemTemplate
    sys::PSY.System
    optimizer::JuMP.OptimizerFactory
    internal::Union{Nothing, StageInternal}

    function Stage(::Type{M},
                   template::OperationsProblemTemplate,
                   sys::PSY.System,
                   optimizer::JuMP.OptimizerFactory) where M<:AbstractOperationsProblem

    new{M}(template,
           sys,
           optimizer,
           nothing)

    end
end

function Stage(template::OperationsProblemTemplate,
               sys::PSY.System,
               optimizer::JuMP.OptimizerFactory) where M<:AbstractOperationsProblem
    return Stage(GenericOpProblem, template, sys, optimizer)
end

get_execution_count(s::Stage) = s.internal.execution_count
get_executions(s::Stage) = s.internal.executions
get_sys(s::Stage) = s.sys
get_template(s::Stage) = s.template
get_number(s::Stage) = s.internal.number
get_psi_container(s::Stage) = s.internal.psi_container

# This makes the choice in which variable to get from the results.
function get_stage_variable(::Type{RecedingHorizon},
                           stages::Pair{Stage{T}, Stage{T}},
                           device_name::String,
                           var_ref::UpdateRef) where T <: AbstractOperationsProblem

    variable = get_value(stages.first.internal.psi_container, var_ref)
    step = axes(variable)[2][1]
    return JuMP.value(variable[device_name, step])
end

function get_stage_variable(::Type{Consecutive},
                             stages::Pair{Stage{T}, Stage{T}},
                             device_name::String,
                             var_ref::UpdateRef) where T <: AbstractOperationsProblem
    variable = get_value(stages.first.internal.psi_container, var_ref)
    step = axes(variable)[2][end]
    return JuMP.value(variable[device_name, step])
end

function get_stage_variable(::Type{Synchronize},
                            stages::Pair{Stage{T}, Stage{T}},
                            device_name::String,
                            var_ref::UpdateRef) where T <: AbstractOperationsProblem
    variable = get_value(stages.first.internal.psi_container, var_ref)
    step = axes(variable)[2][stages.second.internal.execution_count + 1]
    return JuMP.value(variable[device_name, step])
end

#Defined here because it requires Stage to defined

initial_condition_update!(initial_condition_key::ICKey,
                          ::Nothing,
                          ini_cond_vector::Vector{InitialCondition},
                          to_stage::Stage,
                          from_stage::Stage) = nothing

function initial_condition_update!(initial_condition_key::ICKey,
                                    sync::Chron,
                                    ini_cond_vector::Vector{InitialCondition},
                                    to_stage::Stage,
                                    from_stage::Stage) where Chron <: AbstractChronology
    for ic in ini_cond_vector
        name = device_name(ic)
        update_ref = ic.update_ref
        var_value = get_stage_variable(Chron, (from_stage => to_stage), name, update_ref)
        cache = get(from_stage.internal.cache_dict, ic.cache, nothing)
        quantity = calculate_ic_quantity(initial_condition_key, ic, var_value, cache)
        PJ.fix(ic.value, quantity)
    end

    return
end
