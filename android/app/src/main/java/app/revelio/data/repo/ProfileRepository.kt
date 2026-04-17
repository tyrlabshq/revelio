package app.revelio.data.repo

import app.revelio.data.api.RevelioApi
import app.revelio.data.api.dto.AddMemberBody
import app.revelio.data.api.dto.UpdateProfileBody
import app.revelio.domain.FamilyMember
import app.revelio.domain.UserProfile
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ProfileRepository @Inject constructor(
    private val api: RevelioApi,
) {
    suspend fun profile(id: String): UserProfile = api.profile(id).profile

    suspend fun updatePriorities(
        id: String,
        priorities: List<String>?,
        allergies: List<String>?,
        goals: List<String>?,
    ): UserProfile = api.updateProfile(
        id,
        UpdateProfileBody(
            priorities = priorities,
            allergies = allergies,
            goals = goals,
        )
    ).profile

    suspend fun members(id: String): List<FamilyMember> = api.members(id).members

    suspend fun addMember(
        id: String,
        name: String,
        isChild: Boolean,
        goals: List<String>,
        allergies: List<String>,
        avatarColor: String,
    ): FamilyMember = api.addMember(
        id,
        AddMemberBody(
            name = name,
            isChild = isChild,
            goals = goals,
            allergies = allergies,
            avatarColor = avatarColor,
        )
    ).member
}
