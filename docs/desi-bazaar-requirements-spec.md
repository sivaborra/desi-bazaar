# Desi Bazaar — Software Requirements Specification

_Version 1.6 — 2026-10-09 — **Status: Phase-1 implementation baseline (accepted by Siva Borra, 2026-10-09).** v1.5 (2026-10-08) is preserved as the frozen record; v1.6 = v1.5 + approved scope changes SC-1 and SC-2 only. Change rule unchanged: further changes only for demonstrated defects, security/compliance needs, or explicit scope decisions (ID + test + approval + log)._
**v1.6 change log:** SC-1 Advertisements — new §3.11 (promoted listings + sponsored slots; third-party ad networks out of v1). SC-2 Listing video — new FR-L5 (up to 8 images + 2 videos ≤60s per listing); NFR-P1/NFR-S4 extended to video; new IC-4 (signed-URL media upload). Tests DB-TC-184–189 added (189 total).
_Owner: Baltic Systems AB. Author: Siva Borra (with AI-assisted drafting)._
_Governing document: this spec governs implementation. The earlier review v2 (`desi-bazaar-app-requirements-review-v2.md`) is background rationale — where they disagree, this spec wins._
_Peer review history: v1 → GPT round 1 (18 findings) → v2 + spec v1.0 → GPT round 2 (17 findings) → spec v1.1 → Claude incremental review (9 findings) → spec v1.2 → GPT incremental review of v1.2 (9 findings) → spec v1.3 → Claude incremental review of v1.3 (6 findings, all §11 transaction model) → spec v1.4 → freeze assessment (2 mandatory transaction corrections) → spec v1.5 (this: statutory withdrawal not gated on seller authorisation; late payment confirmation never restores released stock)._
_Legal note: Swedish-law findings (intermediary role, DAC7) are flagged as requiring professional assessment — this spec states the requirement to obtain it, not the legal conclusion._

## 1. Introduction

### 1.1 Purpose
This document specifies the requirements for the Desi Bazaar MVP (Phase 1): a clothes-first marketplace app for Indians and Bangladeshis in Sweden, on Android and iOS.

### 1.2 Scope
In scope: seller onboarding with manual approval, buyer registration, listings, search, in-app chat, direct seller payment (Swish), order tracking, reviews with AI-assisted moderation, dispute mediation, admin console.
Out of scope for Phase 1: held-funds escrow, automated payouts, food listings, web app, multi-seller carts.

### 1.3 Conventions
Requirements are labelled FR (functional) and NFR (non-functional), numbered by area. "Shall" = mandatory for Phase 1. "Should" = recommended.

### 1.4 Key decisions (locked)
- **Payments:** Option B — buyer pays seller directly; platform holds no funds. (Option A, a provider-supported architecture, is a Phase-2 upgrade.)
- **Platform:** Flutter, Android + iOS simultaneously.
- **Catalog:** Clothes only. Food excluded until Phase 3.

### 1.5 Gating assessments (must complete before transactional launch)
- **Legal role:** Baltic Systems AB shall obtain and document a Swedish legal assessment of its intermediary role under Konsumentköplag Chapter 1, Section 4 (a business intermediating a private seller's sale may carry trader obligations). Terms, disclosures, complaint handling, and financial responsibility shall reflect that assessment. Direct seller payment is not treated as proof of no sale-related liability. *(Review round 2, critical)*
- **DAC7/tax reporting:** Baltic Systems AB shall document DAC7/POL applicability (Skatteverket platform reporting), including any exclusion relied upon. If applicable, the system supports seller due diligence, transaction records, reporting, correction, and retention. Tax identifiers are collected only after applicability is resolved. *(Review round 2, high)*

## 2. Overall description

### 2.1 Product perspective
A standalone consumer marketplace. No dependency on existing systems except: Swish (payment rail, manual), push notification services, and a moderation AI provider.

### 2.2 User classes
| Class | Description |
|---|---|
| Buyer | Registers free, browses, chats, buys, reviews. No approval needed. |
| Seller | Applies, waits for manual admin approval, lists items, fulfils orders. |
| Admin | Approves sellers, moderates content, mediates disputes. Siva + 1 backup (TBD). |

### 2.3 Operating environment
iOS 16+, Android 10+. Swedish + English UI at launch; content may be in Telugu/Hindi/Bengali/English.

### 2.4 Constraints
- No buyer funds held by the platform (Phase 1).
- ID verification images: minimum-necessary retention (see NFR-PR3).
- All user-facing prices in SEK, inclusive of delivery charges.

## 3. Functional requirements

### 3.1 Seller onboarding & verification
- **FR-S1:** Seller application collects: full name, phone, ID photo, categories sold, short profile text, **and private-individual vs trader status with the basis for classification** (e.g., selling frequency, business registration). Status is validated, not self-asserted without evidence where the distinction matters.
- **FR-S2:** New applications enter `Pending` state. Pending sellers cannot create listings.
- **FR-S3:** Admin approves/rejects via a versioned checklist recording: evidence reviewed, checks performed, decision, reviewer identity, date. Personal acquaintance with the applicant does not substitute for minimum checks.
- **FR-S4:** Approved sellers receive a "Verified" badge displaying scope and date (e.g., "ID verified · Oct 2026"). The badge shall not imply product authentication or transaction guarantees. Badge suspends automatically on: expired checks, material detail changes, or open investigation. A single malicious report shall not alone trigger suspension — investigation opens first.
- **FR-S5:** Rejected applicants receive a reason and may re-apply once with corrections.
- **FR-S6:** Material changes to identity, business status, or **payment recipient** trigger re-verification before further selling. Payment-recipient changes additionally require: re-authentication, buyer-visible notification, and a risk-based hold before new orders may use the new recipient.
- **FR-S7:** Each seller has one **approved payment recipient** (Swish number) bound to the verified identity. **Each order preserves its approved recipient and amount inside the checkout snapshot (FR-L2)** — a later recipient change never silently alters an existing order. The checkout displays this recipient; buyers are instructed to check the recipient shown in their Swish app before approving. Suspected compromise: affected unpaid orders go on hold with explicit buyer instructions, notified only to parties of affected orders. The UI distinguishes three separate facts: buyer reported payment sent / seller acknowledged receipt / platform confirmation (which Phase 1 does not independently provide) — never collapsed into a single "Payment verified" label.

### 3.2 Listings
- **FR-L1:** Listings require: garment category, condition (new/pre-loved), size with measurements, included pieces, disclosed defects, price in SEK, availability, fulfilment options (pickup / post / meetup).
- **FR-L2:** Checkout stores an immutable snapshot of the listing and agreed terms for dispute reference.
- **FR-L3:** Stock: one unit reserved per active order. **Reservation acquisition is atomic** against available inventory — the check and the reservation are one operation; double-allocation is impossible. **Unpaid expiry:** an `order_placed` event with payment dimension still `payment_unreported` after the configured period (default 24h, displayed to the buyer) moves fulfilment to `stock_released`. **Paid-but-unconfirmed:** "unpaid" means no payment reported or otherwise evidenced. Event `buyer_payment_reported` moves the payment dimension to `payment_reported` (bounded 24h for seller acknowledgement) — automatic stock release stops at this point, and the order is never cancelled as unpaid nor its reservation silently released. Payment reported after expiry creates a manual exception. The sale is binding when the seller confirms payment receipt; the §1.5 legal assessment reviews whether software acknowledgement alone determines the legal moment of contract formation. **Payment-resolution outcomes** are recorded explicitly — `payment_established_unpaid` (admin verified no payment), `payment_seller_confirmed`, or `payment_unresolved` (cannot be verified either way; absence of evidence is never treated as evidence of non-payment). Stock release after investigation is a separate atomic operation that preserves the buyer's assertion and complaint route.
- **FR-L4:** Listing and checkout identify the contracting seller: name, private/trader status, contact for complaints/returns, and applicable rights (including trader withdrawal rights where applicable).
- **FR-L5:** Listings may include up to 8 images and up to 2 videos (each video ≤ 60 seconds). Media uploads compress client-side before transfer (NFR-P1); the server validates type/size/content (NFR-S4) and screens media through moderation (FR-R7) before it is buyer-visible. Rejected media is never stored as listing content.

### 3.3 Buyer accounts & discovery
- **FR-B1:** Buyer registration via phone/email + OTP. Free, no approval. The identifier is a phone number **or** an email address (user's choice at sign-in; the app offers both, like SportAdmin). Both channels share identical semantics: 6-digit synthetic code in the slice (logged to the backend console, never sent), 5-minute expiry, max 5 requests per 10 minutes per identifier (NFR-S1, DB-TC-126), each new request invalidates the previous code. Emails are normalized to lowercase; the same identifier always resolves to the same account. Production wiring (real SMS/email delivery) is a pre-launch backlog item — the stub behavior is documented on the sign-in screen.
- **FR-B2:** Search and filter by category, size, price range, condition, location, seller rating.
- **FR-B3:** Seller profiles show: verified badge + scope, listings, ratings, fulfilment history, response time. Profiles shall preserve real differences between sellers (no interchangeable-seller presentation).

### 3.4 Chat
- **FR-C1:** In-app buyer↔seller chat per order. Phone numbers and emails hidden until the order is confirmed.
- **FR-C2:** Contact disclosure after confirmation is purpose-limited (only what's needed for fulfilment).
- **FR-C3:** Chat content is covered by reporting/blocking (see §3.7).

### 3.5 Orders (Option B — direct payment)
- **FR-O1:** Order status is represented in independent dimensions with canonical state identifiers (§12 schema — used identically in requirements, API contracts, persistence, and tests) — **payment** (`payment_unreported` → `payment_reported` → `payment_seller_confirmed` | `payment_established_unpaid` | `payment_unresolved`), **fulfilment** (`stock_reserved` → `dispatched` → `delivery_evidenced` | `delivery_unconfirmed` → `receipt_confirmed`; `stock_reserved` → `stock_released` on unpaid expiry), **cancellation/refund** (`no_cancel` → `cancellation_requested` → `cancelled_unpaid` | `refund_requested` → `refund_reported` → `refund_acknowledged` | `refund_contested`), **dispute** (`dispute_none` → `dispute_open` → `dispute_decided` → `dispute_resolved` | `dispute_closed_unconfirmed` | `dispute_non_compliant`), **return** (`return_none` → `return_requested` → `return_authorised` → `goods_sent_back` → `return_received`). Dimensions coexist: a dispatched order may carry an open dispute; a partial refund does not cancel fulfilment. One flat status field is prohibited. The full transition appendix is §11; identifier categories are defined in §12.
- **FR-O1a — Concurrency rules (validated atomically against the latest order version):**

| Conflict | Rule |
|---|---|
| Cancellation requested + seller marks "dispatched" concurrently | Neither wins automatically. **Cancellation recorded before actual dispatch → cancellation stands** (dispatch assertion rejected; becomes return/refund flow if goods truly left). **Evidenced dispatch before cancellation → fulfilment continues**, cancellation converts to return/refund request. **Conflicting assertions (unverifiable order) → admin review.** Statutory withdrawal vs seller voluntary cancellation policy are handled as separate cases, never one winner rule. |
| Delivery evidence arrives during open non-delivery claim | Claim stays open until evidence reviewed | Evidence does not auto-close claims |
| Buyer acknowledges partial refund while another claim open | Partial refund recorded; other claim continues independently | Dimensions are independent |
| Admin closes case + new evidence arrives | Case reopens | Closure never locks out new evidence |
| Two buyers report payment for the last unit | **Stock reservation is acquired atomically against available inventory; only the valid reservation holder receives current payment instructions.** The seller's acknowledgement order never determines ownership. A late or conflicting payment report creates a payment-resolution exception — it never cancels, transfers, or overrides another order's valid allocation. |
| Payment reported after reservation expiry | Manual exception; stock held for admin review of the actual inventory state. Expiry never implies payment reversal and never invalidates another buyer's valid reservation/allocation. |

Each transition specifies: authorised actor, preconditions, evidence required, stock effect, notifications sent. The canonical appendix (§11) defines every permitted transition.
- **FR-O2:** At checkout the app shows the seller's approved Swish recipient (FR-S7) and the exact amount. Buyer pays via their own Swish app, then taps "I've paid" in-app. **Buyer-reported payment is an assertion, not proof** — a screenshot never establishes receipt.
- **FR-O3:** Seller confirms receipt of funds in-app (by checking their actual Swish account) before dispatch. Dispatch only after seller-confirmed payment.
- **FR-O4:** Completion requires **evidenced delivery** (carrier evidence where available; buyer-confirmed handover for pickup/meetup) or buyer receipt confirmation. Seller-marked dispatch alone never establishes delivery or completion. Orders with neither evidence nor confirmation remain `delivery_unconfirmed` — never auto-labelled "successful." Timer-based administrative closure shall not generate success trust signals, remove complaint access, or imply buyer acceptance.
- **FR-O5:** Cancellation distinguishes paid from unpaid. Cancelling an **unpaid** order simply releases the reservation. Cancelling a **paid** order opens a refund-resolution workflow (`refund_requested` → seller action → `refund_reported` → `refund_acknowledged`, or `refund_contested`): seller response deadline 3 business days, partial refunds supported with evidence, escalation to dispute on contest. **Refund actions are records, not a single status:** each action stores amount in SEK, related agreement/claim, seller report, buyer acknowledgement, and evidence status. Order-level refund summaries are derived from the actions and always distinguish partial from full reimbursement — a single `refund_acknowledged` never implies full reimbursement on its own. The UI never implies money has been returned until the buyer acknowledges it. No refund is labelled bank-verified without an authoritative feed. These are records of reported/evidenced direct payments — not a platform-held-funds ledger. **Acceptance tests:** one agreed partial refund (summary shows partial, claim balance remains); two separate refunds on one order (both recorded, totals derived); buyer acknowledges one refund while contesting another; duplicate seller reports of the same refund (deduplicated, not double-counted); dispute remains open after partial reimbursement.
- **FR-O6:** The app shall state plainly at checkout: "You pay the seller directly. Desi Bazaar does not hold your payment." No "escrow" or "protected payment" claims in Phase 1.

### 3.6 Disputes (mediation — no held funds)
- **FR-D1:** Dispute reasons: **not received** (available once the agreed delivery deadline is missed — including when no delivery event exists), **not as described**, **defective**, and **trader withdrawal** (separate workflow, see FR-D6). Defects discovered later keep the statutory complaint route regardless of platform windows.
- **FR-D2:** Dispute flow collects structured evidence from both sides (photos, chat history, listing snapshot).
- **FR-D3:** Admin mediates and records **separately**: proposed outcome, party agreement, seller action taken, buyer acknowledgement, and unresolved non-compliance. A "refund" decision is a recommendation the seller executes directly — the platform cannot move the money in Phase 1. **Resolution evidence taxonomy** (exactly one applies at closure): `remedy_acknowledged` (buyer confirms receipt of agreed remedy), `remedy_independently_evidenced` (independent evidence identifying **source, transaction/delivery reference, recipient, amount where applicable, and completed status** — a carrier return scan proves return movement, not refund receipt; a platform note or seller-supplied screenshot alone never qualifies as independent refund evidence), `closed_unconfirmed` (investigation closed, remedy receipt not confirmed — uncertainty retained in the record), `unresolved_non_compliant` (seller did not cooperate). A seller assertion or screenshot alone never establishes refund receipt. Only `remedy_acknowledged` and `remedy_independently_evidenced` count as successful buyer recovery in metrics. Unjustified non-cooperation carries proportionate restrictions (human-reviewed): e.g., listing suspension until the case closes. Platform wording is explicit that sanctions cannot guarantee recovery of money; the buyer is told about external remedies.
- **FR-D4:** The platform's mediation does not limit statutory rights. Seller onboarding records private-individual vs trader status (FR-S1); listing and checkout surface it (FR-L4). **Platform deadlines never limit statutory rights** — Swedish consumers buying from traders have a 14-day withdrawal right and a 3-year complaint period; the platform's internal windows sit *inside* those, not instead of them. Pending the §1.5 legal assessment, terms and disclosures are drafted conservatively (assume obligations may apply).
- **FR-D5:** Dispute SLAs: acknowledgement within 1 business day; decision or scheduled update within 5 business days. Appeals go to a different administrator where feasible; new evidence reopens the case.
- **FR-D6:** Trader withdrawal follows the **returns-policy annex** (Annex A): notification period 14 days from delivery; goods returned within 14 days after notification; return address = an approved address (not automatically the seller's registered address); **reimbursement without undue delay and within 14 days after receipt of the withdrawal notice** — where legally permitted, reimbursement may be withheld until the goods are received or the buyer provides evidence of sending them back; ending the withholding period does not create a new 14-day period. Refund = full purchase price + standard delivery cost (extra costs from a buyer-chosen premium method are not reimbursed); buyer pays return postage only where the required prior information was given (otherwise seller bears it); deductions only for diminished value from handling beyond inspection; withdrawal exceptions per the **Distance Contracts Act** (not Konsumentköplag) — sealed health/hygiene goods only where the statutory conditions are met, not as a blanket category. Private-sale voluntary returns are a separate, seller-defined policy — never mixed with statutory withdrawal.
- **FR-D6a (withdrawal interface):** For sales with applicable statutory withdrawal rights, the app provides a clearly labelled, easily accessible withdrawal function throughout the withdrawal period. The buyer identifies the contract, confirms the withdrawal explicitly, and receives a prompt durable acknowledgement recording receipt time. **The withdrawal is effective on valid notice — it is not conditional on seller authorisation, and return shipment is not conditional on seller-provided instructions** (standard instructions apply). Delivery responsibility sits with the contracting seller; evidence of that delivery is retained. An in-app dispute status alone does not satisfy the acknowledgement requirement. Exact statutory wording is reviewed within the §1.5 legal gate — not replaced with another approximate summary here.

### 3.7 Reviews & moderation
- **FR-R1:** One review per order. Eligibility: after **evidenced fulfilment**, or after a **qualifying failed transaction** — an order with substantiated buyer participation (payment reported + seller acknowledgement, or admin-confirmed interaction) where fulfilment verifiably failed or a dispute ended with resolution outcome `closed_unconfirmed` or `unresolved_non_compliant` (outcome identifiers, §12). A buyer's unsubstantiated payment assertion alone never establishes eligibility. Contested eligibility goes to human review. "Completed order" alone is not the gate — genuine failed transactions are reviewable.
- **FR-R2:** Genuine negative reviews that comply with content rules shall be published. Ratings are computed from published reviews only.
- **FR-R3:** AI pre-screens reviews for: profanity, hate speech, personal data (phone/address), suspected fake-review patterns. Clean reviews publish immediately; flagged reviews enter the human queue.
- **FR-R4:** Users can report listings, images, reviews, messages, and accounts from the relevant screen, and block unwanted contact. Reports enter an auditable queue (severity, owner, response target, action, appeal) with defined response targets, including an urgent-safety target. Published support contact details.
- **FR-R5:** Blocking stops unwanted contact without deleting order records or blocking dispute access.
- **FR-R6:** AI moderation assists only: human review required before account sanctions; ID images and payment credentials never submitted to general-purpose moderation models; moderation tested in supported languages including transliterated text.
- **FR-R7:** Proactive screening covers listings, images, profiles, reviews, and chat — controls appropriate to each type (image screening for visual content, not text blocklists alone). Users accept community rules before contributing content. DSA hosting-service obligations (e.g., illegal-content reporting) assessed separately from app-store policy.

### 3.8 Notifications
- **FR-N1:** Push permission optional. Order events, dispute updates, and seller-application status are always visible in an in-app inbox.
- **FR-N2:** State-changing actions (payment confirmation, receipt confirmation, dispute filing) require server acknowledgement before the UI shows success.

### 3.9 Admin console
- **FR-A1:** Queues: seller applications, flagged reviews, open disputes, reported content — each with owner, SLA timer, and audit trail.
- **FR-A2:** Role-limited admin access with **MFA enforced**; all admin actions logged with identity and timestamp; sensitive audit logs access-controlled.
- **FR-A3:** Backup admin configured before launch. **For Phase 1, either authorised administrator may pause new orders and onboarding** (existing orders, disputes, and support continue). Queue-age and SLA alerts notify both admins. Automated capacity-based pausing is explicitly out of scope. Resumption requires the resuming admin to verify queues are staffed; pause does not block payment instructions already issued to buyers with valid unpaid reservations, but no new payment instructions are shown while paused.

### 3.10 Account deletion
- **FR-DEL1:** In-app deletion initiation (Settings) plus a public web page.
- **FR-DEL2:** Flow explains what is deleted vs. retained (narrowly defined records only, e.g., dispute evidence per retention schedule), with reasons and durations.
- **FR-DEL3:** Deletion is a completed operation, not a request screen: active sessions revoked; public profile and listings removed or anonymised per the retention schedule; deletion propagated to processors; requester told what was completed and any exceptions. Backup restores use deletion tombstones so deleted accounts are not resurrected.
- **FR-DEL4:** Acceptance tests: deletion during an open order, deletion after a dispute, processor deletion failure, backup restoration after deletion.

### 3.11 Advertisements (SC-1)
- **FR-AD1:** Sellers may buy promoted listings: 1, 3, or 7 days at admin-configured prices (default 29/69/129 SEK). Promotion payment goes to the platform (Baltic Systems AB, Swish Företag in production) — separate from marketplace buyer→seller payments.
- **FR-AD2:** A promotion goes live only after admin approval (checklist + reason recorded; FR-A2 audit). Unapproved promotions are never shown as promoted.
- **FR-AD3:** Active promotions rank first in browse/search and carry a clear "Sponsored" label. Non-promoted listings are never labelled Sponsored.
- **FR-AD4:** Sponsored feed slots serve active promotions (round-robin) or render empty when there is no inventory — never filler content.
- **FR-AD5:** Promotions expire automatically after the purchased days; expired promotions lose ranking and label without manual action.
- **FR-AD6:** Third-party ad networks (e.g., AdMob) are explicitly out of Phase 1 — they require GDPR consent work and a brand review first.

## 4. Non-functional requirements

### 4.1 Performance
- **NFR-P1:** Listing feed loads in < 2s on 4G. Image and video uploads compress client-side before transfer.

### 4.2 Security
- **NFR-S1:** OTP-gated registration with rate limits and abuse monitoring; session tokens with expiry; payout-recipient changes require re-authentication + notification + risk hold (FR-S6).
- **NFR-S2:** ID images: private storage, encrypted in transit and at rest, authorised verification staff only, least-privilege time-limited access where appropriate, excluded from analytics/logs/AI prompts. Audit-log access controlled.
- **NFR-S3:** Server-side role and object-level authorisation on every sensitive operation: a user shall not reach another user's orders, addresses, chats, or ID documents by altering identifiers. Negative tests required: cross-account access, expired/revoked sessions, unauthorised admin actions, payment-recipient changes.
- **NFR-S4:** Account recovery flows rate-limited and abuse-monitored; recovery shall not bypass payment-recipient change protections. Malicious upload handling (type/size/content validation) for ID photos and listing images and videos.

### 4.3 Privacy & compliance
- **NFR-PR1:** GDPR: controller named (Baltic Systems AB) with privacy contact; lawful basis documented per purpose; consent only for optional processing (no pre-ticked boxes).
- **NFR-PR2:** Data minimisation: every collected field justified; collection notices before consequential collection (ID, address).
- **NFR-PR3:** Retention schedule with actual periods or defensible criteria for: verification docs, abandoned applications, addresses, chats, dispute evidence, security/fraud records, financial records, backups/deletion logs. Push-token retention defined. Analytics/crash-reporting fields enumerated with redaction rules.
- **NFR-PR4:** User rights (access, correction, erasure, **restriction, objection**, portability) with proportionate identity checks; response within one month.
- **NFR-PR5:** Breach procedure tested before launch: designated owner + backup. Breaches documented and assessed without undue delay; **where notification is required, IMY is notified without undue delay and where feasible within 72 hours of awareness** — incomplete information does not delay a required notification. Affected-person notification decision, processor escalation, and evidence preservation included.
- **NFR-PR6:** DPIA/DPO need assessed and documented; age policy defined before launch.
- **NFR-PR7:** Processing register maintained; approved vendor inventory (hosting, OTP, push, analytics, AI moderation, verification) with required processor agreements; subprocessors assessed; non-EEA transfers identified with safeguards. AI provider retention/training-use contractually controlled. Hosting and support-access locations documented. Seller access to buyer addresses/contact details minimised and logged.

### 4.4 Reliability
- **NFR-R1:** Order, payment-confirmation, and dispute actions are idempotent; retries safe.
- **NFR-R2:** Backups must not resurrect deleted accounts (deletion tombstones survive restore).

### 4.5 Store compliance
- **NFR-ST1:** Reviewer accounts (buyer + seller), demonstrable moderation flows, working support/privacy/deletion pages, accurate privacy declarations (Apple) and Data safety (Google).
- **NFR-ST2:** Review notes state: physical goods, platform's own payments (Swish) — not Apple IAP / Google Play Billing.

### 4.6 Brand
- **NFR-BR1:** Trust and service quality outrank seller-count and transaction-volume in every growth decision.
- **NFR-BR2:** Total price including delivery visible before payment. Free-traction period has a defined end date; future fees communicated ≥30 days in advance.
- **NFR-BR3:** Trust metrics are honestly defined: fulfilment history distinguishes **evidenced fulfilment** from administrative closure and unresolved transactions; response time discloses its measurement basis (acknowledgement vs resolution); silent auto-completion never inflates success figures. Measured alongside growth: approval consistency, unresolved-claim rate, report response time, repeat participation.

## 5. Phase-2 upgrade notes (not in MVP scope)

- **Payments (Option A):** a future provider-supported marketplace payment architecture (Stripe Connect candidate). **Not escrow by default:** custody, liability, refunds, dispute handling, and buyer-protection terms remain subject to provider approval, contract, and the §1.5 legal assessment. The FR-P0 gating requirement (documented payment-services classification) applies before any buyer money is held.
- **Fraud acceptance tests (Phase-1 launch gates, not deferred):** fake payment assertions/screenshots (seller checks actual funds; assertion never establishes receipt); false dispatch + silent completion (dispatch ≠ delivery; timer closure ≠ success); empty-box/wrong-item (listing snapshot + shipment evidence + unresolved-claim tracking); seller refund refusal (non-compliance state, deadlines, sanctions, external escalation info); Swish-recipient takeover (approved recipient + strong auth + change alerts + reverification); colluding fake reviews (dual-party acknowledgements, rate limits, linked-account checks, human review). Detection and recovery limits specified alongside prevention.
- **Trust upgrade:** at 30 approved sellers prepare; at 50 (or SLA breach) require: second trained reviewer, calibrated checklists, risk-based verification, audit sampling. Backup coverage (Phase 1, FR-A3) and active second-review capacity (Phase 2) are defined separately. Badge-expiry criteria and investigation triggers defined; a single malicious report never auto-removes a badge.

## 6. Glossary
- **Option B:** Launch payment model — buyer pays seller directly; platform holds no funds.
- **Option A:** A future provider-supported marketplace payment architecture; custody, liability, and protection terms remain subject to provider approval, contract, and the §1.5 legal assessment. Not escrow by default.
- **Verified badge:** Identity/business check completed; scope- and date-labelled; not a product guarantee.
- **Mediation:** The platform's dispute-resolution assistance; contractual role and legal responsibilities are governed by the completed §1.5 legal assessment and approved terms — not by this glossary.

## 7. Release annex (operational values — required before launch)
- **Moderation:** urgent-safety reports triaged within 24h; standard reports within 3 business days; published support contact in-app and on the website.
- **Admin coverage:** primary + backup admin named; both MFA-enrolled. If the primary is unavailable >48h, backup assumes the queues. Pause trigger: administrator-controlled (FR-A3) — either admin can pause new orders/onboarding from the console, with alerts to the other; automatic capacity detection is explicitly out of scope for Phase 1.
- **Verification:** badge validity 12 months, then re-verification; investigation opens on: two independent reports, a payment-recipient change flag, or admin suspicion — a single report alone never auto-suspends.
- **Ages:** Desi Bazaar permits accounts and transactions only for users aged 18 or over — **a platform policy, not a Swish guarantee** (each bank sets its own Swish age conditions; OTP registration does not prove age). Registration collects an age declaration; suspected underage accounts follow a defined review-and-restriction process. If the §1.5 assessment requires stronger age assurance, it is specified explicitly — ID collection is never silently expanded to compensate for the assumption.

## 8. Release-evidence checklist (gates — each carries owner, approval date, version, evidence reference; a dated document alone is not a passed gate)
| Gate | Evidence required | Required before |
|---|---|---|
| Privacy readiness | Notices, lawful-basis map, retention schedule, vendor approvals, necessary agreements | Corresponding production personal-data processing (any stage that handles buyer/seller data — not only public seller onboarding) |
| Operational readiness | Named primary/backup admins, access checks, queue-coverage drill, pause/resume test, published support contact | Public pilot |
| Transaction readiness | §1.5 legal/DAC7 conclusions implemented in terms/workflows; order/refund/fraud/security acceptance tests passed, **including executable §11 transition tests** | Live transactions |
| Distribution readiness | Applicable store approval + production configuration checks | Store-distributed public release |
| Held-funds readiness | Provider approval, contractual/legal sign-off, payment-control tests | Live held-funds transactions (Phase 2; non-production prototyping is not gated) |

## 9. Open items for reviewer
1. Does the withdrawal-without-authorisation split (§11 return table + FR-D6a) hold up — is "standard return instructions" sufficient when the seller provides none?
2. Is the allocation-loss path (`payment_unresolved` → `refund_requested`) fair to the buyer who paid in good faith?
3. Any remaining identifier, transition, or invariant gap before the schema dictionary (§12) is frozen?
4. Is the implementation priority (§13) ordered right, or would you sequence it differently?

## 10. Traceability
Each review finding maps to requirements above: R2-1→§1.5/§3.6; R2-2→§3.5 FR-O1/O4; R2-3→§3.5 FR-O5; R2-4→§3.6 FR-D3; R2-5→§3.1 FR-S6/S7; R2-6→§5 fraud gates; R2-7→§3.1 FR-S1, §3.2 FR-L4, §3.6 FR-D6; R2-8→§1.5; R2-9→§4.3 NFR-PR7; R2-10→§4.3 NFR-PR5; R2-11→§3.10; R2-12→§3.7 FR-R4/R7; R2-13→§4.2; R2-14→this spec governs (v2 superseded as rationale); R2-15→§3.2 FR-L3; R2-16→§3.1 Phase-2 trigger, §3.9 FR-A3; R2-17→§4.6 NFR-BR3. Round-3 (Claude): C1→§3.2 FR-L3; C2→§3.2 FR-L3; C3→§3.5 FR-O1/O1a; C4→§3.6 FR-D3; C5→§3.6 FR-D6 + §7 annex values; C6→§3.1 FR-S7 + §3.2 FR-L2; C7→§3.7 FR-R1; C8→§7 release annex; C9→§6 glossary. Round-4 (GPT, v1.2): G1→§3.6 FR-D6; G2→§3.6 FR-D6a; G3→§3.5 FR-O1a; G4→§3.5 FR-O1a; G5→§3.6 FR-D3; G6→§3.9 FR-A3 + §7; G7→§8; G8→§7; G9→§11. Round-5 (Claude, v1.3): K1→§11 payment outcomes + §3.2 FR-L3; K2→§11 refund/dispute rows + invariant 8; K3→§11 return dimension + §3.5 FR-O1; K4→§3.5 FR-O5 refund-action records + tests; K5→§11 lifecycle entry/inventory rules + §3.2 FR-L3; K6→§12 schema dictionary + §3.7 FR-R1. Round-6 (freeze assessment): F1→§11 return table + §3.6 FR-D6a (statutory withdrawal not gated on seller authorisation); F2→§11 payment rows + invariant 9 (late confirmation never restores released stock).

## 11. Canonical transition appendix

Identifier categories are defined in §12. Format: **From → To** · actor · guard · evidence · stock effect · notification.

**Order creation (initial values):** event `order_placed` atomically checks available inventory and acquires the reservation. Initial dimensions: payment `payment_unreported`, fulfilment `stock_reserved`, cancellation/refund `no_cancel`, dispute `dispute_none`, return `return_none`.

**Payment dimension**

| From → To | Actor | Guard | Evidence | Stock | Notify |
|---|---|---|---|---|---|
| `payment_unreported` → `payment_reported` | Buyer | Reservation valid (`stock_reserved`, not expired) | "I've paid" tap (event `buyer_payment_reported`) | none | seller |
| `payment_unreported` → `payment_unresolved` | Buyer | Payment reported at/after reservation expiry | payment report | held for admin review | admin + seller |
| `payment_reported` → `payment_seller_confirmed` | Seller | Seller verified actual Swish receipt | seller confirmation | none | buyer |
| `payment_reported` → `payment_unresolved` | System | 24h without seller acknowledgement | expiry | held for admin review | admin + parties |
| `payment_unresolved` → `payment_seller_confirmed` | Seller/Admin | funds verified **and unit still allocated to this order** | evidence record | release to dispatch flow | parties |
| `payment_unresolved` → `refund_requested` | System | seller confirmed payment but stock was released/reallocated during investigation — payment acknowledgement never restores allocation (invariant 9) | evidence record | none | parties (buyer: refund path for the direct payment; seller: return it) |
| `payment_unresolved` → `payment_established_unpaid` | Admin | non-payment positively established (e.g., buyer withdraws the claim) | admin record | atomic operation: fulfilment → `stock_released`; buyer's assertion and complaint route preserved in record | parties |

Uncertainty is preserved: absence of payment evidence is never classified as non-payment. Stock release after investigation is a separate atomic operation (see inventory rules below) that keeps the buyer's assertion and complaint route in the record.

**Fulfilment dimension**

| From → To | Actor | Guard | Evidence | Stock | Notify |
|---|---|---|---|---|---|
| `stock_reserved` → `stock_released` | System | unpaid expiry (default 24h), payment still `payment_unreported` | expiry | unit available again | buyer |
| `stock_reserved` → `dispatched` | Seller | `payment_seller_confirmed`; no recorded cancellation | dispatch confirmation | committed (no second allocation) | buyer |
| `dispatched` → `receipt_confirmed` | Buyer | buyer confirms receipt (no timer wait required) | confirmation | none | seller |
| `dispatched` → `delivery_evidenced` | System/Seller | carrier evidence or handover confirm | evidence record | none | parties |
| `dispatched` → `delivery_unconfirmed` | System | `delivery_evidence_window` lapsed (default 7 days, configurable), no evidence | expiry | none | parties |
| `delivery_evidenced`/`delivery_unconfirmed` → `receipt_confirmed` | Buyer | buyer confirms receipt | confirmation | none | seller |

**Cancellation/refund dimension**

| From → To | Actor | Guard | Evidence | Stock | Notify |
|---|---|---|---|---|---|
| `no_cancel` → `cancellation_requested` | Buyer | before dispatch recorded | request | none | seller |
| `cancellation_requested` → `cancelled_unpaid` | System | payment dim = `payment_unreported` | auto | reservation released | parties |
| `cancellation_requested` → `refund_requested` | System | payment reported/confirmed | auto | none | seller (3-business-day deadline) |
| `refund_requested` → `refund_reported` | Seller | seller executed refund | seller report (refund-action record) | none | buyer |
| `refund_reported` → `refund_acknowledged` | **Buyer only** | buyer confirms receipt | acknowledgement | none | parties |
| `refund_reported` → `refund_contested` | Buyer | buyer disputes the refund | contest + evidence | none | admin |
| `refund_contested` → `refund_acknowledged` | **Buyer only** | buyer accepts after dispute | acknowledgement | none | parties |
| `refund_contested` → `dispute_open` | Admin | contest needs mediation | dispute case | none | parties |

An administrator never creates a buyer acknowledgement. Independently evidenced refunds are recorded via the dispute dimension's remedy outcome, not by setting `refund_acknowledged`.

**Return dimension** (linked record per order; post-dispatch path)

Statutory withdrawal is recorded upon a valid notice and is **not conditional on seller authorisation**. Return instructions and receipt acknowledgement are operational events, not permission gates. Authorisation applies only to voluntary returns.

| From → To | Actor | Guard | Evidence | Stock | Notify |
|---|---|---|---|---|---|
| `return_none` → `return_requested` | Buyer | after dispatch; reason preserved (withdrawal / defective / voluntary / cancel-converted) with legal/policy basis, request time, deadlines | request | none | seller |
| `return_requested` → `return_authorised` | Seller/Admin | **reason = voluntary return only** | authorisation + return address/instructions | none | buyer |
| `return_requested` → `goods_sent_back` | Buyer | **reason = statutory withdrawal or defective** — seller authorisation NOT required; buyer ships per standard return instructions | tracking/photo evidence | none | seller |
| `return_authorised` → `goods_sent_back` | Buyer | reason = voluntary return | tracking/photo evidence | none | seller |
| `goods_sent_back` → `return_received` | Seller | seller confirms possession | confirmation | unit quarantined — relisted only after seller confirms possession **and** listing condition remains accurate | parties |
| `goods_sent_back` → `refund_requested` | Buyer/System | qualifying return-shipping evidence supplied — ends the buyer's return obligation; seller may withhold refund only until receipt or this evidence, per FR-D6 (14-day clock runs from withdrawal notice) | return-shipping evidence | — | seller |
| `return_received` → `refund_requested` | System | return complete | auto | — | seller (refund deadline per FR-D6) |

**Dispute dimension**

| From → To | Actor | Guard | Evidence | Stock | Notify |
|---|---|---|---|---|---|
| `dispute_none` → `dispute_open` | Buyer | eligible reason (FR-D1) incl. missed delivery deadline | structured evidence | none | seller + admin |
| `dispute_open` → `dispute_decided` | Admin | mediation complete | reasoned decision + rationale | none | parties |
| `dispute_decided` → `dispute_resolved` | System | validated remedy outcome per FR-D3 taxonomy = `remedy_acknowledged` or `remedy_independently_evidenced` (status follows evidence; selecting the status never creates it) | remedy-outcome record | none | parties |
| `dispute_decided` → `dispute_closed_unconfirmed` | Admin | investigation closed, receipt unconfirmed | admin record | none | parties |
| `dispute_decided` → `dispute_non_compliant` | Admin | seller non-cooperation | admin record | listing suspension applies | parties |
| any → `dispute_open` (reopen) | System | new evidence after closure | new evidence | none | admin |

**Inventory disposition rules**
- Unpaid expiry → `stock_released`, unit available.
- Cancellation before dispatch, unpaid → `stock_released`.
- Payment unresolved after investigation → admin may release stock only via explicit atomic operation; buyer's assertion and complaint route persist.
- Returned goods → quarantined; relisting requires seller possession confirmation + condition accuracy check.
- A refund alone never relists an item.

**Global invariants**
1. No dispatch before `payment_seller_confirmed`.
2. No second allocation of the same stock unit (reservation acquisition is atomic).
3. A claim never disappears when fulfilment advances.
4. A partial refund never erases the remaining claim or balance.
5. Seller acknowledgements never independently establish buyer receipt.
6. Administrative closure never generates successful-fulfilment or successful-recovery metrics.
7. Expiry of any timer never implies payment reversal or buyer acceptance.
8. `refund_acknowledged` is set only by the buyer.
9. Payment acknowledgement never creates or restores inventory allocation. Dispatch requires both seller-confirmed payment AND a valid allocation to that order.

## 12. Schema dictionary
Three identifier categories. Different names are fine when they represent different things; ambiguous names presented as interchangeable are not.

| Category | Definition | Examples |
|---|---|---|
| **State identifier** | A value of one order dimension (§11). Used in requirements, API contracts, persistence, tests. | `payment_reported`, `stock_reserved`, `dispute_closed_unconfirmed` |
| **Event identifier** | Something that happened; triggers a transition. | `order_placed`, `buyer_payment_reported`, `seller_dispatched` |
| **Resolution-outcome identifier** | The recorded outcome of a mediation/refund case (FR-D3 taxonomy). Not a state. | `remedy_acknowledged`, `remedy_independently_evidenced`, `closed_unconfirmed`, `unresolved_non_compliant` |

Prose uses `awaiting_seller_verification` only as shorthand for "payment dimension in `payment_reported` awaiting seller confirmation" — never as a state or API value. Dispute states carry the `dispute_` prefix; bare outcome codes (`closed_unconfirmed`) refer to the FR-D3 taxonomy. Before generating API contracts, database enums, or test fixtures, this dictionary is frozen and any new identifier is added here first.

## 13. Implementation priority (proposed — Siva decides)

Build in vertical slices, not layer by layer. Each slice is demoable on test data.

**Slice 1 — core loop (first):** schema freeze (§11 + §12) → auth/OTP → seller onboarding + admin approval queue → listings + discovery → reservation → payment reporting/acknowledgement → fulfilment → reviews. One end-to-end journey on test data: approval → listing → reservation → payment acks → fulfilment → review.

**Slice 2 — money edge cases:** cancellation (paid/unpaid), paid-but-unconfirmed, returns (all reasons), partial-refund records, dispute mediation. Executable §11 transition tests against this slice.

**Slice 3 — trust & safety:** chat, moderation/reporting/blocking, admin console + MFA, security hardening (object auth, rate limits, negative tests).

**Slice 4 — compliance:** privacy implementation (notices, lawful-basis map, retention), account deletion (§3.10 incl. processor propagation), vendor/processor agreements.

**Slice 5 — launch gates (last):** §1.5 legal/DAC7 conclusions incorporated → release-evidence checklist (§8) → store submission.

**Explicitly last / out of Phase 1:** Option A held-funds architecture, trust upgrade at 50 sellers, food listings, web app, multi-seller carts.

**Parallel track (not blocking slices 1–3):** legal assessment, DAC7 analysis, privacy/vendor paperwork — collected as gate evidence for slice 5.

## 14. Implementation clarifications (frozen with v1.5)

**IC-1 — Atomic cross-dimension updates.** Any transition whose effects touch more than one dimension executes as a single atomic transaction. Partial application is a defect. This covers: order creation (all five dimensions initialised together); `payment_unresolved → payment_established_unpaid` with fulfilment → `stock_released`; `refund_contested → dispute_open` (refund dimension + dispute case creation); `return_received → refund_requested` (return + cancellation/refund dimensions); reservation acquisition (inventory check + reservation as one operation). Concurrency control: compare against the latest order version; conflicting concurrent transitions are serialised, never silently merged.

**IC-2 — Explicit legal/policy classification of converted returns.** Every return record carries its classification set at creation (see IC-2a). Cancel-converted returns (pre-dispatch cancellation where goods truly left) are classified explicitly by the admin/seller at conversion time with the reason recorded — never defaulted. The basis determines the applicable path: statutory/defective bypass seller authorisation (§11); voluntary requires it. The original request, its basis, and the request timestamp are immutable once set; corrections to a misclassified basis are separate audited events (IC-2a).

**IC-2a — Return origin and basis are separate fields (adopted 2026-10-08, Siva's decision).** `return_class` is replaced by two fields: `return_origin` (`buyer_initiated` | `cancellation_converted`) records where the return came from; `return_basis` (`statutory_withdrawal` | `defective_goods` | `voluntary_policy`) records the legal/policy basis that determines permission, postage, and deadlines. A converted cancellation must acquire an explicit `return_basis` at conversion time. Corrections to a misclassified basis are allowed as audited events (who, when, old → new, reason); silent rewrites are not.

**IC-4 — Media upload uses signed URLs (adopted 2026-10-09, Siva's decision).** Clients request an upload URL per file (purpose, content type, size declared); bytes go direct to object storage; the server validates type/size/content on completion (checksum + magic-byte sniffing) and queues moderation screening before buyer visibility. ID documents follow the same flow with NFR-S2 protections.

**IC-3 — Security/privacy prerequisites apply from the first relevant slice.** The compliance work is not deferred to slice 4: any slice that handles personal data inherits its prerequisites. Concretely: synthetic data only until privacy notices are published — no real PII in any environment before the §8 privacy gate; ID images encrypted at rest and excluded from logs from the first slice that stores them; processor agreements signed before any vendor touches production data; admin MFA enforced before the admin console is exposed; audit logging of admin actions from slice 1. Each slice's definition of done includes its applicable security/privacy prerequisites.
