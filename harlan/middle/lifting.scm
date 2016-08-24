(library (harlan middle lifting)
  (export
    optimize-lift-lets
    optimize-lift-allocation)
  (import
   (rnrs)
   (harlan helpers)
   (except (elegant-weapons helpers) ident?)
   (elegant-weapons sets)
   (harlan verification-passes))

  ;; This optimization does something like loop invariant code
  ;; motion. The main idea is to let bindings up as high as possible
  ;; in the program. This may not be a good idea in general, but we'll
  ;; find out.
  ;;
  ;; This pass ignores code inside of kernels. That might need to be
  ;; treating separately. Kernels shouldn't be doing memory allocation
  ;; anyway.
  ;;
  ;; The approach pass uses is to walk all the code. We return two
  ;; values: a rewritten AST and a list of bindings that need to be
  ;; placed. When we pass a binding form that binds a variable one of
  ;; the liftable bindings depends on, we go ahead and place this let
  ;; immediately inside this form. We then continue to pass the rest
  ;; of the bindings up the tree.

  (define-match optimize-lift-lets
    ((module ,[Decl -> decl*] ...)
     `(module ,decl* ...)))

  (define optimize-lift-allocation optimize-lift-lets)

  (define (make-let bindings body)
    (if (null? bindings)
        body
        (fold-right
         (lambda (b exp)
           `(let (,b) ,exp))
         body
         bindings)))
  
  (define-match Decl
    ((extern . ,_)
     `(extern . ,_))
    ((typedef ,name ,t) `(typedef ,name ,t))
    ((fn ,name ,args ,type ,[Stmt -> body bindings])
     `(fn ,name ,args ,type
          ,(make-let bindings body))))

  ;; Takes a list of variables and bindings. Returns a list of
  ;; bindings that can and cannot be lifted over the definition of the
  ;; variables in vars.
  (define-match (split-bindings vars)
    (() (values `() `()))
    (((,x ,t ,e) . ,[liftable pinned])
     (if (let ((fv (free-vars-Expr e)))
           (and (null? (intersection vars fv))
                (pure? e)))
         (values (cons `(,x ,t ,e) liftable) pinned)
         (values liftable (cons `(,x ,t ,e) pinned)))))
      
  (define-match Stmt
    ((let ((,x* ,t* ,[Expr -> e* binding*]) ...)
       ,[body bindings])
     (let-values (((liftable pinned) ((split-bindings x*) bindings)))
       (values (make-let pinned body)
               (append
                (map list x* t* (map make-let binding* e*))
                liftable))))
    ((let-region (,r ...) ,[body bindings])
     ;; FIXME: This is overly conservative, many bindings can be
     ;; lifted beyond this.
     (values `(let-region (,r ...) ,(make-let bindings body))
             '()))
    ((let ((,x* ,t*) ...) ,[body bindings])
     (values `(let ((,x* ,t*) ...) ,(make-let bindings body))
             `()))
    ((kernel ,kt ,d (((,x* ,t) (,e ,es) ,dim) ...) ,[body bindings])
     (let-values (((liftable pinned) ((split-bindings x*) bindings)))
       (values `(kernel ,kt ,d (((,x* ,t) (,e ,es) ,dim) ...)
                        ,(make-let pinned body))
               liftable)))
    ((kernel ,kt ,r ,d (((,x* ,t) (,e ,es) ,dim) ...) ,[body bindings])
     (let-values (((liftable pinned) ((split-bindings x*) bindings)))
       (values `(kernel ,kt ,r ,d (((,x* ,t) (,e ,es) ,dim) ...)
                        ,(make-let pinned body))
               liftable)))
    ((begin ,[stmt* bindings*] ... ,[Expr -> e bindings])
     (values
      `(begin ,@(map make-let bindings* stmt*) ,(make-let bindings e))
      `()))
    ((for (,x ,[Expr -> start start-bindings]
              ,[Expr -> end end-bindings]
              ,[Expr -> step step-bindings])
          ,[body bindings])
     ;; We don't lift any body bindings out of the for loop, in case
     ;; side effects mess with them. Again, we need a proper assigned
     ;; variable analysis.
     (values
      `(for (,x ,start ,end ,step)
         ,(make-let bindings body))
        (append start-bindings end-bindings step-bindings)))
    ((while ,[Expr -> test test-bindings]
       ,[body bindings])
     ;; We don't lift any bindings in the body outside of the while
     ;; loop. This avoids problems when there are side effects. That
     ;; said, this is exactly the situation where we do want to lift
     ;; bindings, so we should probably do a proper assigned variable
     ;; analysis instead.
     (values `(while ,test ,(make-let bindings body))
             test-bindings))
    ((if ,[Expr -> e bindings] ,c)
     (values `(if ,e ,c) bindings))
    ((if ,[Expr -> e bindings] ,c ,a)
     (values `(if ,e ,c ,a) bindings))
    ((set! ,[Expr -> x x-bindings] ,[Expr -> e e-bindings])
     (values `(set! ,x ,e)
             (append x-bindings e-bindings)))
    ((assert ,[Expr -> e bindings])
     (values `(assert ,e) bindings))
    ((print . ,e*) (values `(print . ,e*) `()))
    ((return) (values `(return) `()))
    ((return ,e) (values `(return ,e) `()))
    ((do ,[Expr -> e bindings])
     (values `(do ,e) bindings)))

  (define-match Expr
    ((let ((,x* ,t* ,e*) ...) ,[body bindings])
     (let-values (((liftable pinned) ((split-bindings x*) bindings)))
       (values (make-let pinned body) (append liftable (map list x* t* e*)))))
    ((begin ,[Stmt -> stmt* bindings*] ... ,[e bindings])
     (values
      `(begin ,@(map make-let bindings* stmt*) ,(make-let bindings e))
      `()))
    ((kernel ,kt ,d (((,x* ,t) (,e ,es) ,dim) ...) ,[body bindings])
     ;; Don't lift out of kernels, in case there are side
     ;; effects. Again, we need an assigned variable analysis.
     (values `(kernel ,kt ,d (((,x* ,t) (,e ,es) ,dim) ...)
                      ,(make-let bindings body))
             '()))
    ((kernel ,kt ,r ,d (((,x* ,t) (,e ,es) ,dim) ...) ,[body bindings])
     (values `(kernel ,kt ,r ,d (((,x* ,t) (,e ,es) ,dim) ...)
                      ,(make-let bindings body))
             '()))
    (,e (values e `())))

  (define-match free-vars-Expr
    ((,t ,x) (guard (scalar-type? t)) `())
    ((var ,t ,x) (list x))
    ((,op ,[e1] ,[e2])
     (guard (or (binop? op) (relop? op)))
     (union e1 e2))
    ((addressof ,[e]) e)
    ((deref ,[e]) e)
    ((call ,[fn] ,[args] ...)
     (apply union fn args))
    ((length ,[e]) e)
    ((make-vector ,t ,r ,[e]) e)
    ((vector ,t ,r ,[e] ...) (apply union e))
    ((vector-ref ,t ,[x] ,[i])
     (union x i))
    ((unsafe-vector-ref ,t ,[x] ,[i])
     (union x i))
    ((unsafe-vec-ptr ,t ,[v]) v)
    ((kernel ,t (,[dfv**] ...) (((,x* ,t*) (,[fv**] ,ts*) ,d) ...) ,[e])
     (apply union
            (difference e x*)
            (union dfv** fv**)))
    ((kernel ,t ,r (,[dfv**] ...) (((,x* ,t*) (,[fv**] ,ts*) ,d) ...) ,[e])
     (apply union
            (difference e x*)
            (union dfv** fv**)))
    ((let ((,x* ,t* ,[e*]) ...) ,[e])
     (apply union (difference e x*) e*))
    ((if ,[t] ,[c] ,[a])
     (union t c a))
    ((c-expr ,t ,v) `(c-expr ,t ,v))
    ((field ,[e] ,x) e)
    ((box ,t ,r ,[e]) e)
    ((unbox ,t ,r ,[e]) e)
    ((begin ,[free-vars-Stmt -> s*] ... ,[e])
     (apply union e s*)))

  (define-match free-vars-Stmt
    ((error ,x) `())
    ((print ,[free-vars-Expr -> fv*]) fv*)
    ((assert ,[free-vars-Expr -> fv*]) fv*)
    ((return) `())
    ((return ,[free-vars-Expr -> fv*]) fv*)
    ((for (,x ,[free-vars-Expr -> sfv*] ,[free-vars-Expr -> efv*]
              ,[free-vars-Expr -> stepfv*]) ,[fv*])
     (union sfv* efv* stepfv* (difference fv* `(,x))))
    ((set! ,[free-vars-Expr -> x] ,[free-vars-Expr -> v])
     (union x v))
    ((if ,[free-vars-Expr -> test] ,[conseq])
     (union test conseq))
    ((if ,[free-vars-Expr -> test] ,[conseq] ,[altern])
     (union test conseq altern))
    ((while ,[free-vars-Expr -> test] ,[body])
     (union test body))
    ((let ((,x* ,t* ,[free-vars-Expr -> e*]) ...) ,[e])
     (apply union (difference e x*) e*))
    ((begin ,[s*] ...)
     (apply union s*)))

  ;; pure means that it has no side effects
  ;; TODO: fix pure
  (define-match pure?
    ((,t ,x) (guard (scalar-type? t)) `(,t ,x))
    ((var ,t ,x) #t)
    ((,op ,[lhs] ,[rhs])
     (guard (or (binop? op) (relop? op)))
     (and lhs rhs))
    ((let ((,x ,t ,e) ...) ,b)
     (and (andmap pure? e) (pure? b)))
    ((begin ,stmt* ... ,e) #f)
    ((vector ,t . ,e*) #f)
    ((vector-r ,t ,r . ,e*) #f)
    ((make-vector ,t ,r ,[e]) #f)
    ((length ,[e]) e)
    ((if ,[t] ,[c] ,[a])
     (and t c a))
    ;; Don't lift function calls.
    ((call ,fn ,arg* ...) #f)
    ((addressof ,[e]) e)
    ((deref ,[e]) e)
    ((vector-ref ,t ,[x] ,[i])
     (and x i))
    ((iota ,[e]) e)
    ((field ,[e] ,x) e)
    ((box ,t ,r ,[e]) e)
    ((unbox ,t ,r ,[e]) e)
    ((kernel
       ,t
       (,dims ...)
       (((,x ,xt) (,e ,et) ,d)
        ...)
       ,body)
     (and (andmap pure? e)
          (andmap pure? dims)
          (pure? body)))
    ((kernel
       ,t ,r
       (,dims ...)
       (((,x ,xt) (,e ,et) ,d)
        ...)
       ,body)
     (and (andmap pure? e)
          (andmap pure? dims)
          (pure? body))))
  
  ;; end library
  )
