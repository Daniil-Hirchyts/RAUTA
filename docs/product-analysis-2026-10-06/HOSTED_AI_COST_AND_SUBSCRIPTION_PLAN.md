**RAUTA — hosted AI costs and subscription plan**

6 October 2026 · Analysis only · Companion to the [product and subscription plan](RAUTA_PRODUCT_AND_SUBSCRIPTION_PLAN.md)

**Recommendation**

Keep the proposed €4.99/month and €34.99/year prices as hypotheses. Hosted text assistance can fit those prices if RAUTA uses a small model, retains its existing local training engines, and enforces usage limits on a server. The price alone does not establish profitability: model quality, actual usage, hosting, acquisition, support and retention still need measurement.

Sell ongoing training guidance: a useful next week, adjustments and explanations of progress. Include optional cloud assistance within Plus. Local and cloud interfaces should respect the same Free/Plus feature boundaries; local inference is not an automatic entitlement to every premium operation.

Start by comparing OpenAI GPT-6 Luna and Mistral Small 4 against the existing local model, adding Ministral 3 8B as a cheaper candidate. Gemini Flash-Lite and GPT-OSS on Groq are further alternatives. Select one hosted provider for the first pilot. Provider switching can remain an internal capability; beginners should not need to choose a model. Only add a larger model to a specific task if evaluation establishes a useful improvement. No model has been benchmarked on RAUTA in this analysis.

**What the current architecture makes possible**

RAUTA already parses many recognizable requests in Swift and executes validated operations through its host. Planning, progression and adaptations have local engines. The model can interpret unfamiliar wording and explain computed results without taking over training decisions. [Agent flow](../../ios/Rauta/Rauta/Agent/Core/RautaAgent.swift#L101).

The current assistant supplies a small profile summary, four upcoming workouts and three recent messages trimmed to 90 characters each. It chooses a limited set of relevant tools. This is a good starting point, but actual hosted token counts must include instructions, tool definitions, arguments and returned data. No hosted usage was measured during this analysis. [Context](../../ios/Rauta/Rauta/Agent/Core/AgentContext.swift#L5), [tool routing](../../ios/Rauta/Rauta/Agent/Core/AgentTools.swift).

One limitation needs changing in a future implementation: `send` currently checks whether the local model is installed before it attempts deterministic interpretation. Standard commands should work without that download; subscribers choosing cloud mode should not need it either. [Readiness guard](../../ios/Rauta/Rauta/Agent/Core/RautaAgent.swift#L75).

Voice transcription and speech synthesis already use Apple APIs. Keep those local initially and send only the resulting text to the hosted model. This preserves voice interaction without introducing paid live audio sessions. [Voice implementation](../../ios/Rauta/Rauta/Native/VoiceIO.swift).

**Cost scenarios**

These are calculated scenarios using published paid Standard text rates checked today. Each request assumes 2,000 input tokens and 500 total billable output tokens, one model call, and no cache discount. The input allowance includes tools and context. Figures exclude hosting, API taxes, regional uplifts, extra calls and retries. Different tokenizers can produce different counts for identical text.

| Model and rate source | Input / output, USD per million tokens | 100 requests | 500 requests | 2,000 requests |
|---|---|---|---|---|
| [OpenAI GPT-6 Luna](https://developers.openai.com/api/docs/pricing) | $0.10 / $0.50 | $0.045 | $0.225 | $0.90 |
| [Gemini 2.5 Flash-Lite](https://ai.google.dev/gemini-api/docs/pricing) | $0.10 / $0.40 | $0.040 | $0.200 | $0.80 |
| [Claude Haiku 4.5](https://platform.claude.com/docs/en/about-claude/pricing) | $1.00 / $5.00 | $0.450 | $2.250 | $9.00 |
| [OpenAI GPT-6.1 Sol](https://developers.openai.com/api/docs/pricing) | $2.00 / $10.00 | $0.900 | $4.500 | $18.00 |

Formula: requests × (input tokens × input rate + billable output tokens × output rate) ÷ 1,000,000.

The columns compare cost under identical token assumptions, not answer quality. Invisible reasoning is billed as output; 500 visible tokens plus additional reasoning would exceed this scenario. OpenAI's `max_output_tokens` includes reasoning as well as visible output. Test an appropriate cap and reasoning setting against task quality. [Reasoning accounting](https://developers.openai.com/api/docs/guides/reasoning), [Luna settings](https://developers.openai.com/api/docs/models/gpt-6-luna).

An illustrative monthly bundle is 200 Luna requests ($0.09) and four Sol reviews, each with 5,000 input and 1,000 billable output tokens ($0.08 total). That is **$0.17**, or **$0.204 with an illustrative 20% contingency**. A fifth review raises the pre-contingency total to $0.19. A contingency is not a measured retry rate or a substitute for enforcing limits.

Larger context, reasoning and repeated passes change this result. At 10,000 input and 2,000 billable output tokens per call, 500 Sol calls would cost $20. Treat each provider call separately in the ledger, even when the user sees one message. Do not base the business on free API tiers, assumed cache hits or batch savings.

**Other providers and the model shortlist**

Luna is a useful baseline, not an established winner. The following expands the same 2,000-input/500-billable-output scenario, using current Standard/global rates without caching, regional surcharges or extra calls. The DeepSeek range uses off-peak and peak uncached rates.

| Model and official rate source | Input / output, USD per million tokens | 500 requests |
|---|---|---|
| [Ministral 3 3B](https://docs.mistral.ai/inference/pricing) | $0.10 / $0.10 | $0.125 |
| [Ministral 3 8B](https://docs.mistral.ai/inference/pricing) | $0.15 / $0.15 | $0.1875 |
| [Mistral Small 4](https://docs.mistral.ai/inference/pricing) | $0.15 / $0.60 | $0.300 |
| [GPT-OSS 20B on Groq](https://console.groq.com/docs/models) | $0.075 / $0.30 | $0.150 |
| [GPT-OSS 120B on Groq](https://console.groq.com/docs/models) | $0.15 / $0.60 | $0.300 |
| [Gemini 3.1 Flash-Lite](https://ai.google.dev/gemini-api/docs/pricing) | $0.25 / $1.50 | $0.625 |
| [DeepSeek V4.1 Flash](https://api-docs.deepseek.com/quick_start/pricing/) | $0.15–$0.30 / $0.60–$1.20 | $0.300–$0.600 |
| [Grok 4.7](https://docs.x.ai/developers/pricing) | $2.00 / $6.00 | $3.500 |

The newer Gemini 3.1 model is an additional candidate; the earlier 2.5 model in the first table remains a lower-cost comparison. Model age or parameter count alone does not establish which produces better RAUTA results.

At 200 requests/month, choosing Ministral 3 8B instead of Luna saves $0.015 in this scenario. Choosing Small 4 instead of Luna adds $0.03. These differences are small enough to prioritize correct actions and helpful explanations. Evaluate the smallest model that passes those tests; a cheap answer requiring corrections is not necessarily cheaper per completed task.

Mistral Small 4 and Ministral 3 8B both document function calling and structured outputs, relevant to RAUTA's validated-action architecture. Treat Small 4 as the first Mistral comparison and 8B as a further cost experiment, not a claim about measured superiority. [Small 4 capabilities](https://docs.mistral.ai/models/mistral-small-4-0-26-03), [8B capabilities](https://docs.mistral.ai/models/ministral-3-8b-25-12).

Groq is a hosting provider, distinct from xAI's Grok models. Its GPT-OSS options are inexpensive candidates for a responsive assistant, but measure full response time and billed reasoning rather than equating published token speed with the user's wait. Its structured-output mode currently cannot be combined with streaming or tool use; validate the intended action protocol accordingly. [GPT-OSS 20B details](https://console.groq.com/docs/model/openai/gpt-oss-20b), [structured-output limitations](https://console.groq.com/docs/structured-outputs).

Mistral also offers EU regional inference, with an upcharge, varying model availability and feature restrictions. The global endpoint does not promise an inference location. OpenAI documents eligible EU processing for Luna as well; European processing is a configuration decision, not something to infer from a company's nationality. [Mistral regional inference](https://docs.mistral.ai/inference/regional-inference), [Luna regional options](https://developers.openai.com/api/docs/models/gpt-6-luna).

DeepSeek's current Flash supports non-thinking mode and tool calls, but its time-dependent pricing needs a peak-rate budget for interactive use. Grok 4.7 is a less economical first candidate for this particular small subscription unless testing demonstrates enough additional value. These are product recommendations, not benchmark conclusions. A provider change must recalculate the allowance and spending ceiling; the Luna example does not describe every provider's cost.

**Jev by TypeSafe AI: an optional decision layer**

The user's clarification identifies Jev, TypeSafe AI's System One model. Its interface returns predefined choices, scores and yes/no probabilities. It does not generate coaching replies or reasoning explanations, so assess it for a different role from Luna and Mistral. Structured output and calibrated probabilities do not guarantee a correct individual decision. [System One interface](https://docs.typesafe.ai/concepts/system-one).

TypeSafe lists Jev 1.13 at $0.042 per million input tokens, with output free. At an assumed 2,000 total billable input tokens, 500 decision requests cost **$0.042**; 200 cost **$0.0168**. This is direct-provider inference only, without gateway fees or any downstream text generation. English is documented as its strongest language; test other supported app languages. [Current model reference](https://docs.typesafe.ai/models).

Possible RAUTA roles, proposed rather than tested:

- Classify an unfamiliar request into known intents such as schedule, swap, progress, logging or general advice.
- Choose between candidate workouts or substitutions already retrieved and validated by Swift.
- Signal ambiguity so RAUTA can ask for clarification or use a generative model.

The potential future flow is: keep recognized commands in Swift; try Jev only for focused uncertain decisions; execute a selected action through the existing validations and render its normal result; use Luna or Mistral where prose or broader interpretation is required. A known deterministic command already costs no inference, so replacing that path with Jev would add an expense.

Jev needs a bounded answer space. Candidate extraction, exact loads/repetitions, date arithmetic, progression calculations and permissions remain application responsibilities. TypeSafe documents weaknesses in numerical precision, dates, literal interpretation and irrelevant context. Thresholds must be evaluated on RAUTA requests, and every selected action still needs validation. [Known limitations](https://docs.typesafe.ai/model-jaggedness/jev-1.13).

For the 500-request scenario, Jev followed by Luna on every request costs $0.267 versus $0.225 for Luna alone. If half can finish after Jev with a normal local result, the modeled total becomes $0.1545. With these identical input assumptions, Jev needs to eliminate more than roughly 19% of Luna calls to reduce inference cost. Real question/context sizes and tokenizers will change that threshold. Both the latency benefit and savings require measurement.

Recommendation: evaluate Luna and Mistral Small 4 as conversational providers first. Include Jev in a separate routing experiment if the current parser leaves many bounded decisions unresolved. Adopt it only if it improves completed-task accuracy or latency enough to justify another provider; saving a few cents alone is a weak reason to add integration complexity. Keep the server budget, privacy opt-in and fallback rules consistent across all hosted calls.

**Budget against subscription proceeds**

This example assumes the displayed price includes 20% VAT, then applies either a 15% or 30% commission to the price excluding VAT. It is illustrative, not a determination of RAUTA's tax treatment or Apple agreement. Apple describes 85% proceeds for enrolled Small Business developers and the standard subscription proceeds progression on its [subscription page](https://developer.apple.com/app-store/subscriptions/).

| Customer price | Monthly proceeds at 15% commission | Monthly proceeds at 30% commission |
|---|---|---|
| €4.99/month | €3.53 | €2.91 |
| €34.99/year, divided by 12 | €2.07 | €1.70 |

Use actual App Store Connect proceeds when available. The annual plan provides the tighter monthly budget. Provider costs are USD; convert them using billing exchange rates and include a cushion before subtracting them from euro proceeds.

For a pilot, aim for AI cost around 10–15% of annual-plan proceeds. A **$0.30 monthly provider-spend ceiling per subscriber** is a starting hypothesis to reconcile with actual proceeds, exchange rates and measured usage. Hosting has its own budget. For example, a hypothetical $20 monthly hosting bill costs $1 per subscriber at 20 paying users, but $0.20 at 100; this is arithmetic, not a hosting quote. Low subscriber volume can matter more than inexpensive inference.

Do not offer lifetime unlimited hosted inference: it creates ongoing costs without ongoing proceeds. Locally delivered lifetime features would have different economics.

**Proposed Free and Plus experience**

| Free | Plus |
|---|---|
| Core workout logging, history and the Free training features from the original plan | Ongoing plans, adaptations, progression explanations and reviews |
| Standard commands executed locally; optional on-device conversations where supported | Same local experience plus optional cloud assistance |
| No recurring hosted allowance by default | Pilot hypothesis: 200 cloud messages/month plus weekly reviews; budget for five reviews in a month |

The visible allowance must be validated using high-cost successful sessions, including tool rounds and retries. If it cannot fit the spend ceiling, simplify the workflow, use the smaller model for reviews, adjust the allowance or revise the price before promising it publicly. Do not advertise “unlimited cloud AI.” Count successful cloud messages consistently, disclose the reset date and show remaining allowance. Technical retries should not become unexplained deductions.

When the allowance is exhausted, clearly explain the next reset and keep available local assistance and subscribed local training features usable. A service outage should produce an honest local fallback, not a false claim that a requested action succeeded. Saved training remains accessible on cancellation as described in the original plan.

**Minimum server design and spending controls**

Hosted AI changes the architecture: locally delivered subscriptions do not inherently require RAUTA's own server, but shared provider credentials and per-subscriber cloud limits do. Use a small proxy with secrets on the server and a persistent entitlement/usage ledger. Never embed RAUTA's provider key in the iPhone app. [API key guidance](https://developers.openai.com/api/docs/guides/production-best-practices).

Proposed controls for later implementation:

1. Verify the subscription server-side; associate cloud usage with a stable subscriber identity across reinstall, restore and multiple devices. A local Boolean or installation ID alone is insufficient. Decide whether a purchase-linked identity without an email account meets this requirement.
2. Allow only approved models and tasks on the server. Enforce limits on input tokens, billable output, request size, simultaneous requests and daily/monthly usage. Reject excessive input before forwarding it. Keep routine reasoning minimal only where quality testing supports it.
3. Prefer one inference call for normal actions, then render the validated Swift result directly. Bound any second pass and retries. Never retry an operation that changes training without preventing duplicate execution.
4. Atomically reserve a conservative worst-case cost before each provider call, covering permitted input/output and applicable surcharges. Concurrent requests must share the same budget. Reconcile reservations against billed usage; an ambiguous timeout must not immediately release money that may already have been spent.
5. Track spend per subscriber and across the service. Keep provider pricing configurable. Include refunds/revocations, expiry, rate limiting and abuse controls in access decisions.
6. Add a global service ceiling and a switch to disable cloud calls. Use provider alerts and hard limits as a second layer. OpenAI now supports enforced spend limits, but enforcement is not instantaneous and spend can slightly exceed them. [Spend-limit behavior](https://developers.openai.com/api/docs/guides/spend-limits).

RAUTA should retain responsibility for interpreting returned actions, checking constraints and confirming changes. A hosted model must not bypass the existing equipment, scheduling or training validations.

**Privacy and validation before committing**

The current privacy screen promises that chats remain on the phone and that RAUTA has no servers. Cloud mode needs a clear opt-in identifying the provider and the information sent, with a local option retained. Send only task-relevant training summaries; avoid forwarding the whole workout database or unrelated Health data. [Current privacy copy](../../ios/Rauta/Rauta/Views/Screens/PoliciesScreen.swift#L265).

OpenAI API content is not used for training by default, but this does not mean zero retention. Abuse-monitoring retention is generally up to 30 days, and endpoint storage settings require attention. Document the chosen configuration accurately. Google's pricing page also distinguishes data use in its free and paid tiers. [OpenAI data controls](https://developers.openai.com/api/docs/guides/your-data), [Gemini tier details](https://ai.google.dev/gemini-api/docs/pricing).

Before choosing a provider, prepare 50–100 representative scenarios: clear and ambiguous requests, dates, equipment restrictions, missed sessions, insufficient history, progress explanations and supported languages. Compare against local inference. Measure valid actions, factual accuracy against records, response time and total billed cost, including failed attempts. A cheaper model that needs repeated correction can cost more and feel worse.

Then run a limited paid pilot. Track median and high-percentile cost per subscriber, maximum cost, actual usage, completed guidance tasks, retention and net proceeds. Adopt the €4.99/€34.99 offer only if users value the guidance and the annual-plan economics hold. Add provider choice, user-supplied keys, paid live audio or extra cloud packs later only if observed demand warrants them.

This document is a proposed product and architecture plan. No application code, billing integration or hosted API requests were added.
