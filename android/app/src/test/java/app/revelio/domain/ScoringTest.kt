package app.revelio.domain

import app.revelio.domain.scoring.gradeFromScore
import app.revelio.domain.scoring.personalizeScore
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Ports the behavior guarantees from `shared/scoring.ts`:
 *   - No priorities → score unchanged.
 *   - Priorities match a flag → penalty = severity * 5 * overlap.
 *   - Score clamps to [0, 100].
 *   - Grade thresholds: A≥80, B≥65, C≥50, D≥35, F<35.
 */
class ScoringTest {

    @Test
    fun `no priorities returns base score`() {
        val flags = listOf(
            IngredientFlag(
                ingredient = "palm oil",
                severity = 2,
                category = "seed oil",
                reason = "",
                priorities = listOf("seed_oils"),
            )
        )
        assertEquals(80, personalizeScore(80, flags, emptyList()))
    }

    @Test
    fun `single overlapping priority subtracts severity times five`() {
        val flags = listOf(
            IngredientFlag(
                ingredient = "soybean oil",
                severity = 3,
                category = "seed oil",
                reason = "",
                priorities = listOf("seed_oils"),
            )
        )
        // 100 - (3 * 5 * 1) = 85
        assertEquals(85, personalizeScore(100, flags, listOf(UserPriority.SEED_OILS)))
    }

    @Test
    fun `multi-priority overlap multiplies penalty`() {
        val flags = listOf(
            IngredientFlag(
                ingredient = "red-40",
                severity = 2,
                category = "artificial dye",
                reason = "",
                priorities = listOf("artificial_additives", "endocrine_disruptors"),
            )
        )
        // overlap = 2, severity = 2 → penalty 2*5*2 = 20.  70 - 20 = 50.
        val score = personalizeScore(
            70,
            flags,
            listOf(UserPriority.ARTIFICIAL_ADDITIVES, UserPriority.ENDOCRINE_DISRUPTORS),
        )
        assertEquals(50, score)
    }

    @Test
    fun `score clamps at zero`() {
        val flags = List(10) {
            IngredientFlag(
                ingredient = "x",
                severity = 3,
                category = "test",
                reason = "",
                priorities = listOf("seed_oils"),
            )
        }
        assertEquals(0, personalizeScore(20, flags, listOf(UserPriority.SEED_OILS)))
    }

    @Test
    fun `score clamps at one hundred`() {
        // No flags → no penalty, so a 100 base stays at 100 even with priorities.
        assertEquals(100, personalizeScore(100, emptyList(), listOf(UserPriority.VEGAN)))
    }

    @Test
    fun `grade boundaries match ts source`() {
        assertEquals(Grade.A, gradeFromScore(80))
        assertEquals(Grade.B, gradeFromScore(65))
        assertEquals(Grade.C, gradeFromScore(50))
        assertEquals(Grade.D, gradeFromScore(35))
        assertEquals(Grade.F, gradeFromScore(34))
        assertEquals(Grade.A, gradeFromScore(100))
        assertEquals(Grade.F, gradeFromScore(0))
    }

    @Test
    fun `non-matching priorities do not penalize`() {
        val flags = listOf(
            IngredientFlag(
                ingredient = "sls",
                severity = 2,
                category = "sulfate",
                reason = "",
                priorities = listOf("sulfate_free"),
            )
        )
        // User cares about gluten, not sulfates — no penalty.
        assertEquals(60, personalizeScore(60, flags, listOf(UserPriority.GLUTEN_FREE)))
    }
}
