;; title: borrowing-protocol-example
;; version: 1.0.0
;; summary: Educational borrowing system with collateral management
;; description: Production-grade implementation for enterprise use

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INSUFFICIENT-COLLATERAL (err u101))
(define-constant ERR-LOAN-NOT-FOUND (err u102))
(define-constant ERR-LOAN-ALREADY-REPAID (err u103))
(define-constant ERR-LIQUIDATION-NOT-ALLOWED (err u104))
(define-constant ERR-INVALID-AMOUNT (err u105))
(define-constant ERR-COLLATERAL-RATIO-TOO-LOW (err u106))

;; Configuration constants
(define-constant MINIMUM-COLLATERAL-RATIO u150) ;; 150% minimum collateral ratio
(define-constant LIQUIDATION-THRESHOLD u120) ;; 120% liquidation threshold
(define-constant LIQUIDATION-PENALTY u110) ;; 10% liquidation penalty
(define-constant INTEREST-RATE-PER-BLOCK u1) ;; 0.01% per block
(define-constant MAX-LOAN-DURATION u52560) ;; ~1 year in blocks

;; Contract owner
(define-data-var contract-owner principal tx-sender)

;; Protocol statistics
(define-data-var total-loans-issued uint u0)
(define-data-var total-collateral-locked uint u0)
(define-data-var total-outstanding-debt uint u0)

;; Loan structure
(define-map loans
  { loan-id: uint }
  {
    borrower: principal,
    collateral-amount: uint,
    borrowed-amount: uint,
    interest-accrued: uint,
    creation-block: uint,
    status: (string-ascii 20) ;; "active", "repaid", "liquidated"
  }
)

;; User collateral balances
(define-map user-collateral
  { user: principal }
  { amount: uint }
)

;; Loan counter for unique IDs
(define-data-var loan-counter uint u0)

;; Oracle price (simplified for example)
(define-data-var collateral-price uint u100) ;; $1.00 in cents

;; Private functions

(define-private (calculate-interest (principal-amount uint) (blocks-elapsed uint))
  (/ (* principal-amount INTEREST-RATE-PER-BLOCK blocks-elapsed) u10000)
)

(define-private (calculate-collateral-ratio (collateral-amount uint) (debt-amount uint))
  (if (is-eq debt-amount u0)
    u0
    (/ (* collateral-amount (var-get collateral-price)) debt-amount)
  )
)

(define-private (is-authorized (user principal))
  (or (is-eq user tx-sender) (is-eq tx-sender (var-get contract-owner)))
)

;; Public functions

;; Deposit collateral
(define-public (deposit-collateral (amount uint))
  (begin
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (let (
      (current-balance (default-to u0 (get amount (map-get? user-collateral { user: tx-sender }))))
      (new-balance (+ current-balance amount))
    )
      ;; Transfer tokens to contract (simplified - assumes STX)
      (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
      
      ;; Update user balance
      (map-set user-collateral
        { user: tx-sender }
        { amount: new-balance }
      )
      
      ;; Update total collateral locked
      (var-set total-collateral-locked (+ (var-get total-collateral-locked) amount))
      
      (ok new-balance)
    )
  )
)

;; Create loan
(define-public (create-loan (collateral-amount uint) (borrow-amount uint))
  (let (
    (user-balance (default-to u0 (get amount (map-get? user-collateral { user: tx-sender }))))
    (collateral-ratio (calculate-collateral-ratio collateral-amount borrow-amount))
    (loan-id (+ (var-get loan-counter) u1))
  )
    ;; Validation checks
    (asserts! (> borrow-amount u0) ERR-INVALID-AMOUNT)
    (asserts! (>= user-balance collateral-amount) ERR-INSUFFICIENT-COLLATERAL)
    (asserts! (>= collateral-ratio MINIMUM-COLLATERAL-RATIO) ERR-COLLATERAL-RATIO-TOO-LOW)
    
    ;; Lock collateral
    (map-set user-collateral
      { user: tx-sender }
      { amount: (- user-balance collateral-amount) }
    )
    
    ;; Create loan record
    (map-set loans
      { loan-id: loan-id }
      {
        borrower: tx-sender,
        collateral-amount: collateral-amount,
        borrowed-amount: borrow-amount,
        interest-accrued: u0,
        creation-block: stacks-block-height,
        status: "active"
      }
    )
    
    ;; Update counters
    (var-set loan-counter loan-id)
    (var-set total-loans-issued (+ (var-get total-loans-issued) u1))
    (var-set total-outstanding-debt (+ (var-get total-outstanding-debt) borrow-amount))
    
    ;; Transfer borrowed amount to user (simplified)
    (try! (as-contract (stx-transfer? borrow-amount tx-sender tx-sender)))
    
    (ok loan-id)
  )
)

;; Repay loan
(define-public (repay-loan (loan-id uint))
  (let (
    (loan (unwrap! (map-get? loans { loan-id: loan-id }) ERR-LOAN-NOT-FOUND))
    (blocks-elapsed (- stacks-block-height (get creation-block loan)))
    (interest (calculate-interest (get borrowed-amount loan) blocks-elapsed))
    (total-repayment (+ (get borrowed-amount loan) interest))
    (user-balance (default-to u0 (get amount (map-get? user-collateral { user: tx-sender }))))
  )
    ;; Validation checks
    (asserts! (is-eq (get borrower loan) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status loan) "active") ERR-LOAN-ALREADY-REPAID)
    
    ;; Transfer repayment to contract
    (try! (stx-transfer? total-repayment tx-sender (as-contract tx-sender)))
    
    ;; Release collateral back to user
    (map-set user-collateral
      { user: tx-sender }
      { amount: (+ user-balance (get collateral-amount loan)) }
    )
    
    ;; Update loan status
    (map-set loans
      { loan-id: loan-id }
      (merge loan {
        status: "repaid",
        interest-accrued: interest
      })
    )
    
    ;; Update outstanding debt
    (var-set total-outstanding-debt (- (var-get total-outstanding-debt) (get borrowed-amount loan)))
    
    (ok total-repayment)
  )
)

;; Liquidate undercollateralized loan
(define-public (liquidate-loan (loan-id uint))
  (let (
    (loan (unwrap! (map-get? loans { loan-id: loan-id }) ERR-LOAN-NOT-FOUND))
    (blocks-elapsed (- stacks-block-height (get creation-block loan)))
    (interest (calculate-interest (get borrowed-amount loan) blocks-elapsed))
    (total-debt (+ (get borrowed-amount loan) interest))
    (current-ratio (calculate-collateral-ratio (get collateral-amount loan) total-debt))
    (liquidation-amount (* total-debt LIQUIDATION-PENALTY))
    (liquidation-amount-divided (/ liquidation-amount u100))
  )
    ;; Validation checks
    (asserts! (is-eq (get status loan) "active") ERR-LOAN-ALREADY-REPAID)
    (asserts! (<= current-ratio LIQUIDATION-THRESHOLD) ERR-LIQUIDATION-NOT-ALLOWED)
    
    ;; Transfer liquidation payment to contract
    (try! (stx-transfer? liquidation-amount-divided tx-sender (as-contract tx-sender)))
    
    ;; Transfer collateral to liquidator
    (try! (as-contract (stx-transfer? (get collateral-amount loan) tx-sender tx-sender)))
    
    ;; Update loan status
    (map-set loans
      { loan-id: loan-id }
      (merge loan {
        status: "liquidated",
        interest-accrued: interest
      })
    )
    
    ;; Update outstanding debt
    (var-set total-outstanding-debt (- (var-get total-outstanding-debt) (get borrowed-amount loan)))
    
    (ok true)
  )
)

;; Withdraw available collateral
(define-public (withdraw-collateral (amount uint))
  (let (
    (user-balance (default-to u0 (get amount (map-get? user-collateral { user: tx-sender }))))
  )
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (>= user-balance amount) ERR-INSUFFICIENT-COLLATERAL)
    
    ;; Update user balance
    (map-set user-collateral
      { user: tx-sender }
      { amount: (- user-balance amount) }
    )
    
    ;; Transfer collateral to user
    (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
    
    ;; Update total collateral locked
    (var-set total-collateral-locked (- (var-get total-collateral-locked) amount))
    
    (ok amount)
  )
)

;; Read-only functions

(define-read-only (get-loan (loan-id uint))
  (map-get? loans { loan-id: loan-id })
)

(define-read-only (get-user-collateral (user principal))
  (default-to u0 (get amount (map-get? user-collateral { user: user })))
)

(define-read-only (get-loan-health (loan-id uint))
  (match (map-get? loans { loan-id: loan-id })
    loan
    (let (
      (blocks-elapsed (- stacks-block-height (get creation-block loan)))
      (interest (calculate-interest (get borrowed-amount loan) blocks-elapsed))
      (total-debt (+ (get borrowed-amount loan) interest))
      (current-ratio (calculate-collateral-ratio (get collateral-amount loan) total-debt))
    )
      (ok {
        collateral-ratio: current-ratio,
        total-debt: total-debt,
        can-be-liquidated: (<= current-ratio LIQUIDATION-THRESHOLD)
      })
    )
    ERR-LOAN-NOT-FOUND
  )
)

(define-read-only (get-protocol-stats)
  {
    total-loans: (var-get total-loans-issued),
    total-collateral: (var-get total-collateral-locked),
    total-debt: (var-get total-outstanding-debt),
    collateral-price: (var-get collateral-price)
  }
)

;; Admin functions

(define-public (set-collateral-price (new-price uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set collateral-price new-price)
    (ok new-price)
  )
)

