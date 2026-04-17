package app.revelio.domain.scoring

import app.revelio.domain.Grade
import app.revelio.domain.IngredientFlag
import app.revelio.domain.UserPriority

/**
 * Kotlin re-implementation of `shared/scoring.ts::personalizeScore`.
 *
 * The backend owns the authoritative `baseScore`. This client-side
 * implementation lets us re-score cached scan results when the user toggles
 * priorities without a round-trip — and it keeps the scoring logic in one
 * place on mobile so history / pantry views can show consistent grades.
 *
 * Algorithm (matches TS source):
 *   - Start with `baseScore`.
 *   - For each flag whose priorities overlap the user's active priorities,
 *     subtract `severity * 5 * overlap`.
 *   - Clamp to [0, 100].
 */
fun personalizeScore(
    baseScore: Int,
    flags: List<IngredientFlag>,
    priorities: List<UserPriority>,
): Int {
    if (priorities.isEmpty()) return baseScore
    val activeWire = priorities.map { it.wire }.toHashSet()

    var penalty = 0
    for (flag in flags) {
        val overlap = flag.priorities.count { it in activeWire }
        if (overlap > 0) {
            penalty += flag.severity * 5 * overlap
        }
    }

    val adjusted = baseScore - penalty
    return adjusted.coerceIn(0, 100)
}

/**
 * Thin convenience wrapper for callers that only have a raw score.
 * Mirrors `scoreToGrade` in the TS source.
 */
fun gradeFromScore(score: Int): Grade = Grade.fromScore(score)
