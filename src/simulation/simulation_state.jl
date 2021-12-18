struct SimulationState
    current_time::Base.RefValue{Dates.DateTime}
    end_of_step_timestamp::Base.RefValue{Dates.DateTime}
    decision_states::ValueStates
    system_states::ValueStates
end

function SimulationState()
    return SimulationState(
        Ref(UNSET_INI_TIME),
        Ref(UNSET_INI_TIME),
        ValueStates(),
        ValueStates(),
    )
end

get_end_of_step_timestamp(s::SimulationState) = s.end_of_step_timestamp[]
get_current_time(s::SimulationState) = s.current_time[]

function set_end_of_step_timestamp!(s::SimulationState, val::Dates.DateTime)
    s.end_of_step_timestamp[] = val
    return
end

function set_current_time!(s::SimulationState, val::Dates.DateTime)
    s.current_time[] = val
    return
end

get_decision_states(s::SimulationState) = s.decision_states
get_system_states(s::SimulationState) = s.system_states

const STATE_TIME_PARAMS = NamedTuple{(:horizon, :resolution), NTuple{2, Dates.Millisecond}}

function _get_state_params(models::SimulationModels, simulation_step::Dates.Period)
    params = OrderedDict{OptimizationContainerKey, STATE_TIME_PARAMS}()
    for model in get_decision_models(models)
        container = get_optimization_container(model)
        model_resolution = get_resolution(model)
        model_interval = get_interval(model)
        horizon_step = get_horizon(model) * model_resolution
        # This is the portion of the Horizon that "overflows" into the next step
        time_residual = horizon_step - model_interval
        for type in fieldnames(ValueStates)
            field_containers = getfield(container, type)
            for key in keys(field_containers)
                if !haskey(params, key)
                    params[key] = (
                        horizon = max(simulation_step + time_residual, horizon_step),
                        resolution = model_resolution,
                    )
                else
                    params[key] = (
                        horizon = max(params[key].horizon, horizon_step),
                        resolution = min(params[key].resolution, model_resolution),
                    )
                end
            end
        end
    end
    return params
end

function _initialize_model_states!(
    sim_state::SimulationState,
    model::OperationModel,
    simulation_initial_time::Dates.DateTime,
    params::OrderedDict{OptimizationContainerKey, STATE_TIME_PARAMS},
)
    states = get_decision_states(sim_state)
    container = get_optimization_container(model)
    for field in fieldnames(ValueStates)
        field_containers = getfield(container, field)
        field_states = getfield(states, field)
        for (key, value) in field_containers
            # TODO: Handle case of sparse_axis_array
            value_counts = params[key].horizon ÷ params[key].resolution
            if length(axes(value)) == 1
                column_names = [string(encode_key(key))]
            elseif length(axes(value)) == 2
                column_names, _ = axes(value)
            else
                @warn("Multidimensional Array caching is not currently supported")
                continue
            end
            if !haskey(field_states, key) || length(field_states[key]) < value_counts
                field_states[key] = ValueState(
                    DataFrames.DataFrame(
                        fill(NaN, value_counts, length(column_names)),
                        column_names,
                    ),
                    collect(
                        range(
                            simulation_initial_time,
                            step = params[key].resolution,
                            length = value_counts,
                        ),
                    ),
                    params[key].resolution,
                )
            end
        end
    end
    return
end

function _initialize_system_states!(
    sim_state::SimulationState,
    ::Nothing,
    simulation_initial_time::Dates.DateTime,
    params::OrderedDict{OptimizationContainerKey, STATE_TIME_PARAMS},
)
    decision_states = get_decision_states(sim_state)
    emulator_states = get_system_states(sim_state)
    for key in get_state_keys(decision_states)
        cols = DataFrames.names(get_state_values(decision_states, key))
        set_state_data!(
            emulator_states,
            key,
            ValueState(
                DataFrames.DataFrame(cols .=> NaN),
                [simulation_initial_time],
                params[key].resolution,
            ),
        )
    end
    return
end

function initialize_simulation_state!(
    sim_state::SimulationState,
    models::SimulationModels,
    simulation_step::Dates.Period,
    simulation_initial_time::Dates.DateTime,
)
    params = _get_state_params(models, simulation_step)
    for model in get_decision_models(models)
        _initialize_model_states!(sim_state, model, simulation_initial_time, params)
    end

    min_resolution = minimum([v[2] for v in values(params)])
    set_end_of_step_timestamp!(
        sim_state,
        simulation_initial_time + simulation_step - min_resolution,
    )

    em = get_emulation_model(models)
    _initialize_system_states!(sim_state, em, simulation_initial_time, params)
    return
end

function update_state_data!(
    key::VariableKey,
    state::SimulationState,
    store_data::DataFrames.DataFrame,
    simulation_time::Dates.DateTime,
    model_params::ModelStoreParams,
    end_of_step_timestamp::Dates.DateTime,
)
    state_data = get_decision_state_data(state, key)
    model_resolution = get_resolution(model_params)
    state_resolution = get_data_resolution(state_data)
    resolution_ratio = model_resolution ÷ state_resolution
    @assert_op resolution_ratio >= 1

    if simulation_time > end_of_step_timestamp
        state_data_index = 1
        state_data.timestamps[:] .=
            range(simulation_time, step = state_resolution, length = length(state_data))
    else
        state_data_index = find_timestamp_index(get_timestamps(state_data), simulation_time)
    end

    offset = resolution_ratio - 1
    result_time_index = axes(store_data)[1]
    set_last_recorded_row!(state_data, state_data_index)
    # This implementation can fail if the names aren't in the same order.
    @assert_op sort(DataFrames.names(state_data.values)) ==
               sort(DataFrames.names(store_data))

    for t in result_time_index
        state_range = state_data_index:(state_data_index + offset)
        for j in DataFrames.names(store_data)
            for i in state_range
                # TODO: We could also interpolate here
                state_data.values[i, j] = store_data[t, j]
            end
        end
        state_data_index += resolution_ratio
    end

    return
end

function update_state_data!(
    key::AuxVarKey{S, T},
    state::SimulationState,
    store_data::DataFrames.DataFrame,
    simulation_time::Dates.DateTime,
    model_params::ModelStoreParams,
    end_of_step_timestamp::Dates.DateTime,
) where {T <: PSY.Component, S <: Union{TimeDurationOff, TimeDurationOn}}
    state_data = get_decision_state_data(state, key)
    model_resolution = get_resolution(model_params)
    state_resolution = get_data_resolution(state_data)
    resolution_ratio = model_resolution ÷ state_resolution
    @assert_op resolution_ratio >= 1

    if simulation_time > end_of_step_timestamp
        state_data_index = 1
        state_data.timestamps[:] .=
            range(simulation_time, step = state_resolution, length = length(state_data))
    else
        state_data_index = find_timestamp_index(get_timestamps(state_data), simulation_time)
    end

    offset = resolution_ratio - 1
    result_time_index = axes(store_data)[1]
    set_last_recorded_row!(state_data, state_data_index)
    # This implementation can fail if the names aren't in the same order.
    @assert_op sort(DataFrames.names(state_data.values)) ==
               sort(DataFrames.names(store_data))

    if (model_resolution/state_resolution) == 1.0
        increment_per_period = 1.0
    elseif state_resolution < Dates.Hour(1) && state_resolution > Dates.Minute(1)
        increment_per_period =  Dates.value(Dates.Minute(state_resolution))
    end

    for t in result_time_index
        state_range = state_data_index:(state_data_index + offset)
        for j in DataFrames.names(store_data)
            for i in state_range
                if t == 1 && i == 1
                    if store_data[t, j] > 1
                        # Account for the fact that previous model stores the state at the end of the hour/period
                        # we take look one timestep back. As all models save Duration data based on its resolution/timesteps
                        #  The 2nd terms scales the data to the state resolution.
                        state_data.values[i, j] = (store_data[t, j] - 1.0) *  (model_resolution/state_resolution) 
                    else
                        state_data.values[i, j] = store_data[t, j]  *  (model_resolution/state_resolution) 
                    end
                else
                    state_data.values[i, j] = store_data[t, j] >  0 ? state_data.values[i-1, j] + increment_per_period : 0
                end
            end
        end
        state_data_index += resolution_ratio
    end

    return
end


function get_decision_state_data(state::SimulationState, key::OptimizationContainerKey)
    return get_state_data(get_decision_states(state), key)
end

function get_decision_state_value(state::SimulationState, key::OptimizationContainerKey)
    return get_state_values(get_decision_states(state), key)
end

function get_decision_state_value(
    state::SimulationState,
    key::OptimizationContainerKey,
    date::Dates.DateTime,
)
    return get_state_values(get_decision_states(state), key, date)
end

function get_system_state_data(state::SimulationState, key::OptimizationContainerKey)
    return get_state_data(get_system_states(state), key)
end

function get_system_state_value(state::SimulationState, key::OptimizationContainerKey)
    return get_state_values(get_system_states(state), key)[1, :]
end

function get_system_state_value(
    state::SimulationState,
    ::T,
    ::Type{U},
) where {T <: VariableType, U <: Union{PSY.Component, PSY.System}}
    return get_system_state_value(state, VariableKey(T, U))
end

function get_system_state_value(
    state::SimulationState,
    ::T,
    ::Type{U},
) where {T <: AuxVariableType, U <: Union{PSY.Component, PSY.System}}
    return get_system_state_value(state, AuxVarKey(T, U))
end

function get_system_state_value(
    state::SimulationState,
    ::T,
    ::Type{U},
) where {T <: ConstraintType, U <: Union{PSY.Component, PSY.System}}
    return get_system_state_value(state, ConstraintKey(T, U))
end

function get_system_state_data(
    state::SimulationState,
    ::T,
    ::Type{U},
) where {T <: VariableType, U <: Union{PSY.Component, PSY.System}}
    return get_system_state_data(state, VariableKey(T, U))
end

function get_system_state_data(
    state::SimulationState,
    ::T,
    ::Type{U},
) where {T <: AuxVariableType, U <: Union{PSY.Component, PSY.System}}
    return get_system_state_data(state, AuxVarKey(T, U))
end

function get_system_state_data(
    state::SimulationState,
    ::T,
    ::Type{U},
) where {T <: ConstraintType, U <: Union{PSY.Component, PSY.System}}
    return get_system_state_data(state, ConstraintKey(T, U))
end
