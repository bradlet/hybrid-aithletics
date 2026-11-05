# AI Coach Evals

Runs scenarios against the AI coach's **production model** (Gemma 4 E2B) on your Mac's GPU, through
the same `CoachRuntime` the iOS app uses, and grades each tool-calling turn.

**Full guide: [`docs/EVALS_GUIDE.md`](../docs/EVALS_GUIDE.md).** It covers how it works, how to add
scenarios, how to A/B prompts and models, and a Swift tour of the code.

## Commands

```bash
./coach-eval list [--details]                       # scenarios and tags
./coach-eval inspect --scenario ID [--no-tools]     # the exact prompt; no model
./coach-eval chat [--scenario ID] [--events]        # interactive, with a scenario's snapshot
./coach-eval run [--scenario ID]… [--tag T] [--samples N] [--save] [--note "…"] [--strict]
./coach-eval compare [BEFORE.json AFTER.json]       # default: the two newest saved runs
swift test                                          # CoachEvalKit unit tests; no model
```

`run` and `chat` take `--temperature`, `--top-p`, `--repetition-penalty`, and `--max-tokens`. They
default to `GenerationConfig.chat`, which is what the app uses.

## First run

You need Apple Silicon, macOS 14+, and the Swift 6.4+ toolchain with the Metal toolchain. The first
`run` or `chat` compiles MLX in release mode (a few minutes) and downloads the model (~4.3 GB to
`~/Documents/huggingface`). Both are cached after that.

## Layout

```
Evals/
├── coach-eval                    # swift run -c release CoachEval "$@"
├── Package.swift                 # CoachEvalKit · CoachEval · CoachEvalKitTests
├── Sources/CoachEvalKit/         # model-free: scenarios, expectations, runner, reports
│   └── Scenarios/                # Fixtures + scenarios by area
├── Sources/CoachEval/            # the CLI: commands + MLXTurnGenerator (AICoachRuntime)
├── Tests/CoachEvalKitTests/
└── results/                      # saved runs (git-ignored)
```
