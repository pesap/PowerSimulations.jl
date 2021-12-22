abstract type AbstractModelStore end

# Required methods for subtypes:
# = initialize_storage!
# - write_result!
# - read_results
# - write_optimizer_stats!
# - read_optimizer_stats
#
# Each subtype must have a field for each instance of STORE_CONTAINERS.

function Base.empty!(store::AbstractModelStore)
    stype = typeof(store)
    for (name, type) in zip(fieldnames(stype), fieldtypes(stype))
        val = getfield(store, name)
        try
            empty!(val)
        catch
            @error "Base.empty! must be customized for type $stype or skipped"
            rethrow()
        end
    end
end

function Base.isempty(store::AbstractModelStore)
    stype = typeof(store)
    for (name, type) in zip(fieldnames(stype), fieldtypes(stype))
        val = getfield(store, name)
        try
            !isempty(val) && return false
        catch
            @error "Base.isempty must be customized for type $stype or skipped"
            rethrow()
        end
    end

    return true
end
function list_fields(store::AbstractModelStore, container_type::Symbol)
    return keys(getfield(store, container_type))
end

function write_result!(store::AbstractModelStore, key, index, array, columns)
    field = get_store_container_type(key)
    return write_result!(store, field, key, index, array, columns)
end

function read_results(store::AbstractModelStore, key, index = nothing)
    field = get_store_container_type(key)
    return read_results(store, field, key, index)
end

function read_results(
    ::Type{DataFrames.DataFrame},
    store::AbstractModelStore,
    container_type::Symbol,
    key,
    index = nothing,
)
    return read_results(store, container_type, key, index)
end

function list_keys(store::AbstractModelStore, container_type)
    container = getfield(store, container_type)
    return collect(keys(container))
end

function get_variable_value(
    store::AbstractModelStore,
    ::T,
    ::Type{U},
) where {T <: VariableType, U <: Union{PSY.Component, PSY.System}}
    return store.variables[VariableKey(T, U)]
end

function get_aux_variable_value(
    store::AbstractModelStore,
    ::T,
    ::Type{U},
) where {T <: AuxVariableType, U <: Union{PSY.Component, PSY.System}}
    return store.aux_variables[AuxVarKey(T, U)]
end

function get_dual_value(
    store::AbstractModelStore,
    ::T,
    ::Type{U},
) where {T <: ConstraintType, U <: Union{PSY.Component, PSY.System}}
    return store.duals[ConstraintKey(T, U)]
end

function get_parameter_value(
    store::AbstractModelStore,
    ::T,
    ::Type{U},
) where {T <: ParameterType, U <: Union{PSY.Component, PSY.System}}
    return store.parameters[ParameterKey(T, U)]
end
