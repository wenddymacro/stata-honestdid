cap mata mata drop findOptimalFLCI()
cap mata mata drop _findOptimalFLCI_helper()
cap mata mata drop _honestMatrices()
cap mata mata drop _findHForMinimumBias()
cap mata mata drop _computeSigmaLFromW()
cap mata mata drop _createMatricesForVarianceFromW()
cap mata mata drop _honestInverseIndex()
cap mata mata drop _createConstraints()
cap mata mata drop _findLowestH()
cap mata mata drop _qfoldednormal()
cap mata mata drop _flciResults()

mata:
struct _flciResults {
    real vector FLCI
    real vector optimalVec
    real vector optimalPrePeriodVec
    real scalar optimalHalfLength
    real scalar M
    real scalar exitcode
}


struct _flciResults scalar function findOptimalFLCI(
    real vector betahat,
    real matrix sigma,
    real scalar numPrePeriods,
    real scalar numPostPeriods,
    real scalar M,
    | real colvector l_vec,
    real scalar alpha,
    real scalar numPoints)
{
    struct _flciResults scalar results

    if ( args() < 6 ) l_vec = basisVector(1, numPostPeriods)
    if ( args() < 7 ) alpha = 0.05
    if ( args() < 8 ) numPoints = 100

    results = _findOptimalFLCI_helper(sigma,
                                      M,
                                      numPrePeriods,
                                      numPostPeriods,
                                      l_vec,
                                      alpha,
                                      numPoints)

    results.FLCI = (results.optimalVec' * betahat' - results.optimalHalfLength,
                    results.optimalVec' * betahat' + results.optimalHalfLength)

    return(results)
}
end

***********************************************************************
*                                                                     *
*                       _findOptimalFLCI_helper                       *
*                                                                     *
***********************************************************************

mata
struct _flciResults scalar function _findOptimalFLCI_helper(
    real matrix sigma,
    real scalar M,
    real scalar numPrePeriods,
    real scalar numPostPeriods,
    real colvector l_vec,
    real scalar alpha,
    real scalar numPoints)
{
    struct _flciResults scalar results
    real rowvector hGrid
    real colvector sel, selmin
    real scalar h0, hMin, n
    real matrix biasDF

    n      = numPrePeriods + numPostPeriods
    nn     = length((n/2 + 1)::n)
    h0     = _findHForMinimumBias(sigma, numPrePeriods, numPostPeriods, l_vec)
    hMin   = _findLowestH(sigma, numPrePeriods, numPostPeriods, l_vec)
    hGrid  = _honest_linspace(hMin, h0, numPoints)
    biasDF = J(numPoints, 2 + n + 2 * nn, .)
    for (i = 1; i <= numPoints; i++) {
        biasDF[i, .] = _findWorstCaseBiasGivenH(hGrid[i], sigma, numPrePeriods, numPostPeriods, l_vec)
    }
    sel     = selectindex((biasDF[., 1] :== 0) :| (biasDF[., 1] :== 10))
    biasDF  = biasDF[sel, .]
    hGrid   = hGrid'[sel, .]
    maxBias = biasDF[., 2] :* M

    CI_halflength = _qfoldednormal(1-alpha, maxBias :/ hGrid) :* hGrid
    optimalHalfLength = min(CI_halflength)
    selmin = selectindex(optimalHalfLength :== CI_halflength)
    optimal_l = biasDF[selmin, (2 + n + nn + 1)..cols(biasDF)]'

    results.optimalVec          = optimal_l \ l_vec
    results.optimalPrePeriodVec = optimal_l
    results.optimalHalfLength   = optimalHalfLength
    results.M                   = M
    results.exitcode            = biasDF[selmin, 1]

    return(results)
}

real vector function _qfoldednormal(real scalar p,
                                    real vector mu,
                                    | real scalar sd,
                                    real scalar numDraws) {
    real matrix qvector, x
    real vector original, mulong
    real scalar m, i, g

    if ( args() < 3 ) sd = 1
    if ( args() < 4 ) numDraws = 1e3

    original  = order(order(mu, 1), 1)
    normDraws = invnormal(halton(numDraws, 1)) * sd
    mulong    = colshape(J(1, numDraws, mu), 1)
    qvector   = mulong, colshape(J(1, numDraws, 1::length(mu)), 1), abs(J(length(mu), 1, normDraws) + mulong)
    _sort(qvector, (1, 2, 3))
    x = rowshape(qvector[., 3], length(mu))
    m = 1 - p
    i = floor(p * numDraws + m)
    g = numDraws * p + m - i
    return(((1 - g) * x[., i] + g * x[., i + 1])[original])
}
end

***********************************************************************
*                                                                     *
*                        _findHForMinimumBias                         *
*                                                                     *
***********************************************************************

mata
struct _honestMatrices {
    real matrix A_quadratic_sd
    real matrix A_linear_sd
    real matrix A_constant_sd
}

real scalar function _findHForMinimumBias(real matrix sigma,
                                          real scalar numPrePeriods,
                                          real scalar numPostPeriods,
                                          real colvector l_vec)
{
    real scalar hsquared
    real rowvector w
    w = (J(1, (numPrePeriods-1), 0), (1..numPostPeriods) * l_vec)
    hsquared = _computeSigmaLFromW(w, sigma, numPrePeriods, l_vec)
    return(sqrt(hsquared))
}

// Compute variance of affine estmiator with choice w
real scalar function _computeSigmaLFromW(real rowvector w,
                                         real matrix sigma,
                                         real scalar numPrePeriods,
                                         real colvector l_vec)
{
    struct _honestMatrices  scalar A_matrices
    real colvector UstackW
    real scalar varL

    A_matrices = _createMatricesForVarianceFromW(sigma, numPrePeriods, l_vec)
    UstackW    = J(length(w), 1, 0) \ colshape(w, 1)
    varL = UstackW' * A_matrices.A_quadratic_sd * UstackW +
        A_matrices.A_linear_sd' * UstackW +
        A_matrices.A_constant_sd
    return(varL)
}

struct _honestMatrices scalar function _createMatricesForVarianceFromW(real matrix sigma,
                                                                       real scalar numPrePeriods,
                                                                       real colvector l_vec) {

    struct _honestMatrices  scalar A_matrices
    real rowvector prePeriodIndices, postPeriodIndices
    real matrix SigmaPre, SigmaPrePost, WtoLPreMat
    real matrix UstackWtoLPreMat, A_quadratic_sd
    real colvector A_linear_sd
    real scalar SigmaPost, A_constant_sd

    prePeriodIndices  = 1..numPrePeriods
    postPeriodIndices = _honestInverseIndex(prePeriodIndices, cols(sigma))

    // Constructs matrix to compute the variance of the affine estimator for a choice of weights W.
    SigmaPre     = sigma[prePeriodIndices, prePeriodIndices]
    SigmaPrePost = sigma[prePeriodIndices, postPeriodIndices]
    SigmaPost    = l_vec' * sigma[postPeriodIndices, postPeriodIndices] * l_vec
    WtoLPreMat   = I(numPrePeriods)

    if (numPrePeriods == 1) {
        WtoLPreMat = 1
    }
    else {
        for (col = 1; col < numPrePeriods; col++) {
            WtoLPreMat[col + 1, col] = -1
        }
    }

    UstackWtoLPreMat = (J(numPrePeriods, numPrePeriods, 0), WtoLPreMat)
    A_quadratic_sd   = UstackWtoLPreMat' * SigmaPre * UstackWtoLPreMat
    A_linear_sd      = 2 * UstackWtoLPreMat' * SigmaPrePost * l_vec
    A_constant_sd    = SigmaPost

    A_matrices = _honestMatrices()
    A_matrices.A_quadratic_sd = A_quadratic_sd
    A_matrices.A_linear_sd    = A_linear_sd
    A_matrices.A_constant_sd  = A_constant_sd

    return(A_matrices)
}

real matrix function _honestInverseIndex(real vector ix, real scalar n)
{
    real vector sel
    if (rows(ix) > cols(ix)) {
        sel = J(n, 1, 1)
        sel[ix] = J(length(ix), 1, 0)
    }
    else {
        sel = J(1, n, 1)
        sel[ix] = J(1, length(ix), 0)
    }
    return(selectindex(sel))
}
end

***********************************************************************
*                                                                     *
*                            _findLowestH                             *
*                                                                     *
***********************************************************************

* Finds the minimum variance affine estimator.
mata
real scalar function _findLowestH(real matrix sigma,
                                  real scalar numPrePeriods,
                                  real scalar numPostPeriods,
                                  real colvector l_vec) {

    struct _honestMatrices scalar A_matrices
    struct OSQP_csc_matrix scalar A, P
    struct OSQP_workspace_abridged scalar varResult
    string scalar fname

    real scalar threshold_sumweights
    real rowvector q, u, l

    threshold_sumweights = (1..numPostPeriods) * l_vec
    A_matrices = _createMatricesForVarianceFromW(sigma, numPrePeriods, l_vec)

    P = OSQP_csc_convert(2 * uppertriangle(A_matrices.A_quadratic_sd))
    q = A_matrices.A_linear_sd'
    A = OSQP_csc_convert(_createConstraints(numPrePeriods))
    u = threshold_sumweights, J(1, 2 * numPrePeriods, 0)
    l = threshold_sumweights, J(1, 2 * numPrePeriods, .)

    fname = st_tempfilename()
    OSQP_setup(fname, P, q, A, u, l)
    varResult = OSQP_solve(fname)

    if ( (varResult.rc != 0) | (varResult.info_status != "solved") ) {
        errprintf("Error in optimization for h0\n")
    }
    minimalVariance = varResult.info_obj_val + A_matrices.A_constant_sd
    minimalH = sqrt(minimalVariance)

    return(minimalH)
}
end

* _createConstraints
* ------------------
*
* ### Inequality constraints
*
* This function creates linear constraints that help to minimize
* worst-case bias over w using the OSQP library, where we cast
* maximization of the absolute values as a linear problem.  To do this,
* we assume that the optimization is over a vector (U, W) where
*
* U_1 = |w_1|, U_2 = |w_1 + w_2|, etc.
*
*
* This function creates a matrix of linear constraints that imposes
* these equalities and can easily be passed to the solver,
*
* -U_1 + w_1 <= 0
* -U_1 - w_1 <= 0, and so on.
*
* ### Equality constraints
*
* In additionl we have equality constraints of the  form
*
*     thresh = sum_t t * i_vec[t]
*     sum_t W = thresh
*
* ### Stack
*
* The solver only accepts one constraint, so we stack these
* two constraints together. They can be expressed as
*
*    (-infty, thresh) <= [A, S] * (U, W) <= (0, thresh)
*
* with S a vector of numPrePeriods 0s and numPrePeriods 1s

mata
real matrix function _createConstraints(real scalar numPrePeriods) {

    // Dense version
    // -------------

    real matrix lowerTriMat, A_absolutevalue, A
    real vector A_sumweights

    lowerTriMat = J(numPrePeriods, numPrePeriods, 1)
    _lowertriangle(lowerTriMat)
    A_absolutevalue = ((-I(numPrePeriods),  lowerTriMat ) \
                       (-I(numPrePeriods), -lowerTriMat))
    A_sumweights = (J(1, numPrePeriods, 0), J(1, numPrePeriods, 1))
    A = A_sumweights \ A_absolutevalue

    // Sparse version
    // --------------
    //
    // struct OSQP_csc_matrix scalar A
    // real vector helper
    // real scalar i
    //
    // A.data    = J(1, 2 * numPrePeriods, -1)
    // A.indptr  = 0, (1..numPrePeriods) * 2
    // A.indices = rowshape(((1::numPrePeriods), (1::numPrePeriods) :+ numPrePeriods), 1)
    // for (i = 1; i <= numPrePeriods; i++) {
    //     helper    = 0, i..(numPrePeriods), (i+numPrePeriods)..(numPrePeriods+numPrePeriods)
    //     A.indices = A.indices, helper
    //     A.indptr  = A.indptr, A.indptr[i + numPrePeriods] + length(helper)
    //     A.data    = A.data, 1, J(1, numPrePeriods-i+1, 1), J(1, numPrePeriods-i+1, -1)
    // }

    return(A)
}

real vector _honest_linspace(real scalar from, real scalar to, real scalar n) {
    real scalar step
    step = (to - from) / (n - 1)
    return(from :+ step :* (0..(n - 1)))
}
end

***********************************************************************
*                                                                     *
*                      _findWorstCaseBiasGivenH                       *
*                                                                     *
***********************************************************************

* A second-order cone program (SOCP) is a convex optimization problem of
* the form
*
*    min  c' x
*    s.t. Ax = b
*         Gx <(K) h
*
* where c is a vector conformable with x, A, G are matrices conformable
* with x, and h is a vector of the same dimension as Gx. In this case,
* <(K) indicates that h - Gx belongs to the cone K, and any number of
* first and second order cones may be specified.
*
* Concretely, say G' = [G1' G2'] and h' = [h1' h2'] with h1-G1x and
* h2-G2x belonging to the first and second-order cones, resp. The
* first-order cone is the positive ortahnt R^n_+, so the constraint is
*
*    G1x <= h1
*
* Now a vector (u_1, u_2) in R x R^{n - 1} belongs to the second-order
* cone if
*
*    ||u_2||_2 <= u_1
*
* with ||.||_2 the L_2 or Eucledean norm. So the constraint is
*
*    L_2(h22 - G22x) <= h21 - G21x
*
* For G2' = [G21' G22'] and h2' = [h21 h22'], noting G21 is a row
* vector, G22 is a matrix, h21 is a scalar, and h22 is a column vector.
* Now we're in business: For our worst-case bias, we are specifically
* interested in the problem with form
*
*    min  c' x
*    s.t. Ax = b
*         Dx <= 0
*         x' W x + v' x + u <= 0
*
* With some modifications we can fit this into the SOCP! The objective
* and equality constraints are unmodified. G1 = D and h1 = 0. So far so
* good. For the quadratic constraint, we can show
*
*    x' W x + v' x + u <= 0
*
* iff
*
*    L_2(W^{1/2} x + 0.5 W^{-1/2} v) <= (0.25 v' W^{-1} v - u)^0.5
*
* Set
*
*     G21 = 0
*     G22 = -W^{1/2}
*     h21 = (0.25 v' W^{-1} v - u)^0.5
*     h22 = 0.5 W^{-1/2} v
*
* and we're done.

* TODO: xx _honest_helper has not been thoroughly tested

mata
real scalar function _honest_helper(real scalar s, real colvector l_vec, real scalar numPostPeriods)
{
    return(abs((1..s) * l_vec[(numPostPeriods - s + 1)::numPostPeriods]))
}

real rowvector function _findWorstCaseBiasGivenH(real scalar hh,
                                                 real matrix sigma,
                                                 real scalar numPrePeriods,
                                                 real scalar numPostPeriods,
                                                 real colvector l_vec,
                                                 | real scalar M) {

    if ( args() < 6 ) M = 1

    struct _honestMatrices  scalar A_matrices
    real scalar threshold_sumweights, constant, n, b, u
    real vector c, A, h1, h21, h22, h, v, L
    real vector postPeriodIndices, optimal_x, optimal_l, optimal_w
    real matrix B, G1, G21, G22, G, W, C, _W0, _W1, _W2, _W3, W1, W2, W3
    string scalar fname
    struct ECOS_workspace_abridged scalar biasResult

    // This function minimizes worst-case bias over Delta^{SD}(M)
    // subject to the constraint that the SD of the estimator is <= hh.
    // Note: this function assumes M = 1 unless specified otherwise.
    //
    // NB: It's a bit unfortunate that here we use h and the same letter
    // is used in the SOCP notation. To aboid confusion, I name our h "hh"

    threshold_sumweights = (1..numPostPeriods) * l_vec
    constant = - threshold_sumweights
    for (s = 1; s <= numPostPeriods; s++) {
        constant = constant + _honest_helper(s, l_vec, numPostPeriods)
    }

    // First the equality and linear inequality constraints
    n  = numPrePeriods + numPostPeriods
    c  = (J(1, numPrePeriods, 1), J(1, numPrePeriods, 0))
    B  = _createConstraints(numPrePeriods)
    A  = B[1, .]
    b  = threshold_sumweights
    G1 = B[2::rows(B), .]
    h1 = J(n, 1, 0)

    // Now the second-order constraints
    A_matrices = _createMatricesForVarianceFromW(sigma, numPrePeriods, l_vec)
    W  = A_matrices.A_quadratic_sd
    v  = A_matrices.A_linear_sd
    u  = A_matrices.A_constant_sd - hh^2

    postPeriodIndices = _honestInverseIndex(1..numPrePeriods, n)
    _W0 = makesymmetric(W[postPeriodIndices, postPeriodIndices])
    eigensystem(_W0, C=., L=.)
    _W1 = makesymmetric(Re((C :* sqrt(L)) * C'))
    _W2 = makesymmetric(Re((C :/ sqrt(L)) * C'))
    _W3 = makesymmetric(Re((C :/     (L)) * C'))

    assert(max(abs((C * diag(L) * C') - _W0)) < 1e-12)
    assert(max(abs(_W1 * _W1 - _W0)) < 1e-12)
    assert(max(abs(_W1 * _W2 - I(numPrePeriods))) < 1e-12)
    assert(max(abs(_W3 * _W0 - I(numPrePeriods))) < 1e-12)

    W1 = J(n, n, 0)
    W2 = J(n, n, 0)
    W3 = J(n, n, 0)
    W1[postPeriodIndices, postPeriodIndices] = _W1
    W2[postPeriodIndices, postPeriodIndices] = _W2
    W3[postPeriodIndices, postPeriodIndices] = _W3

    G21 = J(1, n, 0)
    G22 = -W1
    h21 = sqrt(0.25 * (v' * W3 * v) - u)
    h22 = 0.5 * W2 * v
    G   = G1 \ G21 \ G22
    h   = h1 \ h21 \ h22

    // Run ECOS
    //     min
    //         c * x'
    //     s.t.
    //         A * x' - threshold_sumweights
    //         G1 * x'
    //         x * W * x' + x * v + u

    fname = st_tempfilename()
    ECOS_setup(fname,
               n,
               rows(G),
               rows(A),
               n,
               1,
               n + 1,
               0,
               OSQP_csc_convert(G),
               OSQP_csc_convert(A),
               c,
               h,
               b)
    biasResult = ECOS_solve(fname)

    // Multiply objective by M (note that solution otherwise doesn't
    // depend on M, so no need to run many times with many different Ms)
    biasResult.info_obj_val = biasResult.info_obj_val * M

    // NB: ECOS returns missing if solver fails; I think that should be
    // equivalent to filtering if < Ifn.
    //
    // work.info_exitcode == 0 is Optimal solution found, best
    // work.info_exitcode == 10 is Optimal solution found subject to reduced tolerances, OK

    // Compute the implied w and l
    optimal_x = biasResult.solution_x'
    optimal_w = optimal_x[(length(optimal_x)/2 + 1)::length(optimal_x)]
    optimal_l = _wToLFn(optimal_w)

    return(biasResult.info_exitcode, biasResult.info_obj_val, optimal_x', optimal_w', optimal_l')
}

real vector function _wToLFn(real vector w) {
    numPrePeriods = length(w)
    WtoLPreMat = I(numPrePeriods)
    if (numPrePeriods == 1) {
        WtoLPreMat = 1
    }
    else {
        for (col = 1; col < numPrePeriods; col++) {
            WtoLPreMat[col + 1, col] = -1
        }
    }
    return(WtoLPreMat * w)
}
end
