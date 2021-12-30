# Keep these in sync with the Symbols in src/core/definitions.
get_store_container_type(::AuxVarKey) = STORE_CONTAINER_AUX_VARIABLES
get_store_container_type(::ConstraintKey) = STORE_CONTAINER_DUALS
get_store_container_type(::ExpressionKey) = STORE_CONTAINER_EXPRESSIONS
get_store_container_type(::ParameterKey) = STORE_CONTAINER_PARAMETERS
get_store_container_type(::VariableKey) = STORE_CONTAINER_VARIABLES

function write_results!(
    store,
    model::OperationModel,
    index::Union{Dates.DateTime, Int},
    export_params::Union{Dict{Symbol, Any}, Nothing} = nothing,
)
    write_model_dual_results!(store, model, index, export_params)
    write_model_parameter_results!(store, model, index, export_params)
    write_model_variable_results!(store, model, index, export_params)
    write_model_aux_variable_results!(store, model, index, export_params)
    write_model_expression_results!(store, model, index, export_params)
    return
end

function write_model_dual_results!(
    store,
    model::OperationModel,
    index::Union{Dates.DateTime, Int},
    export_params::Union{Dict{Symbol, Any}, Nothing},
)
    container = get_optimization_container(model)
    model_name = get_name(model)
    if export_params !== nothing
        exports_path = joinpath(export_params[:exports_path], "duals")
        mkpath(exports_path)
    end

    for (key, constraint) in get_duals(container)
        !write_resulting_value(key) && continue
        write_result!(store, model_name, key, index, constraint)

        if export_params !== nothing &&
           should_export_dual(export_params[:exports], index, model_name, key)
            horizon = export_params[:horizon]
            resolution = export_params[:resolution]
            file_type = export_params[:file_type]
            df = axis_array_to_dataframe(constraint, key)
            time_col = range(index, length = horizon, step = resolution)
            DataFrames.insertcols!(df, 1, :DateTime => time_col)
            export_result(file_type, exports_path, key, index, df)
        end
    end
    return
end

function write_model_parameter_results!(
    store,
    model::OperationModel,
    index::Union{Dates.DateTime, Int},
    export_params::Union{Dict{Symbol, Any}, Nothing},
)
    container = get_optimization_container(model)
    model_name = get_name(model)
    if export_params !== nothing
        exports_path = joinpath(export_params[:exports_path], "parameters")
        mkpath(exports_path)
    end

    horizon = get_horizon(get_settings(model))

    parameters = get_parameters(container)
    for (key, container) in parameters
        !write_resulting_value(key) && continue
        param_array = get_parameter_array(container)
        multiplier_array = get_multiplier_array(container)
        @assert_op length(axes(param_array)) == 2
        data = jump_value.(param_array) .* multiplier_array
        write_result!(store, model_name, key, index, data)

        if export_params !== nothing &&
           should_export_parameter(export_params[:exports], index, model_name, key)
            resolution = export_params[:resolution]
            file_type = export_params[:file_type]
            df = axis_array_to_dataframe(data, key)
            time_col = range(index, length = horizon, step = resolution)
            DataFrames.insertcols!(df, 1, :DateTime => time_col)
            export_result(file_type, exports_path, key, index, df)
        end
    end
    return
end

function write_model_variable_results!(
    store,
    model::OperationModel,
    index::Union{Dates.DateTime, Int},
    export_params::Union{Dict{Symbol, Any}, Nothing},
)
    container = get_optimization_container(model)
    model_name = get_name(model)
    if export_params !== nothing
        exports_path = joinpath(export_params[:exports_path], "variables")
        mkpath(exports_path)
    end

    if !isempty(container.primal_values_cache)
        variables = container.primal_values_cache.variables_cache
    else
        variables = get_variables(container)
    end

    for (key, variable) in variables
        !write_resulting_value(key) && continue
        write_result!(store, model_name, key, index, variable)

        if export_params !== nothing &&
           should_export_variable(export_params[:exports], index, model_name, key)
            horizon = export_params[:horizon]
            resolution = export_params[:resolution]
            file_type = export_params[:file_type]
            df = axis_array_to_dataframe(variable, key)
            time_col = range(index, length = horizon, step = resolution)
            DataFrames.insertcols!(df, 1, :DateTime => time_col)
            export_result(file_type, exports_path, key, index, df)
        end
    end
    return
end

function write_model_aux_variable_results!(
    store,
    model::OperationModel,
    index::Union{Dates.DateTime, Int},
    export_params::Union{Dict{Symbol, Any}, Nothing},
)
    container = get_optimization_container(model)
    model_name = get_name(model)
    if export_params !== nothing
        exports_path = joinpath(export_params[:exports_path], "aux_variables")
        mkpath(exports_path)
    end

    for (key, variable) in get_aux_variables(container)
        !write_resulting_value(key) && continue
        write_result!(store, model_name, key, index, variable)

        if export_params !== nothing &&
           should_export_aux_variable(export_params[:exports], index, model_name, key)
            horizon = export_params[:horizon]
            resolution = export_params[:resolution]
            file_type = export_params[:file_type]
            df = axis_array_to_dataframe(variable, key)
            time_col = range(index, length = horizon, step = resolution)
            DataFrames.insertcols!(df, 1, :DateTime => time_col)
            export_result(file_type, exports_path, key, index, df)
        end
    end
    return
end

function write_model_expression_results!(
    store,
    model::OperationModel,
    index::Union{Dates.DateTime, Int},
    export_params::Union{Dict{Symbol, Any}, Nothing},
)
    container = get_optimization_container(model)
    model_name = get_name(model)
    if export_params !== nothing
        exports_path = joinpath(export_params[:exports_path], "expressions")
        mkpath(exports_path)
    end

    if !isempty(container.primal_values_cache)
        expressions = container.primal_values_cache.expressions_cache
    else
        expressions = get_expressions(container)
    end

    for (key, expression) in expressions
        !write_resulting_value(key) && continue
        write_result!(store, model_name, key, index, expression)

        if export_params !== nothing &&
           should_export_expression(export_params[:exports], index, model_name, key)
            horizon = export_params[:horizon]
            resolution = export_params[:resolution]
            file_type = export_params[:file_type]
            df = axis_array_to_dataframe(expression, key)
            time_col = range(index, length = horizon, step = resolution)
            DataFrames.insertcols!(df, 1, :DateTime => time_col)
            export_result(file_type, exports_path, key, index, df)
        end
    end
    return
end
