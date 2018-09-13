using RigidBodyDynamics
using Random
using Profile
using BenchmarkTools

const ScalarType = Float64
# const ScalarType = Float32

function create_floating_atlas()
    urdf = joinpath(@__DIR__, "..", "atlas.urdf")
    atlas = parse_urdf(ScalarType, urdf)
    for joint in out_joints(root_body(atlas), atlas)
        floatingjoint = Joint(string(joint), frame_before(joint), frame_after(joint), QuaternionFloating{ScalarType}())
        replace_joint!(atlas, joint, floatingjoint)
    end
    atlas
end

function create_benchmark_suite()
    suite = BenchmarkGroup()
    mechanism = create_floating_atlas()
    remove_fixed_tree_joints!(mechanism)

    state = MechanismState{ScalarType}(mechanism)
    result = DynamicsResult{ScalarType}(mechanism)
    nv = num_velocities(state)
    mat = MomentumMatrix(root_frame(mechanism), Matrix{ScalarType}(undef, 3, nv), Matrix{ScalarType}(undef, 3, nv))
    torques = similar(velocity(state))
    rfoot = findbody(mechanism, "r_foot")
    lhand = findbody(mechanism, "l_hand")
    p = path(mechanism, rfoot, lhand)
    jac = GeometricJacobian(default_frame(lhand), default_frame(rfoot), root_frame(mechanism),
        Matrix{ScalarType}(undef, 3, nv), Matrix{ScalarType}(undef, 3, nv))

    suite["mass_matrix!"] = @benchmarkable(begin
        setdirty!($state)
        mass_matrix!($(result.massmatrix), $state)
    end, setup = rand!($state), evals = 10)

    suite["dynamics_bias!"] = @benchmarkable(begin
        setdirty!($state)
        dynamics_bias!($result, $state)
    end, setup = begin
        rand!($state)
    end, evals = 10)

    suite["inverse_dynamics!"] = @benchmarkable(begin
        setdirty!($state)
        inverse_dynamics!($torques, $(result.jointwrenches), $(result.accelerations), $state, v̇, externalwrenches)
    end, setup = begin
        v̇ = similar(velocity($state))
        rand!(v̇)
        externalwrenches = RigidBodyDynamics.BodyDict(convert(BodyID, body) => rand(Wrench{ScalarType}, root_frame($mechanism)) for body in bodies($mechanism))
        rand!($state)
    end, evals = 10)

    suite["dynamics!"] = @benchmarkable(begin
        setdirty!($state)
        dynamics!($result, $state, τ, externalwrenches)
    end, setup = begin
        rand!($state)
        τ = similar(velocity($state))
        rand!(τ)
        externalwrenches = RigidBodyDynamics.BodyDict(convert(BodyID, body) => rand(Wrench{ScalarType}, root_frame($mechanism)) for body in bodies($mechanism))
    end, evals = 10)

    suite["momentum_matrix!"] = @benchmarkable(begin
        setdirty!($state)
        momentum_matrix!($mat, $state)
    end, setup = rand!($state), evals = 10)

    suite["geometric_jacobian!"] = @benchmarkable(begin
        setdirty!($state)
        geometric_jacobian!($jac, $state, $p)
    end, setup = rand!($state), evals = 10)

    suite["mass_matrix! and geometric_jacobian!"] = @benchmarkable(begin
        setdirty!($state)
        mass_matrix!($(result.massmatrix), $state)
        geometric_jacobian!($jac, $state, $p)
    end, setup = begin
        rand!($state)
    end, evals = 10)

    suite
end

function runbenchmarks()
    suite = create_benchmark_suite()
    Profile.clear_malloc_data()
    overhead = BenchmarkTools.estimate_overhead()
    Random.seed!(1)
    results = run(suite, verbose=true, overhead=overhead, gctrial=false)
    for result in results
        println("$(first(result)):")
        display(last(result))
        println()
    end
end

runbenchmarks()
