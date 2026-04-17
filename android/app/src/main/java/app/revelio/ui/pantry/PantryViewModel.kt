package app.revelio.ui.pantry

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.revelio.data.api.dto.PantryScoreResponse
import app.revelio.data.db.PantryItemEntity
import app.revelio.data.repo.AuthRepository
import app.revelio.data.repo.PantryRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class PantryUiState(
    val score: PantryScoreResponse? = null,
    val error: String? = null,
    val loading: Boolean = false,
)

@HiltViewModel
class PantryViewModel @Inject constructor(
    private val repo: PantryRepository,
    private val authRepo: AuthRepository,
) : ViewModel() {

    private val userId = authRepo.cachedUser?.id

    val items: StateFlow<List<PantryItemEntity>> =
        (if (userId != null) repo.observe(userId) else emptyFlow())
            .stateIn(
                scope = viewModelScope,
                started = SharingStarted.WhileSubscribed(5_000),
                initialValue = emptyList(),
            )

    private val _ui = MutableStateFlow(PantryUiState())
    val ui: StateFlow<PantryUiState> = _ui.asStateFlow()

    init { refresh() }

    fun refresh() {
        val uid = userId ?: return
        _ui.update { it.copy(loading = true) }
        viewModelScope.launch {
            runCatching { repo.refresh(uid); repo.score(uid) }
                .onSuccess { score ->
                    _ui.update { it.copy(loading = false, score = score, error = null) }
                }
                .onFailure { t ->
                    _ui.update { it.copy(loading = false, error = t.message) }
                }
        }
    }

    fun remove(barcode: String) {
        val uid = userId ?: return
        viewModelScope.launch {
            runCatching { repo.remove(uid, barcode) }
        }
    }
}
