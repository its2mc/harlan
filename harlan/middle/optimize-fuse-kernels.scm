(library
  (harlan middle optimize-fuse-kernels)
  (export optimize-fuse-kernels
    verify-optimize-fuse-kernels)
  (import
   (rnrs)
   (harlan helpers)
   (only (harlan verification-passes)
         verify-make-kernel-dimensions-explicit)
   (harlan compile-opts)
   (elegant-weapons helpers))

  (define verify-optimize-fuse-kernels
    verify-make-kernel-dimensions-explicit)

  (define-match optimize-fuse-kernels
    ((module ,[Decl -> decl*] ...)
     `(module ,decl* ...)))
    
  (define-match Decl
    ((fn ,name ,args ,t ,[Stmt -> stmt])
     `(fn ,name ,args ,t ,stmt))
    ((extern ,name ,args -> ,rtype)
     `(extern ,name ,args -> ,rtype)))

  (define-match Stmt
    ((let ((,x* ,t* ,[Expr -> e*]) ...) ,[body])
     `(let ((,x* ,t* ,e*) ...) ,body))
    ((set! ,[Expr -> lhs] ,[Expr -> rhs])
     `(set! ,lhs ,rhs))
    ((if ,[Expr -> test] ,[conseq] ,[altern])
     `(if ,test ,conseq ,altern))
    ((if ,[Expr -> test] ,[conseq])
     `(if ,test ,conseq))
    ((while ,[Expr -> test] ,[body])
     `(while ,test ,body))
    ((for (,x ,[Expr -> start]
              ,[Expr -> stop]
              ,[Expr -> step])
          ,[body])
     `(for (,x ,start ,stop ,step) ,body))
    ((begin ,[stmt*] ...)
     `(begin ,stmt* ...))
    ((print ,[Expr -> e] ...)
     `(print . ,e))
    ((assert ,[Expr -> e])
     `(assert ,e))
    ((return) `(return))
    ((return ,[Expr -> e])
     `(return ,e))
    ((error ,x) `(error ,x))
    ((do ,[Expr -> e])
     `(do ,e)))

  (define-match Expr
    ((,t ,v) (guard (scalar-type? t)) `(,t ,v))
    ((var ,t ,x) `(var ,t ,x))
    ((int->float ,[e]) `(int->float ,e))
    ((make-vector ,t ,[e])
     `(make-vector ,t ,e))
    ((c-expr ,t ,v)
     `(c-expr ,t ,v))
    ((vector-ref ,t ,[v] ,[i])
     `(vector-ref ,t ,v ,i))
    ((length ,[e])
     `(length ,e))
    ((call ,[f] ,[args] ...)
     `(call ,f ,args ...))
    ((if ,[test] ,[conseq] ,[altern])
     `(if ,test ,conseq ,altern))
    ((if ,[test] ,[conseq])
     `(if ,test ,conseq))
    ((kernel ,t ,dims ,iters ,[body])
     (inline-kernel t dims iters body))
    ((let ((,x* ,t* ,[e*]) ...) ,[e])
     `(let ((,x* ,t* ,e*) ...) ,e))
    ((begin ,[Stmt -> s*] ... ,[e])
     `(begin ,s* ... ,e))
    ((,op ,[lhs] ,[rhs])
     (guard (or (relop? op) (binop? op)))
     `(,op ,lhs ,rhs)))

  (define (inline-kernel t dims iters body)
    (match iters
      ((((,x ,xt)
         ((kernel ,t^ ,dims^ ,iters^ ,body^)
          ,et)
         ,i)
        . ,rest)
       ;; Super kernel!
       (begin
         (assert (equal? dims dims^))
         (if (verbose)
             (begin
               (display "Harlan Compiler Message:")
               (display "optimize-fuse-kernels is inlining a kernel\n")))
         `(kernel ,t ,dims
                  (,@rest . ,iters^)
                  (let ((,x ,xt ,body^))
                    ,body))))
      (,else
       `(kernel ,t ,dims ,iters ,body))))

  ;; end library
  )
