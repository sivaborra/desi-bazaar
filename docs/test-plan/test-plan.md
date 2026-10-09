# Desi Bazaar — Acceptance Test Plan

_Version 1.3 — 2026-10-09 — 191 cases (SC-1 ads: DB-TC-187–189; SC-2 listing video: DB-TC-184–186; email OTP: DB-TC-190–191). Implementation approved; slice-1 backend + Flutter app built._
_Basis: `desi-bazaar-requirements-spec.md` v1.5 FROZEN (Phase-1 implementation baseline)._
_Companion: `test-cases.csv` (DB-TC-001…, each traced to a requirement)._

## 1. Approach

Tests-first per our standard engineering practice: the test plan is reviewed and frozen before design or build. Test cases are acceptance-level (what the user/admin experiences), not unit tests — implementation teams derive unit tests from them.

## 2. Scope

**In scope:** all Phase-1 functional requirements (§3), the §11 transition model (every row + guard rejections + 9 invariants), §5 Phase-1 fraud gates, §3.10 deletion, §4.2 security negatives, §4.3 privacy, §4.6 brand metrics, IC-1/IC-2/IC-3 clarifications.

**Out of scope:** Phase-2 items (Option A held funds, trust upgrade at 50 sellers), food listings, web app, multi-seller carts, performance/load testing (separate NFR plan if needed).

## 3. Test types

| Type | Meaning |
|---|---|
| Acceptance | Happy-path: the requirement works as specified |
| Transition | §11 state-model: a specific From → To row, incl. actor/guard/evidence/stock/notify |
| Negative | Guard rejection: the system must refuse or reroute |
| Fraud | §5 attack scenarios — detection, recovery, limits |
| Security | §4.2 negatives: auth, authorisation, abuse limits |
| Privacy | §4.3: rights, retention, breach, vendor handling |

## 4. Priority

- **P1** — must pass for the slice to be accepted (core loop, money safety, legal gates)
- **P2** — must pass before public pilot (trust, moderation, operations)
- **P3** — must pass before live transactions (polish, metrics, edge cases)

## 5. Phase mapping (to §13 slices)

| Slice | Tests | Count |
|---|---|---|
| 1 — core loop | DB-TC-001–007, 011–013, 015–016, 018–023, 027, 029–030, 042, 045, 047, 052–053, 083, 108, 111, 116, 118, 126–133, 148, 150–151, 176–177 | 44 |
| 2 — money edge cases | DB-TC-009–010, 014, 017, 028, 031–041, 046, 048–051, 054–082, 084–098, 100, 103–107, 109–110, 141–145, 149, 155–163, 166–167, 178–183 | 96 |
| 2 — media & ads (SC-1/SC-2) | DB-TC-184–189 | 6 |
| 1 — auth (email OTP, FR-B1) | DB-TC-190–191 | 2 |
| 3 — trust & safety | DB-TC-008, 024–026, 043–044, 099, 101–102, 112–115, 117, 119–120, 146, 152–154, 170–171 | 22 |
| 4 — compliance | DB-TC-121–125, 134–140, 164–165, 169 | 15 |
| 5 — launch gates | DB-TC-147, 168, 172–175 | 6 |

_These lists are generated from the CSV's Slice column — the CSV is authoritative. 191 cases total: 74 Acceptance, 38 Negative, 51 Transition, 10 Security, 12 Privacy, 6 Fraud; slice 2 gains 6 media/ads cases (DB-TC-184–189); email OTP adds DB-TC-190–191._

**Regression rule:** security and privacy P1 cases (DB-TC-118, 126–133, 138, 140) are owned by their first applicable slice and re-run in every later slice. A case has one owning slice; regression applicability is recorded here, not by duplicating the case.

## 5b. Priority vs stage (separate columns)

| Column | Values | Meaning |
|---|---|---|
| Priority | P1 / P2 / P3 | Importance of the behaviour |
| Slice | 1–5 | First slice that must pass it (owning slice) |
| RequiredBefore | Slice acceptance / Public pilot / Live transactions | The stage gate it blocks |
| ReleaseBlocking | yes / no | Whether an open defect here blocks the stage |

P1 ≈ must pass for slice acceptance; P2 ≈ public pilot; P3 ≈ live transactions — but they are independent: a P3 case can still be RequiredBefore public pilot (e.g., image screening DB-TC-115, community standards DB-TC-116) when the behaviour is public-facing.

**Exit wording:** a stage passes only when all cases marked required for that stage have passed and no release-blocking defects remain open.

## 6. Entry / exit criteria

**Entry (test execution may start):** test plan approved and frozen; test environment with synthetic data only (no real PII per IC-3); §11/§12 schema frozen.

**Exit (slice accepted):** all P1 cases for the slice pass; P2/P3 failures logged with severity and owner; no open P1 defects; evidence checklist items for the slice signed off. **Fraud gates (§5, DB-TC-141–146):** each case is owned by its slice for acceptance, but all six must pass before **live transactions** — they are release gates, not slice-2 gates.

## 7. Traceability

Every test case cites its requirement ID (multiple IDs separated by `;` where a case covers more than one). Coverage rule: each FR/NFR and each §11 row maps to ≥1 test case; each invariant maps to ≥1 negative test. The CSV's Requirement column is the traceability matrix — no separate document. **Coverage claim (honest):** mappings re-checked in review rounds 7–9; cells marked "gap" are known-uncovered and listed below. No blanket completeness claim is made. Per-transition negative coverage (wrong actor / invalid evidence / retry) is explicit for money-sensitive transitions (DB-TC-155, 162–163, 166–167); remaining transitions carry guard-rejection cases where the spec defines the guard.

## 7b. Transition coverage matrix (§11)

Each canonical transition row, its stable test ID(s), and which negative dimensions are covered. Conventions: P=positive, WA=wrong actor, IS=invalid source state, FG=failed guard, IE=invalid/missing evidence, R=retry/idempotency, C=concurrency.

**Payment dimension**

| Transition | P | WA | IS | FG | IE | R | C |
|---|---|---|---|---|---|---|---|
| payment_unreported → payment_reported | 045 | — | gap | gap | — | 166 | — |
| payment_unreported → payment_unresolved | 046 | — | — | — | — | — | — |
| payment_reported → payment_seller_confirmed | 047 | — | — | 163 | 163 | — | — |
| payment_reported → payment_unresolved | 048 | — | — | — | — | — | — |
| payment_unresolved → payment_seller_confirmed | 049 | — | — | 050 | — | — | — |
| payment_unresolved → refund_requested | 050 | — | — | — | — | — | — |
| payment_unresolved → payment_established_unpaid | 051 | — | — | — | — | — | — |

**Fulfilment dimension**

| Transition | P | WA | IS | FG | IE | R | C |
|---|---|---|---|---|---|---|---|
| order creation (all dimensions atomic) | 177 | — | — | gap | — | — | gap |
| stock_reserved → stock_released | 052 | — | — | — | — | — | — |
| stock_reserved → dispatched | 053 | — | — | 030, 082, 090 | — | — | 083 |
| dispatched → receipt_confirmed | 054 | — | — | — | — | — | — |
| dispatched → delivery_evidenced | 055 | — | gap | — | — | — | — |
| dispatched → delivery_unconfirmed | 056 | — | — | — | — | — | — |
| delivery_evidenced/unconfirmed → receipt_confirmed | 057, 156 | — | — | — | — | — | — |
| late evidence after delivery_unconfirmed | 159 | — | — | — | — | — | — |

**Cancellation/refund dimension**

| Transition | P | WA | IS | FG | IE | R | C |
|---|---|---|---|---|---|---|---|
| no_cancel → cancellation_requested | 058 | — | — | — | — | — | 091–093 |
| → cancelled_unpaid | 059, 034 | — | — | — | — | — | — |
| → refund_requested | 060, 035 | — | — | — | — | — | — |
| refund_requested → refund_reported | 061, 036 | 162 | — | — | — | — | — |
| refund_reported → refund_acknowledged | 062 | 063, 089 | — | — | gap | — | — |
| refund_reported → refund_contested | 064 | — | — | — | — | — | — |
| refund_contested → refund_acknowledged | 065 | 063 | — | — | — | — | — |
| refund_contested → dispute_open | 066 | — | — | — | — | — | — |

**Return dimension**

| Transition | P | WA | IS | FG | IE | R | C |
|---|---|---|---|---|---|---|---|
| return_none → return_requested | 067 | — | — | — | — | — | — |
| return_requested → return_authorised | 157 | — | gap | — | — | — | — |
| return_requested → goods_sent_back (statutory/defective) | 068, 158 | — | — | — | — | — | — |
| return_authorised → goods_sent_back | 070 | — | — | — | — | — | — |
| goods_sent_back → return_received | 071 | — | — | — | — | — | — |
| goods_sent_back → refund_requested | 072 | — | — | — | — | — | — |
| return_received → refund_requested | 073 | — | — | — | — | — | — |

**Dispute dimension**

| Transition | P | WA | IS | FG | IE | R | C |
|---|---|---|---|---|---|---|---|
| dispute_none → dispute_open | 075, 095 | — | — | — | gap | 167 | — |
| dispute_open → dispute_decided | 077 | — | — | — | — | — | — |
| → dispute_resolved | 078 | — | — | 086 | 098 | — | — |
| → dispute_closed_unconfirmed | 079 | — | — | 087 | — | — | — |
| → dispute_non_compliant | 080, 099 | — | — | — | — | — | — |
| reopen on new evidence | 081, 160, 161 | — | — | — | — | — | — |

Gaps to close in implementation test design ("gap" cells above): wrong-actor on payment_unresolved transitions; invalid source/evidence for delivery_evidenced, refund_reported→refund_acknowledged, and dispute filing; evidence-validation specifics per operation (API design, design doc §9).

## 8. Defect handling

Defects get IDs (DB-BUG-###), severity, and a spec reference. A defect against frozen v1.5 is either an implementation bug or a spec defect — spec defects follow the change rule (§14 headnote): demonstrated defect → ID + test + Siva's approval + log entry. No silent spec edits.

## 8b. Performance (NFR-P1)

Not covered by acceptance cases. Separate **NFR test plan**, required before public pilot.

**Gate (explicit clarification, recorded 2026-10-08):** feed load **p95 ≤ 2.0s**. Median is diagnostic only.

- **Timing:** start = user action that opens the feed (tap); end = feed-ready.
- **Feed-ready:** first 10 listing cards rendered with images decoded (placeholders don't count).
- **Percentile:** p95 over 20 cold-start runs (app killed, OS image cache cleared between runs).
- **Dataset:** 500 listings with images (mixed sizes, max upload enforced, EXIF stripped).
- **Network:** throttled 4G — 9 Mbps down / 2 Mbps up / 80ms RTT.
- **Devices:** one representative Android (2023-era, e.g. Pixel 6a class) AND one representative iPhone (2022-era, e.g. iPhone 12 class). Both must pass.
- **Image handling:** client-side compression verified; max upload size enforced server-side (NFR-S4).
- **Owner/evidence:** TBD at slice 3; results recorded per device with dataset hash and network profile.

## 9. What Siva reviews

1. Coverage: does every requirement and every §11 row have a test?
2. Correctness: do the expected results match the frozen spec?
3. Priority: is the P1/P2/P3 assignment right?
4. Anything missing that a buyer, seller, or admin would hit on day one?

## 10. Open items

- False-dispatch fraud attribution (DB-TC-142): absence of success signals is tested; what evidence establishes *fraudulent* dispatch needs a policy definition.
- Pre-order (listing) chat: out of scope pending Siva's decision (FR-C1 is order-linked).

1. Coverage: does every requirement and every §11 row have a test?
2. Correctness: do the expected results match the frozen spec?
3. Priority: is the P1/P2/P3 assignment right?
4. Anything missing that a buyer, seller, or admin would hit on day one?
