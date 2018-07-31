function activepowervariables(m::JuMP.Model, devices_netinjection::A, devices::Array{T,1}, time_periods::Int64) where {A <: JumpExpressionMatrix, T <: PowerSystems.RenewableGen}

    on_set = [d.name for d in devices]

    t = 1:time_periods

    pre = @variable(m::JuMP.Model, pre[on_set,t] >= 0) # Power output of generators

    devices_netinjection = varnetinjectiterate!(devices_netinjection,  pre, t, devices)

    return pre, devices_netinjection
end

"""
This function adds the power limits of generators when there are no CommitmentVariables
"""
function powerconstraints(m::JuMP.Model, devices::Array{T,1}, time_periods::Int64) where T <: PowerSystems.RenewableGen

    pre = m[:pre]
    time_index = m[:pre].axes[2]
    name_index = m[:pre].axes[1]

    (length(time_index) != time_periods) ? error("Length of time dimension inconsistent"): true

    pmax_re = JuMP.JuMPArray(Array{ConstraintRef}(length.(indices(pre))), name_index, time_index)

    for t in time_index, (ix, name) in enumerate(name_index)

        if name == devices[ix].name
            pmax_re[name, t] = @constraint(m, pre[name, t] <= devices[ix].tech.installedcapacity*devices[ix].scalingfactor.values[t])
        else
            error("Bus name in Array and variable do not match")
        end

    end

    JuMP.registercon(m, :pmax_renewable, pmax_re)

    return m

end
