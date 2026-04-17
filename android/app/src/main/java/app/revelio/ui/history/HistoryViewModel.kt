package app.revelio.ui.history

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.revelio.data.db.ScanHistoryEntity
import app.revelio.data.repo.AuthRepository
import app.revelio.data.repo.ScanRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import javax.inject.Inject

@HiltViewModel
class HistoryViewModel @Inject constructor(
    scanRepo: ScanRepository,
    authRepo: AuthRepository,
) : ViewModel() {

    val history: StateFlow<List<ScanHistoryEntity>> = scanRepo
        .observeHistory(authRepo.cachedUser?.id)
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = emptyList(),
        )
}
