"""
    optimal_threshold_intervention(prob, [p1 = prob.p], p2, obs, threshold, duration; maxtime)

## Arguments

  - `p1`: parameters for the pre-intervention scenario. Defaults to `prob.p`.
  - `p2`: parameters for the pose-intervention scenario.
  - `obs`: The observation symbolic expression.
  - `threshold`: The threshold for the observation.
  - `duration`: Duration for the evaluation of intervention.

## Keyword Arguments

  - `maxtime`: Maximum optimzation time. Defaults to `60`.

# Returns

  - `opt_tspan`: Optimal intervention time span.
  - `(s1, s2, s3)`: Pre-intervention, intervention, post-intervention solutions.
  - `ret`: Return code from the optimization.
"""
function optimal_threshold_intervention(prob, p2, obs, threshold, duration; kw...)
    p1 = prob.p
    optimal_threshold_intervention(prob, p1, p2, obs, threshold, duration; kw...)
end
function optimal_threshold_intervention(prob, p1, p2, obs, threshold, duration;
                                        maxtime = 60, kw...)
    t0 = prob.tspan[1]
    prob1 = remake(prob, p = p1)
    prob2 = remake(prob, p = p2)

    function cost(x::Vector, grad::Vector)
        return x[2] - x[1]
    end

    function duration_constraint(x::Vector, grad::Vector, ::Val{p} = Val(false)) where {p}
        prob_preintervention = remake(prob1, tspan = (t0, x[1]))
        sol_preintervention = stop_at_threshold(prob_preintervention, obs, threshold; kw...)
        violation = x[1] - sol_preintervention.t[end]
        violation > 0 && return violation + (duration - (x[1] - t0))

        prob_intervention = remake(prob2, u0 = sol_preintervention.u[end],
                                   tspan = (x[1], x[2]))
        sol_intervention = stop_at_threshold(prob_intervention, obs, threshold; kw...)
        violation = x[2] - sol_intervention.t[end]
        violation > 0 && return violation + (duration - (x[2] - t0))

        prob_postintervention = remake(prob1, u0 = sol_intervention.u[end],
                                       tspan = (x[2], t0 + duration))
        sol_postintervention = stop_at_threshold(prob_postintervention, obs, threshold;
                                                 kw...)
        violation = t0 + duration - sol_postintervention.t[end]
        return p ?
               (violation, (sol_preintervention, sol_intervention, sol_postintervention)) :
               violation
    end
    function start_end_constraint(x::Vector, grad::Vector)
        x[1] - x[2]
    end

    opt = Opt(:GN_ISRES, 2)
    opt.lower_bounds = [t0, t0]
    opt.upper_bounds = [t0 + duration, t0 + duration]
    opt.xtol_rel = 1e-4

    opt.min_objective = cost
    inequality_constraint!(opt, duration_constraint, 1e-16)
    inequality_constraint!(opt, start_end_constraint, 1e-8)
    opt.maxtime = maxtime
    init_x = [t0, t0 + duration]
    (optf, optx, ret) = NLopt.optimize(opt, init_x)
    _, (s1, s2, s3) = duration_constraint(optx, [], Val(true))
    optx, (s1, s2, s3), ret
end

"""
    optimal_parameter_intervention_for_threshold(prob, [p1 = prob.p], obs, threshold, cost, ps, lb, ub, intervention_tspan, duration; maxtime=60)

## Arguments

  - `prob`: An ODEProblem.
  - `p1`: parameters for the pre-intervention scenario. Defaults to `prob.p`.
  - `obs`: The observation symbolic expression.
  - `threshold`: The threshold for the observation.
  - `cost`: the cost function for minimization, e.g. `α + 20 * β`.
  - `ps`: the parameters that appear in the cost, e.g. `[α, β]`.
  - `lb`: the lower bounds of the parameters e.g. `[-10, -5]`.
  - `ub`: the uppwer bounds of the parameters e.g. `[5, 10]`.
  - `intervention_tspan`: intervention time span, e.g. `(20.0, 30.0)`. Defaults to `prob.tspan`.
  - `duration`: Duration for the evaluation of intervention. Defaults to `prob.tspan[2] - prob.tspan[1]`.

## Keyword Arguments

  - `maxtime`: Maximum optimzation time. Defaults to `60`.

# Returns

  - `opt_p`: Optimal intervention parameters.
  - `(s1, s2, s3)`: Pre-intervention, intervention, post-intervention solutions.
  - `ret`: Return code from the optimization.
"""
function optimal_parameter_intervention_for_threshold(prob, obs, threshold, cost, ps, lb,
                                                      ub,
                                                      intervention_tspan = prob.tspan,
                                                      duration = abs(-(prob.tspan...));
                                                      kw...)
    p1 = prob.p
    optimal_parameter_intervention_for_threshold(prob, p1, obs, threshold, cost, ps, lb, ub,
                                                 intervention_tspan, duration; kw...)
end
function optimal_parameter_intervention_for_threshold(prob, p1, obs, threshold,
                                                      symbolic_cost, ps, lb, ub,
                                                      intervention_tspan, duration;
                                                      maxtime = 60, kw...)
    t0 = prob.tspan[1]
    prob1 = remake(prob, p = p1)
    ti_start, ti_end = intervention_tspan
    symbolic_cost = Symbolics.unwrap(symbolic_cost)
    #ps = collect(ModelingToolkit.vars(symbolic_cost))
    _cost = Symbolics.build_function(symbolic_cost, ps, expression = Val{false})
    _cost(p1) # just throw when something is wrong during the setup.

    cost = let _cost = _cost
        (x, grad) -> _cost(x)
    end

    function duration_constraint(x::Vector, grad::Vector, ::Val{p} = Val(false)) where {p}
        prob_preintervention = remake(prob1, tspan = (t0, ti_start))
        sol_preintervention = stop_at_threshold(prob_preintervention, obs, threshold; kw...)
        violation = ti_start - sol_preintervention.t[end]
        violation > 0 && return p ? (sol_preintervention, nothing, nothing) :
               (violation + (duration - (ti_start - t0)))

        prob_intervention = remake(prob, u0 = sol_preintervention.u[end], p = ps .=> x,
                                   tspan = (ti_start, ti_end))
        sol_intervention = stop_at_threshold(prob_intervention, obs, threshold; kw...)
        violation = ti_end - sol_intervention.t[end]
        violation > 0 && return p ? (sol_preintervention, sol_intervention, nothing) :
               (violation + (duration - (ti_end - ti_start)))

        prob_postintervention = remake(prob1, u0 = sol_intervention.u[end],
                                       tspan = (ti_end, t0 + duration))
        sol_postintervention = stop_at_threshold(prob_postintervention, obs, threshold;
                                                 kw...)
        violation = t0 + duration - sol_postintervention.t[end]
        return p ?
               (sol_preintervention, sol_intervention, sol_postintervention) :
               violation
    end

    opt = Opt(:GN_ISRES, length(ps))
    opt.lower_bounds = lb
    opt.upper_bounds = ub
    opt.xtol_rel = 1e-4

    opt.min_objective = cost
    inequality_constraint!(opt, duration_constraint, 1e-16)
    opt.maxtime = maxtime
    init_x = @. lb + ub / 2
    (optf, optx, ret) = NLopt.optimize(opt, init_x)
    ss = duration_constraint(optx, [], Val(true))
    Dict(ps .=> optx), ss, ret
end
