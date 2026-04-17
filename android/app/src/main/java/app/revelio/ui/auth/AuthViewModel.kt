package app.revelio.ui.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.revelio.data.repo.AuthRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

data class AuthUiState(
    val phone: String = "",
    val code: String = "",
    val isLoading: Boolean = false,
    val error: String? = null,
    val otpSent: Boolean = false,
    val verified: Boolean = false,
)

@HiltViewModel
class AuthViewModel @Inject constructor(
    private val repo: AuthRepository,
) : ViewModel() {

    private val _state = MutableStateFlow(AuthUiState())
    val state: StateFlow<AuthUiState> = _state.asStateFlow()

    fun onPhoneChanged(phone: String) = _state.update { it.copy(phone = phone) }
    fun onCodeChanged(code: String) = _state.update { it.copy(code = code, error = null) }

    fun requestOtp() {
        val phone = _state.value.phone.trim()
        if (phone.isBlank()) {
            _state.update { it.copy(error = "Enter a phone number") }
            return
        }
        _state.update { it.copy(isLoading = true, error = null) }
        viewModelScope.launch {
            runCatching { repo.requestOtp(phone) }
                .onSuccess { _state.update { it.copy(isLoading = false, otpSent = true) } }
                .onFailure { t ->
                    _state.update { it.copy(isLoading = false, error = t.message ?: "Failed to send OTP") }
                }
        }
    }

    fun verifyOtp(phone: String) {
        val code = _state.value.code.trim()
        if (code.length != 6) {
            _state.update { it.copy(error = "6-digit code required") }
            return
        }
        _state.update { it.copy(isLoading = true, error = null) }
        viewModelScope.launch {
            runCatching { repo.verifyOtp(phone, code) }
                .onSuccess { _state.update { it.copy(isLoading = false, verified = true) } }
                .onFailure { t ->
                    _state.update { it.copy(isLoading = false, error = t.message ?: "Invalid code") }
                }
        }
    }
}
