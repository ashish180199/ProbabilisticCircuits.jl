using LightGraphs
using SimpleWeightedGraphs
using MetaGraphs

#####################
# Learn a Chow-Liu tree from weighted data
#####################

const CLT = Union{MetaDiGraph, SimpleDiGraph}

"""
learn a Chow-Liu tree from training set `train_x`, with Laplace smoothing factor `α`,
for simplification, if `parametered=false`, CPTs are not cached in vertices,
to get parameters, run `learn_prob_circuit` as wrapper;
if `parametered=true`, cache CPTs in vertices.
"""
function learn_chow_liu_tree(train_x::XData; α = 0.0001, parametered=true, clt_root="graph_center")
    learn_chow_liu_tree(WXData(train_x);α=α, parametered=parametered, clt_root=clt_root)
end

function learn_chow_liu_tree(train_x::WXData; α=0.0001, parametered=true, clt_root="graph_center")
    features_num = num_features(train_x)

    # calculate mutual information
    (dis_cache, MI) = mutual_information(feature_matrix(train_x), Data.weights(train_x); α = α)

    # maximum spanning tree/ forest
    g = SimpleWeightedGraph(complete_graph(features_num))
    mst_edges = kruskal_mst(g,- MI)
    tree = SimpleGraph(features_num)
    map(mst_edges) do edge
        add_edge!(tree, src(edge), dst(edge))
    end

    # Build rooted tree / forest
    if clt_root == "graph_center"
        clt = SimpleDiGraph(features_num)
        if nv(tree) == ne(tree) + 1
            clt = bfs_tree(tree, LightGraphs.center(tree)[1])
        else
            for c in filter(c -> (length(c) > 1), connected_components(tree))
                sg, vmap = induced_subgraph(tree, c)
                sub_root = vmap[LightGraphs.center(sg)[1]]
                clt = union(clt, bfs_tree(tree, sub_root))
            end
        end
    elseif clt_root == "rand"
        roots = [rand(c) for c in connected_components(tree)]
        clt = SimpleDiGraph(features_num)
        for root in roots clt = union(clt, bfs_tree(tree, root)) end
    end
    

    # if parametered, cache CPTs in vertices
    if parametered
        clt = MetaDiGraph(clt)
        parent = parent_vector(clt)
        for (c, p) in enumerate(parent)
            set_prop!(clt, c, :parent, p)
        end

        for v in vertices(clt)
            p = parent[v]
            cpt_matrix = get_cpt(p, v, dis_cache)
            set_prop!(clt, v, :cpt, cpt_matrix)
        end
    end

    return clt
end

function get_cpt(parent, child, dis_cache)
    if parent == 0
        p = dis_cache.marginal[child, :]
        return Dict(0=>p[1], 1=>p[2])
    else
        p = dis_cache.pairwise[child, parent, :] ./ [dis_cache.marginal[parent, :]; dis_cache.marginal[parent, :]]
        @. p[isnan(p)] = 0; @. p[p==Inf] = 0; @. p[p == -Inf] = 0
        return Dict((0,0)=>p[1], (1,0)=>p[3], (0,1)=>p[2], (1,1)=>p[4]) #p(child|parent)
    end
end


"Get parent vector of a tree"
function parent_vector(tree::CLT)::Vector{Int64}
    v = zeros(Int64, nv(tree)) # parent of roots is 0
    foreach(e->v[dst(e)] = src(e), edges(tree))
    return v
end

#####################
# Methods for test
#####################
"Print edges and vertices of a ChowLiu tree"
function print_tree(clt::CLT)
    for e in edges(clt) print(e); print(" ");end
    if clt isa SimpleDiGraph
        for v in vertices(clt) print(v); print(" "); end
    end
    if clt isa MetaDiGraph
        for v in vertices(clt) print(v); print(" "); println(props(clt, v)) end
    end
end

"Parse a clt from given file"
function parse_clt(filename::String)::MetaDiGraph
    f = open(filename)
    n = parse(Int32,readline(f))
    n_root = parse(Int32,readline(f))
    clt = MetaDiGraph(n)
    for i in 1 : n_root
        root, prob = split(readline(f), " ")
        root, prob = parse(Int32, root), parse(Float64, prob)
        set_prop!(clt, root, :parent, 0)
        set_prop!(clt, root, :cpt, Dict(1=>prob,0=>1-prob))
    end

    for i = 1 : n - n_root
        dst, src, prob1, prob0 = split(readline(f), " ")
        dst, src, prob1, prob0 = parse(Int32, dst), parse(Int32, src), parse(Float64, prob1), parse(Float64, prob0)
        add_edge!(clt, src,dst)
        set_prop!(clt, dst, :parent, src)
        set_prop!(clt, dst, :cpt, Dict((1,1)=>prob1, (0,1)=>1-prob1, (1,0)=>prob0, (0,0)=>1-prob0))
    end
    return clt
end