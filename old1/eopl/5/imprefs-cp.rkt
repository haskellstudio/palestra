#lang eopl

(#%provide interp
           interp/translation
           expval->value
           other-summary)

(define (interp src) (value-of-program (scan&parse src)))

(define (interp/translation src)
  (value-of-program
    (translate-program:letcc->call/cc
      (scan&parse src))))

(define times-of-using-letcc 0)
(define times-of-using-cc 0)

(define (other-summary)
  (eopl:printf "letcc: ~a~%" times-of-using-letcc)
  (eopl:printf "cc: ~a~%" times-of-using-cc))

;(define (interp src) (value-of-program-dbg-store (scan&parse src)))

; Program ::= Expression
;
; Expression ::= Number
;            ::= Identifier
;            ::= proc ({Identifier}*(,)) Expression
;            ::= primitive-procedure({Expression}*(,))
;            ::= (Expression {Expression}*)
;            ::= if Expression then Expression else Expression
;            ::= let {Identifier = Expression}*(,) in Expression
;            ::= letrec {Identifier ({Identifier}*(,)) = Expression}*(,) in Expression
;            ::= set Identifier = Expression
;            ::= begin {Expression}*(,) end
;            ::= ref Identifier
;            ::= try Expression catch (Identifier, Identifier) Expression
;            ::= raise Expression
;            ::= cc Expression Expression
;            ::= letcc Identifier in Expression
;
; MutPair = Ref(ExpVal) X Ref(ExpVal)
; ExpVal = Number + Boolean + Proc + MutPair + Continuation + Ref(ExpVal)
; DenVal = Ref(ExpVal)
;
; primitive-procedures: minus, diff(-), addition(+), ,multiplication(*),
;                       quotient, remainder,
;                       zero?, equal?, greater?, less?,
;                       newpair, left, right, setleft, setright,
;                       deref, setref,
;                       call/cc,
;
; environment: symbol -> DenVal
; store: Ref -> ExpVal

(define scanner-spec
  '((white-sp (whitespace) skip)
    (commont ("#" (arbno (not #\newline))) skip)
    (number (digit (arbno digit)) number)
    (identifier
      ((or letter)
       (arbno
         (or "-" "_" "/" letter digit))) symbol)))

(define grammar-spec
  '((program (expression) a-program)
    (expression (number) number-exp)
    (expression (identifier) var-exp)
    (expression
      (primitive
        "(" (separated-list expression ",") ")")
      apply-primitive-exp)
    (expression
      ("proc" "(" (separated-list identifier ",") ")"
       expression)
      proc-exp)
    (expression
      ("(" expression (arbno expression) ")")
      call-exp)
    (expression
      ("if" expression "then" expression "else" expression)
      if-exp)
    (expression
      ("let" (separated-list identifier "=" expression ",") "in" expression)
      let-exp)
    (expression
      ("letrec"
       (separated-list
         identifier
         "(" (separated-list identifier ",") ")" "=" expression
         ",")
       "in" expression)
      letrec-exp)
    (expression
      ("set" identifier "=" expression)
      assign-exp)
    (expression
      ("begin" (separated-list expression ",") "end")
      begin-exp)
    (expression
      ("ref" identifier)
      ref-exp)
    (expression
      ("try" expression "catch" "(" identifier "," identifier ")" expression)
      try-exp)
    (expression
      ("raise" expression)
      raise-exp)
    (expression
      ("cc" expression expression)
      cc-exp)
    (expression
      ("letcc" identifier "in" expression)
      letcc-exp)
    (primitive ("+") add-prim)
    (primitive ("-") diff-prim)
    (primitive ("*") mult-prim)
    (primitive ("minus") minus-prim)
    (primitive ("quotient") quotient-prim)
    (primitive ("remainder") remainder-prim)
    (primitive ("zero?") zero?-prim)
    (primitive ("equal?") equal?-prim)
    (primitive ("greater?") greater?-prim)
    (primitive ("less?") less?-prim)
    (primitive ("pair") pair-prim)
    (primitive ("left") left-prim)
    (primitive ("right") right-prim)
    (primitive ("setleft") setleft-prim)
    (primitive ("setright") setright-prim)
    (primitive ("deref") deref-prim)
    (primitive ("setref") setref-prim)
    (primitive ("call/cc") call/cc-prim)))

(sllgen:make-define-datatypes
  scanner-spec grammar-spec)

(define scan&parse
  (sllgen:make-string-parser
    scanner-spec grammar-spec))

;(eopl:pretty-print
;  (sllgen:list-define-datatypes
;    scanner-spec grammar-spec))
;
;(define test-parse
;  (sllgen:make-rep-loop
;    "> " (lambda (x) x)
;    (sllgen:make-stream-parser
;      scanner-spec grammar-spec)))
;
;(test-parse)

; translate: letcc and cc => call/cc ;;;;;;;;;;;;;;;;;;;;;;
; cc cont val => (cont val)
; letcc cont exp => call/cc(proc (cont) exp)
(define (translate-program:letcc->call/cc pgm)
  (cases program pgm
    (a-program (exp)
      (a-program (translation-of exp)))))

(define (translation-of exp)
  (cases expression exp
    (apply-primitive-exp (prim exps)
      (apply-primitive-exp prim
                          (map translation-of exps)))
    (proc-exp (vars body)
      (proc-exp vars (translation-of body)))
    (call-exp (rator rands)
      (call-exp (translation-of rator) (map translation-of rands)))
    (if-exp (exp1 exp2 exp3)
      (if-exp (translation-of exp1)
              (translation-of exp2)
              (translation-of exp3)))
    (let-exp (vars exps body)
      (let-exp vars (map translation-of exps) (translation-of body)))
    (letrec-exp (vars argss exps body)
      (letrec-exp vars argss (map translation-of exps) (translation-of body)))
    (assign-exp (var exp)
      (assign-exp var (translation-of exp)))
    (begin-exp (exps)
      (begin-exp (map translation-of exps)))
    (try-exp (exp err cont handler-exp)
      (try-exp (translation-of exp) err cont (translation-of handler-exp)))
    (raise-exp (exp)
      (raise-exp (translation-of exp)))
    (cc-exp (cont-exp exp)
      (call-exp (translation-of cont-exp) (list (translation-of exp))))
    (letcc-exp (var body)
      (apply-primitive-exp
        (call/cc-prim)
        (list (proc-exp (list var) (translation-of body)))))
    (else  ; number-exp, var-exp, ref-exp
      exp)))

; expval ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-datatype expval expval?
  (num-val
    (num number?))
  (bool-val
    (bool boolean?))
  (proc-val
    (proc proc?))
  (mutpair-val
    (pair mutpair?))
  (ref-val
    (ref reference?))
  (cont-val
    (cont continuation?)))

(define (expval->value val)
  (cond ((expval? val)
         (cases expval val
           (num-val (num) num)
           (bool-val (bool) bool)
           (proc-val (proc) proc)
           (mutpair-val (pair) pair)
           (ref-val (ref) ref)
           (cont-val (cont) cont)))
        ((number? val) '==number==)
        ((boolean? val) '==bool==)
        (else val)))

(define (ref-val? val)
  (cases expval val
    (ref-val (ref) #t)
    (else #f)))

(define (report-expval-extractor-error type val)
  (eopl:error "Type error:" val type))

(define (expval->num val)
  (cases expval val
    (num-val (num) num)
    (else (report-expval-extractor-error 'num val))))

(define (expval->bool val)
  (cases expval val
    (bool-val (bool) bool)
    (else (report-expval-extractor-error 'bool val))))

(define (expval->proc val)
  (cases expval val
    (proc-val (proc) proc)
    (else (report-expval-extractor-error 'proc val))))

(define (expval->mutpair val)
  (cases expval val
    (mutpair-val (pair) pair)
    (else (report-expval-extractor-error 'mutpair val))))

(define (expval->ref val)
  (cases expval val
    (ref-val (ref) ref)
    (else (report-expval-extractor-error 'ref val))))

(define (expval->cont val)
  (cases expval val
    (cont-val (cont) cont)
    (else (report-expval-extractor-error 'cont val))))

; procedure ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-datatype proc0 proc?
  (procedure
    (list-of-var (list-of symbol?))
    (body expression?)
    (env environment?)))

(define (proc-val-procedure args body env)
  (proc-val (procedure args body env)))

(define (apply-proc-or-cont/k val list-of-val cont)
  (cases expval val
    (cont-val (cont)
      (if (= 1 (length list-of-val))
        (apply-cont cont (car list-of-val))
        (report-arguments-not-match '(val) list-of-val)))
    (proc-val (proc)
      (apply-proc/k proc list-of-val cont))
    (else
      (report-application-not-proc-or-cont val))))

(define (report-application-not-proc-or-cont val)
  (eopl:error "application-not-proc-or-cont" val))

(define (apply-proc/k proc list-of-val cont)
  (cases proc0 proc
    (procedure (list-of-var body env)
      (let ((nvars (length list-of-var))
            (nvals (length list-of-val)))
        (if (= nvars nvals)
          (value-of/k
            body
            (extend-env env list-of-var list-of-val)
            cont)
          (report-arguments-not-match
            list-of-var list-of-val))))))

(define (report-arguments-not-match vars vals)
  (eopl:error "args not match" vars vals))

; mutpair ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-datatype mutpair mutpair?
  (a-pair
    (left-ref reference?)
    (right-ref reference?)))

(define (newpair val1 val2)
  (a-pair (newref val1) (newref val2)))

(define (mutpair-left pair)
  (cases mutpair pair
    (a-pair (l r) (deref l))))

(define (mutpair-right pair)
  (cases mutpair pair
    (a-pair (l r) (deref r))))

(define (mutpair-setleft pair val)
  (cases mutpair pair
    (a-pair (l r)
      (setref! l val))))

(define (mutpair-setright pair val)
  (cases mutpair pair
    (a-pair (l r)
      (setref! r val))))

; store ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define the-store 'uninitialized)

(define (empty-store) '())

(define (get-store) the-store)

(define (initialize-store!)
  (set! the-store (empty-store)))

(define (reference? v) (integer? v))

(define (newref val)
  (let ((next-ref (length the-store)))
    (set! the-store (append the-store (list val)))
    next-ref))

(define (deref ref)
  (list-ref the-store ref))

(define (setref! ref val)
  (define (iter st ref)
    (if (null? st)
      (report-invalid-reference ref the-store)
      (if (zero? ref)
        (cons val (cdr st))
        (cons (car st) (iter (cdr st) (- ref 1))))))
  (set! the-store
    (iter the-store ref)))

(define (report-invalid-reference ref the-store)
  (eopl:error "invalid reference:" ref the-store))

; environment ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-datatype frame frame?
  (frame-vec (vec vector?)))

(define (a-frame vars vals)
  (frame-vec (vector vars vals)))

(define (empty-frame)
  (a-frame '() '()))

(define (frame-set! frm vars vals)
  (cases frame frm
    (frame-vec (vec)
      (vector-set! vec 0 vars)
      (vector-set! vec 1 vals))))

(define (frame-vars frm)
  (cases frame frm
    (frame-vec (vec) (vector-ref vec 0))))

(define (frame-vals frm)
  (cases frame frm
    (frame-vec (vec) (vector-ref vec 1))))

(define-datatype environment environment?
  (empty-env)
  (extend-env-frame
    (enclosing-environemt environment?)
    (frm frame?)))

(define (extend-env env vars vals)
  ; assert (= (length list-of-symbol) (length list-of-exp))
  (extend-env-frame env (a-frame vars (map newref vals))))

(define (extend-env-1 env var val)
  (extend-env env (list var) (list val)))

(define (extend-env-rec env list-of-name list-of-args list-of-body)
  ; assert (= (length list-of-name) (length list-of-args) (length list-of-body))
  (let* ((frm (empty-frame))
         (new-env (extend-env-frame env frm))
         (mk-proc-ref (lambda (args body)
                        (newref (proc-val-procedure args body new-env)))))
    (frame-set! frm
                list-of-name
                (map mk-proc-ref list-of-args list-of-body))
    new-env))

(define (apply-env env search-var)
  (define (search-env env)
    (cases environment env
      (empty-env () (report-unbound-var search-var))
      (extend-env-frame (enclosing-env frm)
        (search-frame (frame-vars frm) (frame-vals frm) enclosing-env))))
  (define (search-frame vars vals next-env)
    (if (null? vars)
      (search-env next-env)
      (if (eqv? search-var (car vars))
        (car vals)
        (search-frame (cdr vars) (cdr vals) next-env))))
  (search-env env))

(define (report-unbound-var search-var)
  (eopl:error "Unbound variable" search-var))

; continuation ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define-datatype continuation continuation?
  (end-cont)
  (a-cont
    (saved-cont continuation?)
    (env environment?)
    (cfrm cont-frame?)))

(define-datatype cont-frame cont-frame?
  (prim-cf
    (prim primitive?)
    (rands (list-of expression?)))
  (prim-cf1
    (prim primitive?)
    (vals (list-of expval?))
    (rands (list-of expression?)))
  (operator-cf
    (rands (list-of expression?)))
  (operands-cf1
    (rator expval?)
    (vals (list-of expval?))
    (rands (list-of expression?)))
  (if-cf
    (then-exp expression?)
    (else-exp expression?))
  (let-cf
    (vars (list-of symbol?))
    (rest-exps (list-of expression?))
    (body expression?))
  (let-cf1
    (vars (list-of symbol?))
    (vals (list-of expval?))
    (exps (list-of expression?))
    (body expression?))
  (assign-cf
    (var symbol?))
  (begin-cf
    (exps (list-of expression?)))
  (try-cf
    (var symbol?)
    (cont-var symbol?)
    (handler-exp expression?))
  (raise-cf)
  (cc-cf
    (exp expression?))
  (ccval-cf
    (cont continuation?)))

; apply-cont: continuation X expval -> expval
(define (apply-cont cont val)
  (cases continuation cont
    (end-cont () (eopl:printf "Fin.~%") val)
    (a-cont (saved-cont env cfrm)
      (cases cont-frame cfrm
        (prim-cf (prim rands)
          (apply-cont (a-cont saved-cont env
                              (prim-cf1 prim '() rands)) val))
        (prim-cf1 (prim vals rands)
          (let ((new-vals (cons val vals)))
            (if (null? rands)
              (apply-primitive/k prim (reverse new-vals) saved-cont)
              (value-of/k (car rands)
                          env
                          (a-cont saved-cont env
                                  (prim-cf1 prim new-vals (cdr rands)))))))
        (operator-cf (rands)
          (if (null? rands)
            (apply-proc-or-cont/k val '() saved-cont)
            (value-of/k (car rands)
                        env
                        (a-cont saved-cont env
                                (operands-cf1 val '() (cdr rands))))))
        (operands-cf1 (rator vals rands)
          (let ((new-vals (cons val vals)))
            (if (null? rands)
              (apply-proc-or-cont/k rator (reverse new-vals) saved-cont)
              (value-of/k (car rands)
                          env
                          (a-cont saved-cont env
                                  (operands-cf1 rator new-vals (cdr rands)))))))
        (if-cf (then-exp else-exp)
          (if (expval->bool val)
            (value-of/k then-exp env saved-cont)
            (value-of/k else-exp env saved-cont)))
        (let-cf (vars rest-exps body)
          (apply-cont (a-cont saved-cont env
                              (let-cf1 vars '() rest-exps body))
                      val))
        (let-cf1 (vars vals exps body)
          (let ((new-vals (cons val vals)))
            (if (null? exps)
              (value-of/k body
                          (extend-env env vars (reverse new-vals))
                          saved-cont)
              (value-of/k (car exps)
                          env
                          (a-cont saved-cont env
                                  (let-cf1 vars new-vals (cdr exps) body))))))
        (assign-cf (var)
          (setref! (apply-env env var) val)
          (apply-cont saved-cont '**void**))
        (begin-cf (exps)
          (if (null? exps)
            (apply-cont saved-cont val)
            (value-of/k (car exps) env (a-cont saved-cont env
                                               (begin-cf (cdr exps))))))
        (try-cf (var cont-var handler-exp)
          (apply-cont saved-cont val))
        (raise-cf ()
          (apply-handler val saved-cont))
        (cc-cf (exp)
          (value-of/k exp env (a-cont saved-cont env
                                      (ccval-cf (expval->cont val)))))
        (ccval-cf (applied-cont)
          (apply-cont applied-cont val))))))

(define (apply-handler val before-raised-cont)
  (define (iter cont)
    (cases continuation cont
      (end-cont () (report-uncaught-exception val before-raised-cont))
      (a-cont (saved-cont env cfrm)
        (cases cont-frame cfrm
          (try-cf (var cont-var handler-exp)
            (value-of/k handler-exp
                        (extend-env env
                                    (list var cont-var)
                                    (list val (cont-val before-raised-cont)))
                        saved-cont))
          (else (iter saved-cont))))))
  (iter before-raised-cont))

(define (report-uncaught-exception val cont)
  (eopl:error "uncaught-expception:" val cont))

; value-of ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define (value-of-program pgm)
  (initialize-store!)
  (cases program pgm
    (a-program (exp1)
      (value-of/k exp1 (init-env) (end-cont)))))

(define (print-store)
  (define (iter count lst)
    (if (null? lst)
      'done
      (begin
        (display count)(display " ")
        (eopl:pretty-print (car lst))
        (iter (+ count 1) (cdr lst)))))
  (display "###")(newline)
  (iter 0 the-store)
  (display "###")(newline))

(define (value-of-program-dbg-store pgm)
  (initialize-store!)
  (let ((ret (cases program pgm
               (a-program (exp1)
                 (value-of/k exp1 (init-env) (end-cont))))))
    (print-store)
    ret))

(define (value-of/k exp env cont)
  (cases expression exp
    (number-exp (number)
      (apply-cont cont (num-val number)))
    (var-exp (identifier)
      (apply-cont cont (deref (apply-env env identifier))))
    (proc-exp (list-of-var body)
      (apply-cont cont (proc-val-procedure list-of-var body env)))
    (apply-primitive-exp (prim list-of-exp)
      (if (null? list-of-exp)
        (apply-primitive/k prim '() cont)
        (value-of/k
          (car list-of-exp)
          env
          (a-cont cont env (prim-cf prim (cdr list-of-exp))))))
    (call-exp (rator rands)
      (value-of/k rator env (a-cont cont env (operator-cf rands))))
    (if-exp (exp1 exp2 exp3)
      (value-of/k exp1 env (a-cont cont env (if-cf exp2 exp3))))
    (let-exp (list-of-symbol list-of-exp body)
      (if (null? list-of-symbol)
        (value-of/k body env cont)
        (value-of/k
          (car list-of-exp)
          env
          (a-cont cont env (let-cf list-of-symbol (cdr list-of-exp) body)))))
    (letrec-exp (list-of-name list-of-args list-of-body letrec-body)
      (let ((new-env (extend-env-rec
                       env
                       list-of-name
                       list-of-args
                       list-of-body)))
        (value-of/k letrec-body new-env cont)))
    (assign-exp (var exp)
      (value-of/k exp env (a-cont cont env (assign-cf var))))
    (begin-exp (list-of-exp)
      (if (null? list-of-exp)
        (report-no-exps-in-begin)
        (value-of/k (car list-of-exp)
                    env
                    (a-cont cont env (begin-cf (cdr list-of-exp))))))
    (ref-exp (var)
      (apply-cont cont (ref-val (apply-env env var))))
    (try-exp (exp var cont-var handler-exp)
      (value-of/k exp env (a-cont cont env
                                  (try-cf var cont-var handler-exp))))
    (raise-exp (exp)
      (value-of/k exp env (a-cont cont env
                                  (raise-cf))))
    (cc-exp (exp1 exp2)
      (set! times-of-using-cc (+ 1 times-of-using-cc))
      (value-of/k exp1 env (a-cont cont env
                                   (cc-cf exp2))))
    (letcc-exp (var exp)
      (set! times-of-using-letcc (+ 1 times-of-using-letcc))
      (value-of/k exp (extend-env-1 env var (cont-val cont)) cont))))

(define (report-no-exps-in-begin)
  (eopl:error "no expressions between begin and end"))

(define (init-env) (empty-env))

(define (apply-primitive/k prim list-of-expval cont)
  (define (>> prim/expval)
    (apply-cont cont (apply prim/expval list-of-expval)))
  (cases primitive prim
    (add-prim () (>> add/expval))
    (diff-prim () (>> diff/expval))
    (mult-prim () (>> mult/expval))
    (minus-prim () (>> minus/expval))
    (quotient-prim () (>> quotient/expval))
    (remainder-prim () (>> remainder/expval))
    (zero?-prim () (>> zero?/expval))
    (equal?-prim () (>> equal?/expval))
    (greater?-prim () (>> greater?/expval))
    (less?-prim () (>> less?/expval))
    (pair-prim () (>> pair/expval))
    (left-prim () (>> left/expval))
    (right-prim () (>> right/expval))
    (setleft-prim () (>> setleft/expval))
    (setright-prim () (>> setright/expval))
    (deref-prim () (>> deref/expval))
    (setref-prim () (>> setref/expval))
    (call/cc-prim ()
      (apply call/cc/expval cont list-of-expval))))

; primitive procedures ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (add/expval . vals)
  (num-val (apply + (map expval->num vals))))

(define (diff/expval val1 val2)
  (num-val (- (expval->num val1) (expval->num val2))))

(define (mult/expval . vals)
  (num-val (apply * (map expval->num vals))))

(define (minus/expval val)
  (num-val (- (expval->num val))))

(define (quotient/expval val1 val2)
  (num-val (quotient (expval->num val1) (expval->num val2))))

(define (remainder/expval val1 val2)
  (num-val (remainder (expval->num val1) (expval->num val2))))

(define (zero?/expval val)
  (bool-val (zero? (expval->num val))))

(define (equal?/expval . vals)
  (bool-val (apply = (map expval->num vals))))

(define (greater?/expval . vals)
  (bool-val (apply > (map expval->num vals))))

(define (less?/expval . vals)
  (bool-val (apply < (map expval->num vals))))

(define (pair/expval val1 val2)
  (mutpair-val (newpair val1 val2)))

(define (left/expval val)
  (mutpair-left (expval->mutpair val)))

(define (right/expval val)
  (mutpair-right (expval->mutpair val)))

(define (setleft/expval val1 val2)
  (mutpair-setleft (expval->mutpair val1) val2)
  '**void**)

(define (setright/expval val1 val2)
  (mutpair-setright (expval->mutpair val1) val2)
  '**void**)

(define (deref/expval val)
  (deref (expval->ref val)))

(define (setref/expval val1 val2)
  (setref! (expval->ref val1) val2)
  '**void**)

(define (call/cc/expval cont val)
  (let ((proc (expval->proc val)))
    (apply-proc/k proc (list (cont-val cont)) cont)))

; read-eval-print ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define read-eval-print
  (sllgen:make-rep-loop
    "> " value-of-program
    (sllgen:make-stream-parser
      scanner-spec grammar-spec)))

;(read-eval-print)
