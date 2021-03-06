#Author : GHRIBI SAIF EDDINE
#Question 1 part 1
draw_sd <- function(mu , sigma)
    #' draws  an ellipsoid  around the mean of a gaussian distribution
    #' which corresponds to the density level set of the univariate
    #' 0.95 quantile.
    #' mu: vector of size d the dimension
    #' sigma: a d*d covariance matrix.
    #' returns: a 2*100 matrix containing abscissas and ordinates of
    #' the ellipsoid to be drawn. 
{
    L <-  chol(sigma)
    angles <- seq(0, 2*pi, length.out=100)
    U <- 1.64* rbind(cos(angles), sin(angles))
    X <- mu + t(L) %*% U
    return(X)
}

initPar <- function(x , k){
    #' Initialisation for VB based on kmeans. 
    #'x: dataset: a n*d matrix for n points with d features each.
    #'k: number of components for the inferred mixture
    #' returns: a list with entries p, Mu, Sigma: respectively a vector of size k (weights), a k*d matrix (centers) and a d*d*k array (empirical covariance matrix)
    init <- kmeans(x = x, centers = k, iter.max = 100, nstart = 1,
                   algorithm = c("Hartigan-Wong"), trace=FALSE)
    Mu <- init$centers
    d <- ncol(x)
    Sigma <- array(dim=c(d,d,k))
    p <- rep(0,k)
    for( i in (1:k)){
        inds = which(init$cluster==i)
        n = length(inds)
        tildeX = t(t(x[inds,]) -Mu[i,])  
        sig = 1/n * t(tildeX) %*% tildeX
        Sigma[,,i] <- sig
        p[i] <-  n/nrow(x)
    }
    return(list(p = p, Mu = Mu, Sigma = Sigma ))
}

nanDetector <- function(X)
    #' returns TRUE if X contains NaNs
{
   # examine data frames
   if(is.data.frame(X)){ 
       return(any(unlist(sapply(X, is.nan))))
   }
   #  examine vectors, matrices, or arrays
   if(is.numeric(X)){
       return(any(is.nan(X)))
   }
   #  examine lists, including nested lists
   if(is.list(X)){
       return(any(rapply(X, is.nan)))
   }
   return(FALSE)
}

# this function computes the multiplication elementwise 
ElementwiseMultiply <- function ( a_, b_ )
{
c_ = a_ ;
for ( i in 1:ncol(a_) )
{
    c_[,i] = ( a_[,i] * b_ ) ;
}
return ( c_ );
}

# this function computes the sum of a (1,k) vector with a (n,k) matrix 
sum_element_wise<-function(a,b,k,N){
  res = b
  for (i in 1:k){
    for (j in 1:N){
      res[i,j]=b[i,j] + a[i]

    }

  }

return (res)
}

#this function computes Xk_bar defined in Bishop book (1/nk * sum (r_nk * x_n))
compute_Xk<-function(x,NK,respons){

 N = nrow(respons)
 K = ncol(respons)
 d = ncol (x)
res = array(0,dim = c(K,d)) 
for ( k in 1:K){
a = 0 
  for (n in 1:N){
    a = a + respons[n,k]*x[n,]
  }
res[k,] = a/NK[k]
}

return (res)

}

#this function computes the Sk defined in bishop book 
compute_Sk <- function(x,NK,respons,Xk_bar){
 N = nrow(respons)
 K = ncol(respons)
 d = ncol (x)
 res = array(0,dim=c(d,d,K))
 for (k in 1:K){
 a = array(0,dim = c(d,d))
   for (n in 1:N){
      
     a = a + respons[n,k] * (   (x[n,]-Xk_bar[k,])%*% t(x[n,]-Xk_bar[k,])   )

   }
   res[,,k]= a/ NK[k]
 }
  
return (res)
}

vbEstep <- function(x, Alpha, Winv, Nu, M, Beta)
    #' computation of the variational responsibilities. 
    #' x: the data. A n*d matrix
    #' Alpha: a k vector: current dirichlet parameter for q(p)
    #' Winv : a d*d*k array: current inverses of the W parameter for the Wishart q(Lambda)
    #' Nu: a k vector: current degrees of freedom parameter for the Wishart q(Lambda)
    #' M: a k*d matrix: current mean parameters for the Gaussian q(Mu | Lambda)
    #' Beta: a k vector: current scale parameters for the Gaussian q(Mu | Lambda)
    #' returns: a n*k matrix: the responsibilities for each data point.  
{
    d <-  ncol(M)
    k <- length(Alpha)
    N <- nrow(x)
    
    Eloglambda <-  # k vector
        sapply(1:k, function(j){
            sum(digamma( (Nu[j] + 1 - (1:d) )/2) )+ d * log(2) - log(det(Winv[,,j]))
        })
     
        
    Elogrho <- # k vector
        digamma(Alpha) - digamma(sum(Alpha))    
        
        
    temp_gaussian <- ElementwiseMultiply ( t( sapply(1:k, function(j){ ## a N * k matrix
            Wj <- solve(Winv[,,j])
            sapply(1:N, function(n){# a N vector
                t(M[j,] -x[n, ]) %*% Wj %*% (M[j,] -x[n, ])}) 
        })) , Nu) 
      
    Equadratic <- sum_element_wise(d/Beta,temp_gaussian,k,N) # k*N  matrix
      
         
    logResponsT <- Elogrho + 0.5* Eloglambda -0.5*Equadratic
    ## Complete the code: the transpose of
        ## the unnormalized log-responsibility matrix, ie. a k * N matrix
    logRespons <- t(logResponsT) ## N * k
    logRespons <- logRespons - apply(logRespons, 1, max) #' avoids numerical precision loss. 
    respons <- exp(logRespons) ##  N * k matrix
    Z <-  apply(respons, 1 , sum ) # N vector
    respons <-  respons / Z ##N * k matrix
    
    return(respons)
}

vbMstep <- function(x , respons , alpha0 ,  W0inv , nu0 , m0 , beta0)

    #' x: the data. A n*d matrix 
    #' respons: current q(z): a n*k matrix (responsibilities r_{nk})
    #' alpha0>0: a real.  isotropic dirichlet prior parameter on p
    #' W0inv, nu0: parameters for the Wishart prior on Lambda.
    #' W0inv: d*d matrix, inverse of the Wishart parameter.
    #' nu0 > d-1:  is a real.
    #' m0 : mean parameter (d vector) for the Gaussian-Wishart prior on  mu
    #' beta0: scale parameter for the gaussian-wishart  prior on mu (>0)
    ##' 
    #' returns: a list made of ( Alpha , Winv, Nu , M , Beta):  optimal parameters for
    #' q(p),
    #' q(mu_j, Lambda_j), j=1, ...,k: 
    #' Alpha: k-vector ; Winv: d*d*k array ; Nu: a k-vector ; M: k*d matrix ;
    #' Beta: k-vector                   
{   N = nrow(x)
    d <- ncol(x)
    K <-  ncol(respons)
    NK <- apply(respons, 2, sum) # a vector of size k
    NK <- sapply(NK, function(x){max(x, 1e-300)}) ## avoids divisions by zero
    
    Xk_bar = compute_Xk(x,NK,respons)
   

    #Sk = calc_sk(respons,x,Xk_bar,N,K)/NK
    Sk = compute_Sk(x,NK,respons,Xk_bar)
   

    Alpha <- alpha0 + NK ## complete the code (optimal Alpha): vector of size k

    Nu <- nu0 + NK ## complete the code (optimal nu): vector of size k

    Beta <- beta0 + NK## complete the code (optimal Beta): vector of size k

  
    
    z = ElementwiseMultiply(Xk_bar,NK)
  
    for (k in 1:K){
     
       z[k,]  = z[k,] + beta0*m0

    }
    M = ElementwiseMultiply(z,1/Beta)  ## complete the code: optimal mean parameters m_j for the mu_j's:
        ## a k*d matrix
    
    Winv <- array(dim=c(d,d,K))
    for( k in (1:K)){
     
        ## 
        ##
        
        Winv[,,k] <- W0inv + NK[k]*Sk[,,k] + (beta0*NK[k])/(beta0+NK[k]) *t(Xk_bar[k,] - m0)%*%(Xk_bar[k,]-m0) ## complete the code: optimal W^{-1}
            ##(inverse of the covariance parameter for Lambda_j)
            ## a d*d matrix
    }

    return(list(Alpha = Alpha, Winv = Winv, Nu = Nu, M= M, Beta =Beta)) 
}
vbalgo <- function(x, k, alpha0,  W0inv, nu0, m0, beta0, tol=1e-5)
 
    #' x: the data. n*d matrix
    #' k: the number of mixture components. 
    #' alpha0, W0inv, nu0, m0, beta0: prior hyper-parameters, see vbMstep.
    #' returns: a list composed of (Alphamat,  Winvarray, Numat, Marray, Betamat, responsarray, stopCriteria):
    #'   optimal parameters for q(p), q(mu_j, Lambda_j), j=1, ...,k, and trace of the
    ## stopping criteria along the iteration. 
    #'   Alphamat: K* Tmatrix,  Winvarray: d*d*T array,  Numat: a k*T matrix-vector, 
    #'   Marray: k*d*T array,  Betamat: k*T matrix, responsarray: n*k*T matrix, 
    #'   where T is the number of steps.
    #' stoppingCriteria: a T-vector:the stopping criterion  at each iteration (the first entry is set to the arbitrary 0 value)
{
    m0 = m0
    N <- nrow(x)
      d <- ncol(x)
    init <-  initPar(x=x,k=k)
    res <- list(Alphamat=matrix(nrow=k, ncol=0),
                Winvarray = array(dim=c(d,d,k,0)),
                Numat = matrix(nrow=k, ncol=0),
                Marray= array(dim=c(k,d,0) ),
                Betamat = matrix(nrow=k, ncol=0),
                responsarray = array(dim=c(N,k, 0)),
                stopCriteria = c(0)
                )
  
    Winvstart <- array(0,dim=c(d,d,k))
    for(j in 1:k){
        Winvstart[,,j] <- init$p[j] * N *  init$Sigma[,,j]
        }
    current <- list( Alpha = N * init$p, 
                    Winv = Winvstart, 
                    Nu = N* init$p, 
                    M = init$Mu,
                    Beta = N * init$p)
    ## current: current list of hyper parameters for the variational distribution
    
    continue <- TRUE
    niter <- 0
    while(continue){        
        niter <- niter+1
        respons <- vbEstep(x,current$Alpha,current$Winv,current$Nu,current$M,current$Beta) ## Complete the code
           
            
        if(nanDetector(respons)) {
          print("nan respons ")
          stop("NaNs detected!\n")}
        vbOpt <-vbMstep(x , respons , alpha0 ,  W0inv , nu0 , m0 , beta0) ## Complete the code
       
            
        if(nanDetector(vbOpt)) { print("nan vbopt") 
        stop("NaNs detected!\n")}
         
          memory_current = current
           current <- vbOpt

        if(niter >=2)
         
            
            {# Complete the code for computing the stopping
                ## criterion at current iteration. 
                 delta <- norm(as.matrix (current$Winv - memory_current$Winv )  ) + norm(as.matrix ( current$M - memory_current$M ) ) 
                 
            res$stopCriteria <- c(res$stopCriteria,delta)
        }
        

        
        res$Alphamat <- cbind(res$Alphamat, current$Alpha)
        res$Winvarray <- abind(res$Winvarray, current$Winv,along=4)
        res$Numat <- cbind(res$Numat, current$Nu)
        res$Marray <- abind(res$Marray, current$M,along=3)
        res$Betamat <- cbind(res$Betamat, current$Beta)
        res$responsarray <- abind(res$responsarray, respons,along=3)
        
            if(niter>=2){
                if( niter == 200  ||  delta < tol)              
            {continue <- FALSE}
        }
    }
        return(res)
        
}


#Question 1 part 3 

rproposal <- function( Mu, Sigma, p, ppar=list(var_Mu = 0.1,
                                               nu_Sigma = 10,
                                               alpha_p = 10))
    #' random generator according to a proposal kernel centered at the current value.
    #' Mu, Sigma, p: current mixture parameters, see gmllk.
    #' ppar: a list made of :
    #' - var_Mu: variance parameter for the gaussian kernel for Mu.
    #' - nu_Sigma: degrees of freedom for the Wihart kernel for Sigma
    #' - alpha_p: concentration aprameter for the Dirichlet kernel for p
    #' returns: a list fo proposal parameters: (Mu, Sigma, p), where 
    #'   p ~ dirichlet(Alpha) with mean = Alpha/sum(Alpha) = current p and
    #'   concentration parameter sum(Alpha) = alpha_p.
    #' Mu : a k*d matrix and Sigma: a d*d*k array: 
    #'   for j in 1:k,  Mu[j,]~ Normal(mean= current Mu[j,], covariance = var_Mu*Identity)
    #'   Sigma[,,j]~ Wishart(W = 1/nu_Sigma * current Sigma[,,j] ; nu = nu_Sigma)
    
{
    d <- ncol(Mu)
    k <- length(p)
    alphaProp <- sapply(ppar$alpha_p * p, function(x){max(x,1e-30)})
    ## this avoids numerical errors

    p <- rdirichlet(n=1, alpha = alphaProp)
    p <- sapply(p, function(x){max(x,1e-30)})
    p <- p/sum(p)
    for(j in (1:k))
    {
        Mu[j,] <- rmvn(1 ,Mu[j,],ppar$var_Mu * diag (d)) ## complete the code. use function rmvn 
        Sigma[,,j] <-  rWishart(1, ppar$nu_Sigma , (1/ppar$nu_Sigma) * Sigma[,,j]) ## complete the code. use function rwishart
    }
    return(list(Mu = Mu, Sigma = Sigma, p = p))
}

#question 2 part 3 
wrapper <- function(x , y , FUN, ...)
    #' applies a function on a grid with abscissas x, y.
    #' x, y: vectors of same length.
      {
       sapply(seq_along(x), FUN = function(i){FUN(x[i], y[i],...)})
      }
gmcdf <- function(x , Mu , Sigma , p)
    #' multivariate cumulative distribution function in a GMM. 
    #' x: a single point (vector of size d)
    #' Mu, Sigma, p: see gmllk.
    #' returns: the cdf at point x. 
{
    k <- length(p)
    vect_cdf <- vapply(1:k, function(j){
        pmnorm(x, mean = Mu[j,], varcov = Sigma[,,j])
    }, FUN.VALUE = numeric(1))
    return(sum(p*vect_cdf))
}

dprior <- function( Mu, Sigma, p,
                   hpar = list( alpha0= 1,
                               m0 = rep(0, ncol(Mu)), beta0 = 1, 
                               W0 = diag(ncol(Mu)), nu0 = ncol(Mu)))
    #'log-prior density on (Mu, Sigma, p)
    #' Mu, Sigma, p: see gmllk
    #' hpar: a list of hyper-parameters composed of
    #' - alpha0> 0 : isotropic dirichlet prior on p
    #' - m0: a d vector: mean parameter for the Gaussian-Wishart prior on Mu
    #' - beta0: a single number >0: scale parameter for the Gaussian-Wishart prior on Mu
    #' - W0: covariance parameter for the inverse-wishart distribution on Sigma
    #' - nu0: degrees of freedom >d-1 for the wishart distribution on Sigma.  
    
{
    d <- ncol(Mu)
    k <- length(p)
    prior_p <- ddirichlet(p, alpha= rep(hpar$alpha0, k), log = TRUE)
    prior_MuSigma <- sum(sapply(1:k, function(j){
        dnorminvwishart(mu = Mu[j,], mu0 = hpar$m0, lambda = hpar$beta0,
                        Sigma = Sigma[,,j], S = hpar$W0, nu = hpar$nu0,
                        log = TRUE)}))
    return(prior_p + prior_MuSigma)
}

rproposal <- function( Mu, Sigma, p, ppar=list(var_Mu = 0.1,
                                               nu_Sigma = 10,
                                               alpha_p = 10))
    #' random generator according to a proposal kernel centered at the current value.
    #' Mu, Sigma, p: current mixture parameters, see gmllk.
    #' ppar: a list made of :
    #' - var_Mu: variance parameter for the gaussian kernel for Mu.
    #' - nu_Sigma: degrees of freedom for the Wihart kernel for Sigma
    #' - alpha_p: concentration aprameter for the Dirichlet kernel for p
    #' returns: a list fo proposal parameters: (Mu, Sigma, p), where 
    #'   p ~ dirichlet(Alpha) with mean = Alpha/sum(Alpha) = current p and
    #'   concentration parameter sum(Alpha) = alpha_p.
    #' Mu : a k*d matrix and Sigma: a d*d*k array: 
    #'   for j in 1:k,  Mu[j,]~ Normal(mean= current Mu[j,], covariance = var_Mu*Identity)
    #'   Sigma[,,j]~ Wishart(W = 1/nu_Sigma * current Sigma[,,j] ; nu = nu_Sigma)
    
{
    d <- ncol(Mu)
    k <- length(p)
    alphaProp <- sapply(ppar$alpha_p * p, function(x){max(x,1e-30)})
    ## this avoids numerical errors

    p <- rdirichlet(n=1, alpha = alphaProp)
    p <- sapply(p, function(x){max(x,1e-30)})
    p <- p/sum(p)
    for(j in (1:k))
    {
        Mu[j,] <- rmvn(1 ,Mu[j,],ppar$var_Mu * diag (d)) ## complete the code. use function rmvn 
        Sigma[,,j] <-  rWishart(1, ppar$nu_Sigma , (1/ppar$nu_Sigma) * Sigma[,,j]) ## complete the code. use function rwishart
    }
    return(list(Mu = Mu, Sigma = Sigma, p = p))
}
gmllk <- function(x , Mu , Sigma , p){
    #' Log-likelihood in the Gaussian mixture model. 
    #' x: dataset: a n*d matrix for n points with d features each.
    #' Mu: a k*d matrix with k the number of components: the centers
    #' Sigma: a d*d*k array:: the convariance matrices.
    #' p: a vector of length k: the mixture weights
    #' returns:  the log-likelihood (single number)
    k <- length(p)
    if(is.vector(x)){
        x <- matrix(x, nrow=1)}
    n <- nrow(x)
    mat_dens <- vapply(1:k, function(j){
        dmnorm(x, mean = Mu[j,], varcov = Sigma[,,j], log=FALSE)
    }, FUN.VALUE = numeric(n)) ##  n rows, k columns.
    if(is.vector(mat_dens)){
        mat_dens <- matrix(mat_dens, nrow = 1)
    }
    vect_dens <-   mat_dens%*%matrix(p,ncol=1) ## vector of size n
    return(sum(log(vect_dens)))
}

MHsample <- function(x, k, nsample,
                     init=list(Mu = matrix(0,ncol=ncol(x), nrow=k ),
                               Sigma = array(rep(diag(ncol(x)), k),
                                             dim=c(ncol(x), ncol(x), k)),
                               p = rep(1/k, k)),
                     hpar= list( alpha0= 1, 
                                m0 = rep(0, ncol(Mu)), beta0 = 1, 
                                W0 = diag(ncol(Mu)), nu0 = ncol(Mu)),
                     ppar = list(var_Mu = 0.1,
                                 nu_Sigma = 10,
                                 alpha_p = 10) )
    #' x: the data. A n*d matrix.
    #' k: the number of mixture components.
    #' nsample: number of MCMC iterations
    #' init: starting value for the the MCMC. Format: list(Mu, Sigma, p), see gmllk for details
    #' hpar: a list of hyper-parameter for the prior: see dprior.
    #' ppar: a list of parameter for the proposal: see rproposal.
    #' returns: a sample produced by the Metropolis-Hastings algorithm, together with
    #' the log-posterior density (unnormalized) across iterations, and number of acepted proposals.  as a list composed of
    #' - p: a k*nsample matrix
    #' - Mu: a k*d*nsample array
    #' - Sigma: a d*d*k*nsample array
    #' - lpostdens: the log posterior density (vector of size nsample)
    #' - naccept! number of accepted proposals. 
{
    d <- ncol(x)
    output <- list(p = matrix(nrow=k, ncol=nsample),
                   Mu = array(dim = c(k, d, nsample)),
                   Sigma = array(dim = c(d, d ,k, nsample)),
                   lpostdens = rep(0, nsample),
                   naccept = 0
                   )
    current <- init
    current$lpost <- gmllk(x=x, Mu=current$Mu,
                            Sigma = current$Sigma, p=current$p) +
        dprior(Mu = current$Mu, Sigma = current$Sigma, p = current$p,
               hpar = hpar)
    ## lpost: logarithm of the unnormalized posterior density.
    
    for (niter in 1:nsample){
        proposal <- rproposal(Mu = current$Mu, Sigma = current$Sigma, p=current$p,
                              ppar = ppar)

        proposal$lpost <- gmllk(x=x, Mu=proposal$Mu,
                                Sigma = proposal$Sigma, p=proposal$p) +
            dprior(Mu = proposal$Mu, Sigma = proposal$Sigma, p = proposal$p,
                   hpar = hpar)
    
            
        llkmoveSigma <- sum(vapply(1:k, FUN = function(j){
            dwishart(Omega =proposal$Sigma[,,j], nu=ppar$nu_Sigma,
                     S = 1/ppar$nu_Sigma * current$Sigma[,,j] , log=TRUE)},
            FUN.VALUE = numeric(1)))

        llkbackSigma <- sum(vapply(1:k, FUN = function(j){
            dwishart(Omega =current$Sigma[,,j], nu=ppar$nu_Sigma,
                     S = 1/ppar$nu_Sigma * proposal$Sigma[,,j] , log=TRUE)},
            FUN.VALUE = numeric(1)))
        
        alphaPropmove <- sapply(ppar$alpha_p * current$p, function(x){max(x,1e-30)})

        alphaPropback <- sapply(ppar$alpha_p * proposal$p, function(x){max(x,1e-30)})

        lacceptratio <- proposal$lpost - current$lpost + llkmoveSigma - llkbackSigma 
        + ddirichlet(proposal$p , alphaPropmove,log=TRUE) - ddirichlet(current$p , alphaPropback,log=TRUE)
            ## logarithm of the acceptance ratio.
            ## Complete the code using
            ## proposal$lpost,  current$lpost,
            ## ddirichlet( ... , log=TRUE), llkbackSigma and llkmovesigma. 

        U <- runif(1)
        if(U < exp(lacceptratio)){
            current <- proposal
            output$naccept <- output$naccept + 1
        }
        output$p[,niter] <- current$p
        output$Mu[,,niter] <- current$Mu
        output$Sigma[,,,niter] <- current$Sigma
        output$lpostdens[niter] <- current$lpost            
    }
    return(output)
    
} 

#Question 4 part 3 
  cdfTrace <- function(x , sample , burnin = 0 , thin = 1)
  #' Traces the evolution of the gmcdf at point x through the MCMC iterations.
  #'  Can be used for convergence monitoring. 
  #' x: a single point (vector of size d)
  #' burnin, thin: see MHpredictive
  #' returns: a vector of length [ (nsample - burnin )/thin ]
{
  nsample <- ncol(sample$p)
  inds <- (burnin+1):nsample
  inds <- inds[inds%%thin==0]
  output <- vapply(inds , function(niter){
    gmcdf (x , sample$Mu[,,niter] , sample$Sigma[,,,niter] , sample$p[,niter])},   ## complete the code using gmcdf
    FUN.VALUE = numeric(1))
  return(output)
  }

MHpredictive <- function(x , sample , burnin=0, thin=1)
  #' posterior predictive density computed from MH output. 
  #' x: vector size d (single point)
  #' sample: output from the MCMC algorithm should contain
  #'    entries Mu, Sigma, p as in MHsample's output
  #' burnin: length of the burn-in period
  #'   (number of sample being discarded at the beginning of the chain).
  #' thin: thinning parameter: only 1 sample out of 'thin' will be kept
  #' returns: a single numeric value
{
  nsample <- ncol(sample$p)
  inds <- (burnin+1):nsample
  inds <- inds[inds%%thin==0]
  vectllk <- vapply(inds, function(niter){
      exp(gmllk(x , sample$Mu[,,niter] , sample$Sigma[,,,niter] , sample$p[,niter])) ## complete the code
      }        
    , FUN.VALUE = numeric(1)
  )
  return(mean(vectllk))
}
heidel_diagnostic <- function (index,burnin) {
    
    for (i in (1:length(index))) {
    
    cdf_values <- cdfTrace(X[index[i],],outputmh,burnin=0, thin=1)
    print(paste(c("Heidel diagnostic for index ", index [i] )))
    print(heidel.diag(mcmc(cdf_values),eps=0.1, pvalue=0.05))
    }
    
}

#question 1 part 4
MHpredictiveCdf <- function(x , sample , burnin = 0, thin = 1)
    #' posterior predictive cdf computed from MH output.
    #' arguments: see MHpredictive.
    #' returns: a single numeric value. 
{
    nsample <- ncol(sample$p)
    inds <- (burnin+1):nsample
    inds <- inds[inds%%thin==0]

    vectcdf <- vapply(inds, function(niter){
      gmcdf(x , sample$Mu[,,niter] , sample$Sigma[,,,niter] , sample$p[,niter])
  }, FUN.VALUE = numeric(1)
  )
      return(mean(vectcdf))
}

vbPredictiveCdf <- function(x, Alpha, Beta, M, Winv, Nu)
    #' predictive cumulative distribution function based on the VB approximation.
    #' x: a single point (vector): where to evaluate the cdf. 
    #' Alpha, Winv, Nu, M, Beta: the VB posterior parameters,  see vbEstep
    #' returns the value of the variational posterior predictive cdf
    #'  (= mean of the mixture cdf under the variational posterior predictive)
    #'   at point x. 
  {
    k <- length(Alpha)
    d <-  length(x)
    vectcdf <- vapply(X= 1:k, FUN= function(j){
      W <- Winv[,,j]
      L <-  (1 + Beta[j])/ ((Nu[j] + 1 - d) * Beta[j])  *   W
      L <- 1/2 * (L + t(L)) ## ensures symmetry despite numerical errors
      return(pmt(x=x, mean = M[j,], S = L, df = Nu[j] + 1 - d, log=FALSE))} ,
      FUN.VALUE= numeric(1) )
    
    return(sum(Alpha * vectcdf) / sum(Alpha))
  }
