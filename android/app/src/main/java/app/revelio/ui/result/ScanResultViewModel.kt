package app.revelio.ui.result

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.revelio.data.repo.AuthRepository
import app.revelio.data.repo.ScanRepository
import app.revelio.domain.AlternativeProduct
import app.revelio.domain.ScanResult
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class ScanResultUiState(
    val loading: Boolean = true,
    val result: ScanResult? = null,
    val alternatives: List<AlternativeProduct> = emptyList(),
    val error: String? = null,
)

@HiltViewModel
class ScanResultViewModel @Inject constructor(
    private val scanRepo: ScanRepository,
    private val authRepo: AuthRepository,
) : ViewModel() {

    private val _state = MutableStateFlow(ScanResultUiState())
    val state: StateFlow<ScanResultUiState> = _state.asStateFlow()

    fun load(barcode: String) {
        _state.update { it.copy(loading = true, error = null) }
        viewModelScope.launch {
            runCatching { scanRepo.scan(barcode, authRepo.cachedUser?.id) }
                .onSuccess { result ->
                    _state.update { it.copy(loading = false, result = result) }
                }
                .onFailure { t ->
                    _state.update {
                        it.copy(loading = false, error = t.message ?: "Scan failed")
                    }
                }
        }
    }

    fun loadAlternatives(barcode: String) {
        viewModelScope.launch {
            runCatching { scanRepo.alternatives(barcode) }
                .onSuccess { alts -> _state.update { it.copy(alternatives = alts) } }
        }
    }
}
