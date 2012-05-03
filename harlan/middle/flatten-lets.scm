(library
  (harlan middle flatten-lets)
  (export flatten-lets)
  (import (rnrs) (elegant-weapons helpers)
    (harlan helpers))

(define-match flatten-lets
  ((module ,[flatten-decl -> decl*] ...)
   `(module . ,decl*)))

(define-match flatten-decl
  ((fn ,name ,args ,type ,[flatten-stmt -> stmt])
   `(fn ,name ,args ,type ,stmt))
  (,else else))

(define-match flatten-stmt
  ((let ((,x* ,t* ,[flatten-expr -> e*]) ...) ,[stmt])
   `(begin
      ,@(map (lambda (x t e) `(let ,x ,t ,e)) x* t* e*)
      ,stmt))
  ((let ((,x* ,t*) ...) ,[stmt])
   `(begin
      ,@(map (lambda (x t) `(let ,x ,t)) x* t*)
      ,stmt))
  ((if ,[flatten-expr -> test] ,[conseq])
   `(if ,test ,conseq))
  ((if ,[flatten-expr -> test] ,[conseq] ,[alt])
   `(if ,test ,conseq ,alt))
  ((begin ,[stmt*] ...)
   (make-begin stmt*))
  ((print ,[flatten-expr -> expr] ...)
   `(print . ,expr))
  ((assert ,[flatten-expr -> expr])
   `(assert ,expr))
  ((return) `(return))
  ((return ,[flatten-expr -> expr])
   `(return ,expr))
  ((for ,b ,[stmt])
   `(for ,b ,stmt))
  ((while ,test ,[stmt])
   `(while ,test ,stmt))
  ((kernel ,dims (free-vars . ,fv*) ,[stmt])
   `(kernel ,dims (free-vars . ,fv*) ,stmt))
  ((do ,[flatten-expr -> expr]) `(do ,expr))
  ((error ,x) `(error ,x))
  ((set! ,[flatten-expr -> e1] ,[flatten-expr -> e2]) `(set! ,e1 ,e2)))

(define-match flatten-expr
  ((,t ,n) (guard (scalar-type? t)) `(,t ,n))
  ((var ,type ,x) `(var ,type ,x))
  ((c-expr ,type ,x) `(c-expr ,type ,x))
  ((if ,[test] ,[conseq] ,[alt])
   `(if ,test ,conseq ,alt))
  ((alloc ,[region] ,[size])
   `(alloc ,region ,size))
  ((region-ref ,t ,[region] ,[ptr])
   `(region-ref ,t ,region ,ptr))
  ((cast ,t ,[expr])
   `(cast ,t ,expr))
  ((sizeof ,t)
   `(sizeof ,t))
  ((addressof ,[expr])
   `(addressof ,expr))
  ((deref ,[expr])
   `(deref ,expr))
  ((let ((,x* ,t* ,[e*]) ...) ,[expr])
   `(begin
      ,@(map (lambda (x t e) `(let ,x ,t ,e)) x* t* e*)
      ,expr))
  ((vector-ref ,type ,[e1] ,[e2])
   `(vector-ref ,type ,e1 ,e2))
  ((length ,n)
   `(length ,n))
  ((,op ,[e1] ,[e2]) (guard (binop? op))
   `(,op ,e1 ,e2))
  ((,op ,[e1] ,[e2]) (guard (relop? op))
   `(,op ,e1 ,e2))
  ((call ,[expr] ,[expr*] ...)
   `(call ,expr . ,expr*)))

;; end library

)