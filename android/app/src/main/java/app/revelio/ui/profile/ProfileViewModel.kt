package app.revelio.ui.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.revelio.data.repo.AuthRepository
import app.revelio.data.repo.ProfileRepository
import app.revelio.domain.FamilyMember
import app.revelio.domain.UserPriority
import app.revelio.domain.UserProfile
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class ProfileUiState(
    val profile: UserProfile? = null,
    val members: List<FamilyMember> = emptyList(),
    val loading: Boolean = false,
    val error: String? = null,
)

@HiltViewModel
class ProfileViewModel @Inject constructor(
    private val authRepo: AuthRepository,
    private val profileRepo: ProfileRepository,
) : ViewModel() {

    private val _state = MutableStateFlow(ProfileUiState())
    val state: StateFlow<ProfileUiState> = _state.asStateFlow()

    init {
        _state.update { it.copy(profile = authRepo.cachedUser) }
        load()
    }

    fun load() {
        val id = authRepo.cachedUser?.id ?: return
        _state.update { it.copy(loading = true, error = null) }
        viewModelScope.launch {
            runCatching {
                val profile = profileRepo.profile(id)
                val members = profileRepo.members(id)
                profile to members
            }.onSuccess { (profile, members) ->
                _state.update { it.copy(loading = false, profile = profile, members = members) }
            }.onFailure { t ->
                _state.update { it.copy(loading = false, error = t.message) }
            }
        }
    }

    fun togglePriority(priority: UserPriority) {
        val id = authRepo.cachedUser?.id ?: return
        val current = _state.value.profile?.priorities?.toMutableList() ?: mutableListOf()
        if (priority.wire in current) current.remove(priority.wire) else current.add(priority.wire)

        viewModelScope.launch {
            runCatching {
                profileRepo.updatePriorities(
                    id = id,
                    priorities = current,
                    allergies = null,
                    goals = null,
                )
            }.onSuccess { updated ->
                _state.update { it.copy(profile = updated) }
            }
        }
    }

    fun signOut() {
        authRepo.signOut()
    }
}
