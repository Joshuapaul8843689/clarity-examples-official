;; title: yield-calculator-example
;; version: 1.0.0
;; summary: Example yield calculation and distribution mechanism
;; description: Production-grade yield farming and staking rewards system

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-INSUFFICIENT-BALANCE (err u201))
(define-constant ERR-POOL-NOT-FOUND (err u202))
(define-constant ERR-INVALID-AMOUNT (err u203))
(define-constant ERR-ALREADY-STAKED (err u204))
(define-constant ERR-NOT-STAKED (err u205))
(define-constant ERR-REWARD-CALCULATION-ERROR (err u206))
(define-constant ERR-POOL-INACTIVE (err u207))

;; Configuration constants
(define-constant BLOCKS-PER-YEAR u52560) ;; Approximate blocks per year
(define-constant PRECISION u10000) ;; For percentage calculations
(define-constant MIN-STAKE-DURATION u144) ;; Minimum 1 day staking
(define-constant MAX-POOLS u10) ;; Maximum number of pools

;; Contract owner
(define-data-var contract-owner principal tx-sender)

;; Pool counter for unique IDs
(define-data-var pool-counter uint u0)

;; Total protocol statistics
(define-data-var total-staked uint u0)
(define-data-var total-rewards-distributed uint u0)

;; Yield pool structure
(define-map yield-pools
  { pool-id: uint }
  {
    name: (string-ascii 50),
    token-symbol: (string-ascii 10),
    apy-rate: uint, ;; Annual percentage yield in basis points (10000 = 100%)
    total-staked: uint,
    total-rewards-paid: uint,
    creation-block: uint,
    is-active: bool,
    min-stake-amount: uint,
    lock-period: uint ;; in blocks
  }
)

;; User stakes in pools
(define-map user-stakes
  { user: principal, pool-id: uint }
  {
    staked-amount: uint,
    stake-block: uint,
    last-claim-block: uint,
    total-rewards-claimed: uint
  }
)

;; User total balances across all pools
(define-map user-balances
  { user: principal }
  { 
    total-staked: uint,
    total-rewards: uint
  }
)

;; Pool participants for iteration
(define-map pool-participants
  { pool-id: uint, user: principal }
  { active: bool }
)

;; Private functions

(define-private (calculate-yield-per-block (apy-rate uint))
  ;; Convert APY to per-block yield rate
  (/ apy-rate (* BLOCKS-PER-YEAR PRECISION))
)

(define-private (calculate-rewards (stake-amount uint) (apy-rate uint) (blocks-staked uint))
  (let (
    (yield-per-block (calculate-yield-per-block apy-rate))
    (total-yield-basis (* stake-amount yield-per-block blocks-staked))
  )
    (/ total-yield-basis PRECISION)
  )
)

(define-private (is-admin (user principal))
  (is-eq user (var-get contract-owner))
)

(define-private (update-user-balance (user principal) (stake-change int) (reward-change uint))
  (let (
    (current-balance (default-to { total-staked: u0, total-rewards: u0 } 
                      (map-get? user-balances { user: user })))
    (new-staked (if (>= stake-change 0)
                  (+ (get total-staked current-balance) (to-uint stake-change))
                  (- (get total-staked current-balance) (to-uint (- stake-change)))))
    (new-rewards (+ (get total-rewards current-balance) reward-change))
  )
    (map-set user-balances
      { user: user }
      {
        total-staked: new-staked,
        total-rewards: new-rewards
      }
    )
    (ok true)
  )
)

;; Public functions

;; Create new yield pool
(define-public (create-pool (name (string-ascii 50)) (token-symbol (string-ascii 10)) 
                           (apy-rate uint) (min-stake-amount uint) (lock-period uint))
  (let (
    (pool-id (+ (var-get pool-counter) u1))
  )
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (< (var-get pool-counter) MAX-POOLS) ERR-NOT-AUTHORIZED)
    (asserts! (> apy-rate u0) ERR-INVALID-AMOUNT)
    (asserts! (> min-stake-amount u0) ERR-INVALID-AMOUNT)
    
    ;; Create pool
    (map-set yield-pools
      { pool-id: pool-id }
      {
        name: name,
        token-symbol: token-symbol,
        apy-rate: apy-rate,
        total-staked: u0,
        total-rewards-paid: u0,
        creation-block: stacks-block-height,
        is-active: true,
        min-stake-amount: min-stake-amount,
        lock-period: lock-period
      }
    )
    
    (var-set pool-counter pool-id)
    (ok pool-id)
  )
)

;; Stake tokens in a pool
(define-public (stake-tokens (pool-id uint) (amount uint))
  (let (
    (pool (unwrap! (map-get? yield-pools { pool-id: pool-id }) ERR-POOL-NOT-FOUND))
    (existing-stake (map-get? user-stakes { user: tx-sender, pool-id: pool-id }))
  )
    ;; Validation checks
    (asserts! (get is-active pool) ERR-POOL-INACTIVE)
    (asserts! (>= amount (get min-stake-amount pool)) ERR-INVALID-AMOUNT)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    ;; Check if user already has stake in this pool
    (match existing-stake
      stake ERR-ALREADY-STAKED
      ;; New stake
      (begin
        ;; Transfer tokens to contract (simplified)
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        ;; Create stake record
        (map-set user-stakes
          { user: tx-sender, pool-id: pool-id }
          {
            staked-amount: amount,
            stake-block: stacks-block-height,
            last-claim-block: stacks-block-height,
            total-rewards-claimed: u0
          }
        )
        
        ;; Mark user as participant
        (map-set pool-participants
          { pool-id: pool-id, user: tx-sender }
          { active: true }
        )
        
        ;; Update pool totals
        (map-set yield-pools
          { pool-id: pool-id }
          (merge pool { total-staked: (+ (get total-staked pool) amount) })
        )
        
        ;; Update user balance tracking
        (unwrap-panic (update-user-balance tx-sender (to-int amount) u0))
        
        ;; Update global statistics
        (var-set total-staked (+ (var-get total-staked) amount))
        
        (ok amount)
      )
    )
  )
)

;; Claim accumulated rewards
(define-public (claim-rewards (pool-id uint))
  (let (
    (pool (unwrap! (map-get? yield-pools { pool-id: pool-id }) ERR-POOL-NOT-FOUND))
    (stake (unwrap! (map-get? user-stakes { user: tx-sender, pool-id: pool-id }) ERR-NOT-STAKED))
    (blocks-since-claim (- stacks-block-height (get last-claim-block stake)))
    (rewards (calculate-rewards (get staked-amount stake) (get apy-rate pool) blocks-since-claim))
  )
    (asserts! (> rewards u0) ERR-INVALID-AMOUNT)
    
    ;; Update stake record with new claim block
    (map-set user-stakes
      { user: tx-sender, pool-id: pool-id }
      (merge stake {
        last-claim-block: stacks-block-height,
        total-rewards-claimed: (+ (get total-rewards-claimed stake) rewards)
      })
    )
    
    ;; Update pool rewards paid
    (map-set yield-pools
      { pool-id: pool-id }
      (merge pool { total-rewards-paid: (+ (get total-rewards-paid pool) rewards) })
    )
    
    ;; Update user balance tracking
    (unwrap-panic (update-user-balance tx-sender 0 rewards))
    
    ;; Update global statistics
    (var-set total-rewards-distributed (+ (var-get total-rewards-distributed) rewards))
    
    ;; Transfer rewards to user (simplified)
    (try! (as-contract (stx-transfer? rewards tx-sender tx-sender)))
    
    (ok rewards)
  )
)

;; Unstake tokens and claim final rewards
(define-public (unstake-tokens (pool-id uint))
  (let (
    (pool (unwrap! (map-get? yield-pools { pool-id: pool-id }) ERR-POOL-NOT-FOUND))
    (stake (unwrap! (map-get? user-stakes { user: tx-sender, pool-id: pool-id }) ERR-NOT-STAKED))
    (blocks-staked (- stacks-block-height (get stake-block stake)))
    (blocks-since-claim (- stacks-block-height (get last-claim-block stake)))
    (final-rewards (calculate-rewards (get staked-amount stake) (get apy-rate pool) blocks-since-claim))
    (stake-amount (get staked-amount stake))
  )
    ;; Check minimum staking period
    (asserts! (>= blocks-staked (get lock-period pool)) ERR-INVALID-AMOUNT)
    
    ;; Remove stake record
    (map-delete user-stakes { user: tx-sender, pool-id: pool-id })
    
    ;; Remove from participants
    (map-delete pool-participants { pool-id: pool-id, user: tx-sender })
    
    ;; Update pool totals
    (map-set yield-pools
      { pool-id: pool-id }
      (merge pool {
        total-staked: (- (get total-staked pool) stake-amount),
        total-rewards-paid: (+ (get total-rewards-paid pool) final-rewards)
      })
    )
    
    ;; Update user balance tracking
    (unwrap-panic (update-user-balance tx-sender (- (to-int stake-amount)) final-rewards))
    
    ;; Update global statistics
    (var-set total-staked (- (var-get total-staked) stake-amount))
    (var-set total-rewards-distributed (+ (var-get total-rewards-distributed) final-rewards))
    
    ;; Transfer staked amount back to user
    (try! (as-contract (stx-transfer? stake-amount tx-sender tx-sender)))
    
    ;; Transfer final rewards to user
    (if (> final-rewards u0)
      (try! (as-contract (stx-transfer? final-rewards tx-sender tx-sender)))
      true
    )
    
    (ok { unstaked: stake-amount, final-rewards: final-rewards })
  )
)

;; Compound rewards (restake them)
(define-public (compound-rewards (pool-id uint))
  (let (
    (pool (unwrap! (map-get? yield-pools { pool-id: pool-id }) ERR-POOL-NOT-FOUND))
    (stake (unwrap! (map-get? user-stakes { user: tx-sender, pool-id: pool-id }) ERR-NOT-STAKED))
    (blocks-since-claim (- stacks-block-height (get last-claim-block stake)))
    (rewards (calculate-rewards (get staked-amount stake) (get apy-rate pool) blocks-since-claim))
    (new-stake-amount (+ (get staked-amount stake) rewards))
  )
    (asserts! (> rewards u0) ERR-INVALID-AMOUNT)
    
    ;; Update stake record with compounded amount
    (map-set user-stakes
      { user: tx-sender, pool-id: pool-id }
      (merge stake {
        staked-amount: new-stake-amount,
        last-claim-block: stacks-block-height,
        total-rewards-claimed: (+ (get total-rewards-claimed stake) rewards)
      })
    )
    
    ;; Update pool totals
    (map-set yield-pools
      { pool-id: pool-id }
      (merge pool {
        total-staked: (+ (get total-staked pool) rewards),
        total-rewards-paid: (+ (get total-rewards-paid pool) rewards)
      })
    )
    
    ;; Update global statistics
    (var-set total-staked (+ (var-get total-staked) rewards))
    (var-set total-rewards-distributed (+ (var-get total-rewards-distributed) rewards))
    
    (ok rewards)
  )
)

;; Read-only functions

(define-read-only (get-pool (pool-id uint))
  (map-get? yield-pools { pool-id: pool-id })
)

(define-read-only (get-user-stake (user principal) (pool-id uint))
  (map-get? user-stakes { user: user, pool-id: pool-id })
)

(define-read-only (get-user-balance (user principal))
  (default-to { total-staked: u0, total-rewards: u0 }
    (map-get? user-balances { user: user })
  )
)

(define-read-only (calculate-pending-rewards (user principal) (pool-id uint))
  (match (map-get? user-stakes { user: user, pool-id: pool-id })
    stake
    (match (map-get? yield-pools { pool-id: pool-id })
      pool
      (let (
        (blocks-since-claim (- stacks-block-height (get last-claim-block stake)))
        (rewards (calculate-rewards (get staked-amount stake) (get apy-rate pool) blocks-since-claim))
      )
        (ok rewards)
      )
      ERR-POOL-NOT-FOUND
    )
    ERR-NOT-STAKED
  )
)

(define-read-only (get-pool-apy (pool-id uint))
  (match (map-get? yield-pools { pool-id: pool-id })
    pool (ok (get apy-rate pool))
    ERR-POOL-NOT-FOUND
  )
)

(define-read-only (get-protocol-stats)
  {
    total-pools: (var-get pool-counter),
    total-staked: (var-get total-staked),
    total-rewards-distributed: (var-get total-rewards-distributed)
  }
)

(define-read-only (get-yield-projection (amount uint) (pool-id uint) (duration-blocks uint))
  (match (map-get? yield-pools { pool-id: pool-id })
    pool
    (let (
      (projected-rewards (calculate-rewards amount (get apy-rate pool) duration-blocks))
    )
      (ok {
        initial-amount: amount,
        projected-rewards: projected-rewards,
        final-amount: (+ amount projected-rewards),
        apy-rate: (get apy-rate pool)
      })
    )
    ERR-POOL-NOT-FOUND
  )
)

;; Admin functions

(define-public (update-pool-apy (pool-id uint) (new-apy uint))
  (let (
    (pool (unwrap! (map-get? yield-pools { pool-id: pool-id }) ERR-POOL-NOT-FOUND))
  )
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> new-apy u0) ERR-INVALID-AMOUNT)
    
    (map-set yield-pools
      { pool-id: pool-id }
      (merge pool { apy-rate: new-apy })
    )
    
    (ok new-apy)
  )
)

(define-public (toggle-pool-status (pool-id uint))
  (let (
    (pool (unwrap! (map-get? yield-pools { pool-id: pool-id }) ERR-POOL-NOT-FOUND))
  )
    (asserts! (is-admin tx-sender) ERR-NOT-AUTHORIZED)
    
    (map-set yield-pools
      { pool-id: pool-id }
      (merge pool { is-active: (not (get is-active pool)) })
    )
    
    (ok (not (get is-active pool)))
  )
)

