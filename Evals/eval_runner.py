#!/usr/bin/env python3
"""
AI Coach eval runner using Python MLX.

Uses the Swift `coach-eval inspect` command to get prompts from AICoachCore
(ensuring prompt consistency with the live app), then runs them through
the Python MLX runtime which handles Metal correctly from the command line.

Usage:
    python3 eval_runner.py                          # Run all scenarios
    python3 eval_runner.py --scenario high-rpe      # Run one scenario
    python3 eval_runner.py --compare                # Compare flat vs chat
    python3 eval_runner.py --temperature 0.3        # Override params
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
from dataclasses import dataclass

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Deliberately still Gemma 3 4B: production runs Gemma 4 E2B
# (lmstudio-community/gemma-4-E2B-it-MLX-4bit), so scores do not reflect the
# shipping model. Keep in step with CoachGenerator.modelID.
MODEL_ID = "mlx-community/gemma-3-4b-it-qat-4bit"

SCENARIOS = ["high-rpe", "balanced", "empty", "single-hard", "mixed"]

SCENARIO_DESCRIPTIONS = {
    "high-rpe": "High RPE Overtraining — 5 workouts at RPE 8-9, demanding plan",
    "balanced": "Balanced Training — 4 workouts at RPE 5-7, reasonable plan",
    "empty": "Empty History — no recent workouts, 3 upcoming",
    "single-hard": "Single Hard Workout — one long run at RPE 9, intervals tomorrow",
    "mixed": "Mixed Signals — easy runs low RPE + one interval at RPE 9",
}

# Expected keywords per scenario (at least one should appear)
SCENARIO_KEYWORDS = {
    "high-rpe": ["reduce", "recovery", "rest", "easy", "volume", "lower", "cut", "drop", "cap"],
    "balanced": ["maintain", "continue", "consistent", "keep", "solid", "good"],
    "empty": ["no", "data", "record", "history", "track", "without"],
    "single-hard": ["recovery", "postpone", "easy", "rest", "swap", "delay"],
    "mixed": ["interval", "reduce", "intensity", "modify", "adjust"],
}

# ---------------------------------------------------------------------------
# Prompt extraction (via Swift CLI)
# ---------------------------------------------------------------------------

SWIFT_BINARY = None


def find_swift_binary():
    """Find the built CoachEval binary."""
    global SWIFT_BINARY
    script_dir = os.path.dirname(os.path.abspath(__file__))
    for config in ["release", "debug"]:
        path = os.path.join(
            script_dir, f".build/arm64-apple-macosx/{config}/CoachEval"
        )
        if os.path.exists(path):
            SWIFT_BINARY = path
            return
    # Fallback: try swift run
    SWIFT_BINARY = None


def get_prompt(scenario: str, prompt_mode: str) -> dict:
    """
    Calls the Swift inspect command to get the prompt from AICoachCore.
    Returns a dict with 'system' and 'user' keys for chat mode,
    or 'flat' key for flat mode.
    """
    if SWIFT_BINARY:
        cmd = [
            SWIFT_BINARY,
            "inspect",
            "--scenario",
            scenario,
            "--prompt-mode",
            prompt_mode,
        ]
    else:
        cmd = [
            "swift",
            "run",
            "CoachEval",
            "inspect",
            "--scenario",
            scenario,
            "--prompt-mode",
            prompt_mode,
        ]

    result = subprocess.run(cmd, capture_output=True, text=True, cwd=os.path.dirname(os.path.abspath(__file__)))
    output = result.stdout

    if prompt_mode == "chat":
        # Parse system and user sections
        system_match = re.search(
            r"\[System message\]\n(.*?)\n\[User message\]", output, re.DOTALL
        )
        user_match = re.search(r"\[User message\]\n(.*)", output, re.DOTALL)
        return {
            "system": system_match.group(1).strip() if system_match else "",
            "user": user_match.group(1).strip() if user_match else "",
        }
    else:
        single_match = re.search(
            r"\[Single user message\]\n(.*)", output, re.DOTALL
        )
        return {"flat": single_match.group(1).strip() if single_match else ""}


# ---------------------------------------------------------------------------
# Model loading and generation
# ---------------------------------------------------------------------------


def load_model():
    """Load the model and tokenizer."""
    from mlx_lm import load

    print(f"Loading model {MODEL_ID}...")
    start = time.time()
    model, tokenizer = load(MODEL_ID)
    print(f"Model loaded in {time.time() - start:.1f}s")
    return model, tokenizer


def generate_response(
    model,
    tokenizer,
    prompt_data: dict,
    prompt_mode: str,
    max_tokens: int = 400,
    temperature: float = 0.4,
    top_p: float = 0.9,
    repetition_penalty: float = 1.2,
) -> tuple:
    """Generate a response from the model. Returns (text, generation_time)."""
    from mlx_lm import generate
    from mlx_lm.sample_utils import make_sampler

    if prompt_mode == "chat":
        messages = [
            {"role": "system", "content": prompt_data["system"]},
            {"role": "user", "content": prompt_data["user"]},
        ]
        prompt = tokenizer.apply_chat_template(
            messages, tokenize=False, add_generation_prompt=True
        )
    else:
        messages = [{"role": "user", "content": prompt_data["flat"]}]
        prompt = tokenizer.apply_chat_template(
            messages, tokenize=False, add_generation_prompt=True
        )

    sampler = make_sampler(temp=temperature, top_p=top_p)
    start = time.time()
    response = generate(
        model,
        tokenizer,
        prompt=prompt,
        max_tokens=max_tokens,
        sampler=sampler,
    )
    elapsed = time.time() - start
    return response, elapsed


# ---------------------------------------------------------------------------
# Quality scoring
# ---------------------------------------------------------------------------


@dataclass
class QualityCheck:
    name: str
    score: int
    max_score: int
    passed: bool
    detail: str


def score_response(output: str, scenario: str) -> list:
    """Score the response quality. Returns list of QualityChecks."""
    checks = []

    # Word count (20 pts)
    words = output.split()
    word_count = len(words)
    if 50 <= word_count <= 200:
        checks.append(QualityCheck("Word count", 20, 20, True, f"{word_count} words"))
    elif 20 <= word_count <= 300:
        checks.append(
            QualityCheck("Word count", 10, 20, False, f"{word_count} words")
        )
    else:
        checks.append(
            QualityCheck("Word count", 0, 20, False, f"{word_count} words")
        )

    # No repetition (20 pts) - word trigrams
    lower_words = [w.lower() for w in words]
    if len(lower_words) >= 3:
        trigram_counts = {}
        worst_count = 0
        worst_trigram = ""
        for i in range(len(lower_words) - 2):
            tri = " ".join(lower_words[i : i + 3])
            trigram_counts[tri] = trigram_counts.get(tri, 0) + 1
            if trigram_counts[tri] > worst_count:
                worst_count = trigram_counts[tri]
                worst_trigram = tri
        if worst_count < 3:
            checks.append(
                QualityCheck("No repetition", 20, 20, True, "No excessive repeats")
            )
        else:
            checks.append(
                QualityCheck(
                    "No repetition",
                    0,
                    20,
                    False,
                    f'"{worst_trigram}" x{worst_count}',
                )
            )
    else:
        checks.append(
            QualityCheck("No repetition", 20, 20, True, "Too short to check")
        )

    # Bullet structure (20 pts)
    lines = output.strip().split("\n")
    bullet_lines = [
        l
        for l in lines
        if l.strip().startswith("- ")
        or l.strip().startswith("* ")
        or (l.strip() and l.strip()[0].isdigit() and ". " in l.strip()[:4])
    ]
    bullet_count = len(bullet_lines)
    if 3 <= bullet_count <= 5:
        checks.append(
            QualityCheck(
                "Bullet structure", 20, 20, True, f"{bullet_count} bullets"
            )
        )
    elif bullet_count > 0:
        checks.append(
            QualityCheck(
                "Bullet structure", 10, 20, False, f"{bullet_count} bullets"
            )
        )
    else:
        checks.append(
            QualityCheck("Bullet structure", 0, 20, False, "0 bullets")
        )

    # Actionable language (15 pts)
    action_verbs = [
        "reduce", "increase", "swap", "add", "remove", "keep", "maintain",
        "cap", "replace", "skip", "shorten", "lengthen", "lower", "postpone",
        "move", "drop", "cut", "scale", "modify", "adjust", "incorporate",
        "prioritize", "schedule", "monitor",
    ]
    lower_output = output.lower()
    found = [v for v in action_verbs if v in lower_output]
    action_score = min(15, len(found) * 5)
    checks.append(
        QualityCheck(
            "Actionable language",
            action_score,
            15,
            len(found) >= 3,
            f"Found: {', '.join(found[:5])}",
        )
    )

    # Scenario-relevant keywords (15 pts)
    expected = SCENARIO_KEYWORDS.get(scenario, [])
    matched = [k for k in expected if k in lower_output]
    if len(matched) >= 1:
        checks.append(
            QualityCheck(
                "Relevance",
                15,
                15,
                True,
                f"Matched: {', '.join(matched[:5])}",
            )
        )
    else:
        checks.append(
            QualityCheck("Relevance", 0, 15, False, "No expected keywords found")
        )

    # Coherent ending (10 pts)
    trimmed = output.strip()
    has_artifacts = any(
        t in trimmed
        for t in ["<end_of_turn>", "<start_of_turn>", "<eos>"]
    )
    ends_clean = trimmed and trimmed[-1] in ".!?)"
    if has_artifacts:
        checks.append(
            QualityCheck("Coherent ending", 0, 10, False, "Template artifacts")
        )
    elif ends_clean:
        checks.append(
            QualityCheck("Coherent ending", 10, 10, True, "Clean ending")
        )
    else:
        checks.append(
            QualityCheck(
                "Coherent ending", 5, 10, False, "No terminal punctuation"
            )
        )

    return checks


def print_report(scenario: str, output: str, checks: list, prompt_mode: str, gen_time: float):
    total = sum(c.score for c in checks)
    max_total = sum(c.max_score for c in checks)

    divider = "=" * 60
    print(f"\n{divider}")
    print(f"Scenario: {scenario} — {SCENARIO_DESCRIPTIONS.get(scenario, '')}")
    print(f"Prompt mode: {prompt_mode}")
    print(divider)

    print(f"\n--- Generated Output ---")
    print(output)

    print(f"\n--- Quality Score: {total}/{max_total} ---")
    for c in checks:
        status = "PASS" if c.passed else "FAIL"
        print(f"  [{status}] {c.name}: {c.detail} ({c.score}/{c.max_score})")

    print(f"\nGeneration time: {gen_time:.2f}s")
    print()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(description="AI Coach Eval Runner (Python MLX)")
    parser.add_argument("--scenario", type=str, help="Run only this scenario")
    parser.add_argument(
        "--prompt-mode",
        type=str,
        default="chat",
        choices=["flat", "chat"],
        help="Prompt mode (default: chat)",
    )
    parser.add_argument("--compare", action="store_true", help="Compare flat vs chat")
    parser.add_argument("--temperature", type=float, default=0.4)
    parser.add_argument("--top-p", type=float, default=0.9)
    parser.add_argument("--repetition-penalty", type=float, default=1.2)
    parser.add_argument("--max-tokens", type=int, default=400)
    parser.add_argument("--iterations", type=int, default=1)
    args = parser.parse_args()

    find_swift_binary()
    model, tokenizer = load_model()

    scenarios = [args.scenario] if args.scenario else SCENARIOS
    modes = ["flat", "chat"] if args.compare else [args.prompt_mode]

    total_score = 0
    total_max = 0
    run_count = 0

    for scenario in scenarios:
        for mode in modes:
            for i in range(args.iterations):
                if args.iterations > 1:
                    print(f"\n--- Iteration {i + 1}/{args.iterations} ---")

                prompt_data = get_prompt(scenario, mode)
                output, gen_time = generate_response(
                    model,
                    tokenizer,
                    prompt_data,
                    mode,
                    max_tokens=args.max_tokens,
                    temperature=args.temperature,
                    top_p=args.top_p,
                    repetition_penalty=args.repetition_penalty,
                )

                checks = score_response(output, scenario)
                print_report(scenario, output, checks, mode, gen_time)

                total_score += sum(c.score for c in checks)
                total_max += sum(c.max_score for c in checks)
                run_count += 1

    if run_count > 1:
        print("=" * 60)
        pct = total_score / total_max * 100 if total_max > 0 else 0
        print(
            f"Overall: {total_score}/{total_max} across {run_count} runs ({pct:.0f}%)"
        )
        print()


if __name__ == "__main__":
    main()
