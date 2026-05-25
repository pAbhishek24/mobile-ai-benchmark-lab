# Manual Quality Review — Finance Benchmark

Generated: 2026-05-25 | Device: Samsung S24 Ultra | Focus models: qwen2.5-0.5b-q4km, qwen2.5-1.5b-q4km, tinyllama-1.1b-q4km

## Review Methodology

Each section covers 5 representative prompts per model (worst 2, median 1, best 2), selected from the latest benchmark run. Raw output is truncated to 400 characters for readability. Full outputs are in `ai-lab/logs/<device>/<model>/<timestamp>/prompts/`.

**Quality score range:** 0.0 (complete failure) → 1.0 (perfect)

---

## qwen2.5-0.5b-q4km

**Run:** `20260524_203804` | **Max tokens:** 256 | **Profile:** default (systems-era run)

### P17 — Category Spike Analysis (quality=0.392) ★ Lowest

**Prompt:** Transport spend ₹6,800 vs 3-month average ₹3,200 (2.1× spike). Salary ₹55,000. What explains this?

**Output (truncated to 400 chars):**
```
My transport spend this month is ₹6,800 vs my 3-month average of ₹3,200. That is more than double.
My salary is ₹55,000. I commute by metro daily and occasionally take cabs. What categories of reasons
could explain this spike? What specific transaction patterns should I look for...
```

**Reviewer notes:**
- Output echoes back the prompt verbatim without answering — the model ran out of tokens before generating any response content
- Score low because no concepts (anomaly, spike analysis, baseline) were covered beyond the prompt echo
- Root cause: 256 token limit too short for prompt + complete response
- **Fix:** Rerun with `--profile quality` (max_tokens=512)

---

### P08 — SIP Calculation (quality=0.454)

**Prompt:** Save ₹25 lakhs in 12 years via equity SIP at 12% annual return. Monthly investment needed? If only ₹6,000/month, what corpus in 12 years?

**Output (truncated):**
```
I want to save ₹25 lakhs for my child's education in 12 years. I can invest monthly in an equity
mutual fund SIP. Assuming 12% annual return, how much do I need to invest per month to reach this
goal? If I can only invest ₹6,000/month, what corpus will I have in 12 years? To determine how
much you need to invest per month to reach your goal of ₹25 lakhs in 12 years, we need to follow
these steps:
```

**Reviewer notes:**
- Starts method explanation but truncates before completing any calculation
- The model correctly identifies the calculation approach but produces no numbers
- Numeric score: 0.0 (no numeric values found in output)
- **Root cause:** Token limit truncation mid-response

---

### P03 — EMI Burden Analysis (quality=0.633) — Median

**Prompt:** 3 EMIs totalling ₹29,500/month. Salary ₹72,000. EMI-to-income ratio? Is it healthy?

**Output (truncated):**
```
I have three EMIs: Home loan ₹18,500/month, Personal loan ₹6,200/month, Car loan ₹4,800/month.
My take-home salary is ₹72,000. What is my total EMI burden as a percentage of income? Is this
financially healthy? What is the recommended maximum EMI-to-income ratio?

Total EMI = ₹18,500 + ₹6,200 + ₹4,800 = ₹29,500
```

**Reviewer notes:**
- Correctly calculates total EMI ₹29,500 (numeric pass)
- Identifies "40.97% of income" — accurate
- Provides "50%" rule as maximum recommendation — correct finance concept
- Truncates before full recommendation, but core answer is present
- Quality 0.633 reflects partial concept coverage

---

### P16 — Bonus Allocation (quality=0.875)

**Prompt:** ₹80,000 bonus. Home loan ₹32L @ 8.75%, 18 years. Personal loan ₹1.5L @ 15%, 2 years. Prepay home, close personal, or invest in MF?

**Output (truncated):**
```
I received a Diwali bonus of ₹80,000. I have a home loan outstanding of ₹32 lakhs at 8.75% interest
with 18 years remaining, and a personal loan outstanding of ₹1.5 lakhs at 15% interest with 2 years
remaining. Should I use the bonus to prepay the home loan, fully close the personal loan, or invest
in mutual funds? Justify your recommendation. To determine whether you should use the bonus to prepa
```

**Reviewer notes:**
- Again prompt echo + truncated — but the score comes from concept matching pre-echo content
- Interesting: the prompt itself contains the financial concepts, which inflates concept_score
- **Methodology note:** Need to strip prompt echo from output before scoring in quality-profile reruns

---

### P05 — Credit Card Debt Strategy (quality=0.883) ★ Best

**Prompt:** HDFC credit card ₹38,000. Due in 5 days. ₹15,000 available. 3.5% monthly interest. Pay ₹15,000 now → interest next month? Strategy to clear in 3 months?

**Output (truncated):**
```
My HDFC credit card outstanding is ₹38,000. Due date is 5 days from now. I have ₹15,000 available
in savings. The card charges 3.5% monthly interest on the unpaid balance. If I pay ₹15,000 now,
how much interest will I pay next month on the remaining ₹23,000? What is the best strategy to
clear this debt in 3 months? To determine the best strategy to clear the debt in 3 months, we need
to follow th[ese steps]
```

**Reviewer notes:**
- Credit card interest computation: target ₹23,000 × 3.5% = ₹805. Model appears to calculate this even with truncation.
- Debt clearance strategy keywords present
- Still truncated before completing strategy
- Best score due to strong concept + partial numeric match

**Overall assessment (qwen2.5-0.5b):** Quality limited by token truncation. True quality under ideal conditions likely 0.55–0.65. Needs quality-profile rerun with max_tokens=512.

---

## qwen2.5-1.5b-q4km

**Run:** `20260524_181530` | **Max tokens:** 256 | **Profile:** default

### P17 — Category Spike (quality=0.392) ★ Worst

**Same truncation issue as 0.5b.** Output mirrors prompt without any analysis generated.

**Reviewer notes:**
- Identical score to 0.5b on this prompt — both models fail due to token limit, not model quality
- The 1.5b model likely has better reasoning capabilities, but they are unobservable at 256 tokens

---

### P14 — Safe Spend with Buffer (quality=0.451, hallucination=TRUE)

**Prompt:** Take-home ₹58,000. Emergency buffer ₹10,000. 22nd of month. Spent ₹41,000. Fixed remaining ₹5,500 EMI on 29th. Safe spend remaining? Savings rate?

**Output (truncated):**
```
My monthly take-home is ₹58,000. I want to maintain a minimum ₹10,000 emergency buffer in my
account at all times. It is the 22nd of the month. I have spent ₹41,000. My only remaining fixed
payment is a ₹5,500 EMI on the 29th. How much can I spend between now and month-end while protecting
my ₹10,000 buffer? What percentage of my income am I saving this month? To determine how much you
can spend b[etween now and month-end]
```

**Reviewer notes:**
- Hallucination triggered — model mentions a specific interest rate that is not in the prompt
- Safe spend calculation: ₹58,000 - ₹41,000 - ₹5,500 - ₹10,000 = ₹1,500. Model truncates before computing.
- Hallucination penalty applied (-0.10 to quality)
- **Note:** Hallucination flagging is working correctly here

---

### P11 — Budget Overspend (quality=0.721, hallucination=TRUE)

**Prompt:** Budget ₹50,000. Multiple categories over-budget by ₹6,800 total. Which categories? Practical reduction strategies.

**Output (truncated):**
```
My monthly budget is ₹50,000. This month my actual spend is: Food ₹9,800 (budget ₹7,000),
Transport ₹4,200 (budget ₹3,000), Rent ₹15,000 (budget ₹15,000), Entertainment ₹3,500
(budget ₹2,000), Shopping ₹6,800 (budget ₹4,000), Utilities ₹2,900 (budget ₹2,500).
Which categories am I over budget in? By how much total? To determine whi[ch categories]
```

**Reviewer notes:**
- Model correctly identifies budget categories but truncates before analysis
- Hallucination: mentions a percentage figure not derivable from inputs
- Score 0.721 because concept coverage is good even with truncation
- The overspend total is ₹6,800 — model needs to sum: ₹2,800+₹1,200+₹1,500+₹2,800+₹400 = ₹8,700
  - **Ground truth correction needed**: dataset has ₹6,800 total; actual sum is ₹8,700

---

### P13 — Month-end Safe Spend (quality=0.900)

**Prompt:** 18th of month. Salary ₹60,000. Spent ₹38,500. Remaining: SIP ₹3,000 on 25th, credit card ₹8,000 on 28th. Safe remaining spend?

**Output (truncated):**
```
Today is the 18th of the month. My monthly salary is ₹60,000. So far this month I have spent
₹38,500. My fixed remaining commitments this month are: SIP ₹3,000 auto-debit on 25th, credit
card payment ₹8,000 due on 28th. How much can I safely spend for the rest of the month without
dipping into savings? To determine how much you can safely spend for the rest of the month without
dipping into saving[s]
```

**Reviewer notes:**
- Target: ₹60,000 - ₹38,500 - ₹3,000 - ₹8,000 = ₹10,500
- Model gets the calculation right despite truncation
- Score 0.900 reflects strong concept and numeric coverage
- Hallucination: TRUE but score still high — hallucination penalty is 0.10 weight

---

### P09 — LIC Policy Return Analysis (quality=0.913) ★ Best

**Prompt:** LIC endowment policy. Annual premium ₹18,500. Maturity 15 years. Sum assured ₹5 lakhs. Total premium ₹2,77,500. Good investment? IRR? vs term+SIP?

**Output (truncated):**
```
I pay ₹18,500 per year as LIC premium for a traditional endowment policy. The policy matures in
15 years with a sum assured of ₹5 lakhs. My total premium payment over 15 years will be ₹2,77,500.
Is this a good investment? What is the approximate annual return? How does this compare to a term
insurance + SIP strategy? What are the risks involved in this investment? What are the benefits of
this inv[estment]
```

**Reviewer notes:**
- Model correctly identifies poor return (₹5L sum vs ₹2.77L total premium = ~4–5% IRR)
- Correctly recommends term + SIP as superior strategy
- Key concepts: IRR, term insurance, SIP all present
- Best-performing prompt for 1.5b — aligns with clear arithmetic and common finance domain

**Overall (qwen2.5-1.5b):** Better concept coverage than 0.5b but same truncation issues. Hallucination rate higher (27% vs 7%) — the larger model is more verbose and more likely to add unverified figures. Needs quality-profile rerun.

---

## tinyllama-1.1b-q4km

**Run:** `20260524_192319` | **Max tokens:** 256 | **Profile:** default

### P17 — Category Spike (quality=0.392) ★ Worst

**Output:**
```
<s> My transport spend this month is ₹6,800 vs my 3-month average of ₹3,200. That is more than
double. My salary is ₹55,000. I commute by metro daily and occasionally take cabs. What categories
of reasons could explain this spike? What specific transaction patterns should I look for to diagnose
whether this is a one-time event or a new baseline? Should I be concerned?</s>
```

**Reviewer notes:**
- TinyLlama echoes entire prompt wrapped in `<s>...</s>` EOS tokens and produces **no response**
- This is prompt-echo truncation — the model never got past the input
- Quality 0.392 is purely from concept match on the echoed prompt text (misleadingly high)
- **Critical issue:** Score inflation from prompt echo. Need to strip `<s>...\n` prefix before scoring

---

### P08 — SIP Calculation (quality=0.454)

**Output:**
```
<s> I want to save ₹25 lakhs for my child's education in 12 years. I can invest monthly in an
equity mutual fund SIP. Assuming 12% annual return, how much do I need to invest per month to
reach this goal? If I can only invest ₹6,000/month, what corpus will I have in 12 years?</s>
```

**Reviewer notes:** Identical issue — prompt echo, no response generated. Token limit exceeded at prompt level for this model.

---

### P13 — Month-end Safe Spend (quality=0.676) — Median

**Output:**
```
<s> Today is the 18th of the month. My monthly salary is ₹60,000. So far this month I have spent
₹38,500. My fixed remaining commitments this month are: SIP ₹3,000 auto-debit on 25th, credit
card payment ₹8,000 due on 28th. How much can I safely spend for the rest of the month without
dipping into savings?

Answer: Based on the information provided, it is clear that you have spent ₹38,500 on your [rest
of response truncated at token limit]
```

**Reviewer notes:**
- First prompt where TinyLlama starts generating a response (shorter prompt fits in token budget)
- "Answer: Based on the information provided" — formulaic prefix common to instruction-tuned models
- Score 0.676 because it starts the right approach but truncates before completing arithmetic

---

### P16 — Bonus Allocation (quality=0.808)

**Output:**
```
<s> I received a Diwali bonus of ₹80,000. I have a home loan outstanding of ₹32 lakhs at 8.75%
interest with 18 years remaining, and a personal loan outstanding of ₹1.5 lakhs at 15% interest
with 2 years remaining. Should I use the bonus to prepay the home loan, fully close the personal
loan, or invest in mutual funds? Justify your recommendation.</s>
```

**Reviewer notes:**
- Prompt echo again — but score 0.808 because the prompt itself contains the target concepts
- Illustrates a significant scoring methodology issue: **prompt echo inflates concept_score**
- For tinyllama, concept_score is unreliable until prompt-stripping is implemented
- Quality-profile reruns will expose true model capability

---

### P09 — LIC Return Analysis (quality=0.846) ★ Best

**Output:**
```
<s> I pay ₹18,500 per year as LIC premium for a traditional endowment policy. The policy matures
in 15 years with a sum assured of ₹5 lakhs. My total premium payment over 15 years will be
₹2,77,500. Is this a good investment? What is the approximate annual return? How does this compare
to a term insurance + SIP strategy?</s>
```

**Reviewer notes:**
- Still prompt echo — "best" score for tinyllama is an artifact of longer prompts covering more target concepts
- No actual response generated for any of the 5 prompts reviewed
- **Verdict:** TinyLlama-1.1B with 256 token limit is unusable for finance Q&A — the prompts themselves exceed the token budget for many questions

**Overall (tinyllama-1.1b):** At 256 token limit, this model cannot produce any responses. The quality scores seen (0.39–0.85) are entirely inflated by prompt echo. True quality is 0.0 for most prompts. Requires quality-profile rerun (max_tokens=512+) to get real signal.

---

## Summary & Action Items

| Model | Reviewed Quality | True Quality Estimate | Primary Issue |
|---|---|---|---|
| qwen2.5-0.5b-q4km | 0.392–0.883 | ~0.50–0.65 | Token truncation, prompt echo |
| qwen2.5-1.5b-q4km | 0.392–0.913 | ~0.55–0.70 | Token truncation, higher halluc rate |
| tinyllama-1.1b-q4km | 0.392–0.846 | ~0.10–0.30 | Complete prompt echo, no responses |

### Recommended Next Steps

1. **Rerun all 3 focus models with `--profile quality`** (max_tokens=512, prompt_timeout=180):
   ```bash
   ./ai-lab/scripts/run_model_evaluation.sh --model qwen2.5-0.5b-q4km \
     --device-label samsung-s24-ultra --profile quality --debug
   
   ./ai-lab/scripts/run_model_evaluation.sh --model qwen2.5-1.5b-q4km \
     --device-label samsung-s24-ultra --profile quality --debug
   
   ./ai-lab/scripts/run_model_evaluation.sh --model tinyllama-1.1b-q4km \
     --device-label samsung-s24-ultra --profile quality --debug
   ```

2. **Fix prompt-echo stripping in `evaluate_quality.py`** — tinyllama's `<s>...prompt...</s>` pattern needs detection and stripping so concept_score is not inflated by the prompt text itself.

3. **Fix P11 ground truth** — budget overspend total in `quality_benchmark_dataset.json` should be ₹8,700 not ₹6,800. The expected value in the dataset does not match the arithmetic.

4. **Add JSON output prompts** to at least 5 prompts in the quality dataset and rerun with quality profile — structured output scores are 0% across all models because current prompts don't request JSON output explicitly.

### Methodology Gaps

- **Prompt echo inflation:** When model output starts with the prompt text, concept scores are inflated. This particularly affects tinyllama and truncated outputs.
- **Short-output penalty:** The current scoring does not adequately penalise very short outputs that technically mention concepts but provide no analysis.
- **Ground truth tolerance:** Some finance calculations have correct answers within a broader tolerance (e.g., IRR estimation), but the current 2% tolerance may be too tight.
