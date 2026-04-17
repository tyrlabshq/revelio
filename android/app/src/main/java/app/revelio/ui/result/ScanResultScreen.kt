package app.revelio.ui.result

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.revelio.domain.IngredientFlag
import app.revelio.domain.ScanResult
import app.revelio.ui.theme.gradeColor

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScanResultScreen(
    barcode: String,
    onBack: () -> Unit,
    viewModel: ScanResultViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()

    LaunchedEffect(barcode) {
        viewModel.load(barcode)
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Scan result") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        when {
            state.loading -> LoadingView(padding)
            state.error != null -> ErrorView(padding, state.error!!)
            state.result != null -> ResultView(
                padding = padding,
                result = state.result!!,
                onShowAlternatives = { viewModel.loadAlternatives(barcode) },
                alternativesCount = state.alternatives.size,
            )
        }
    }
}

@Composable
private fun LoadingView(padding: PaddingValues) {
    Box(
        modifier = Modifier.fillMaxSize().padding(padding),
        contentAlignment = Alignment.Center,
    ) {
        CircularProgressIndicator()
    }
}

@Composable
private fun ErrorView(padding: PaddingValues, message: String) {
    Box(
        modifier = Modifier.fillMaxSize().padding(padding).padding(24.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(message, color = MaterialTheme.colorScheme.error)
    }
}

@Composable
private fun ResultView(
    padding: PaddingValues,
    result: ScanResult,
    onShowAlternatives: () -> Unit,
    alternativesCount: Int,
) {
    LazyColumn(
        contentPadding = padding,
        modifier = Modifier.fillMaxSize().padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item { Spacer(Modifier.height(8.dp)) }
        item { GradeHeader(result = result) }
        item { ProductHeader(result = result) }
        item {
            OutlinedButton(onClick = onShowAlternatives) {
                Text(
                    if (alternativesCount > 0) {
                        "Showing $alternativesCount alternatives"
                    } else {
                        "Show cleaner alternatives"
                    }
                )
            }
        }
        item {
            Text(
                "Flags (${result.flags.size})",
                style = MaterialTheme.typography.titleMedium,
            )
        }
        items(result.flags) { flag -> FlagRow(flag) }
        item {
            Text(
                "Ingredients",
                style = MaterialTheme.typography.titleMedium,
            )
        }
        items(result.ingredients) { name ->
            Text(name, style = MaterialTheme.typography.bodyMedium)
        }
        item { Spacer(Modifier.height(24.dp)) }
    }
}

@Composable
private fun GradeHeader(result: ScanResult) {
    val score = if (result.personalizedScore > 0) result.personalizedScore else result.baseScore
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Box(
            modifier = Modifier
                .size(80.dp)
                .clip(CircleShape)
                .background(gradeColor(result.grade)),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                result.grade,
                color = Color.White,
                fontWeight = FontWeight.Bold,
                style = MaterialTheme.typography.displayLarge,
            )
        }
        Spacer(Modifier.height(0.dp))
        Column(modifier = Modifier.padding(start = 16.dp)) {
            Text("Score: $score / 100", style = MaterialTheme.typography.titleMedium)
            Text(
                "${result.flags.size} flagged ingredients",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun ProductHeader(result: ScanResult) {
    Card(
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
        shape = RoundedCornerShape(12.dp),
    ) {
        Column(Modifier.padding(16.dp)) {
            Text(result.productName, style = MaterialTheme.typography.titleMedium)
            result.brand?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Text(
                result.category.uppercase(),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun FlagRow(flag: IngredientFlag) {
    val severityColor = when (flag.severity) {
        3 -> gradeColor("F")
        2 -> gradeColor("D")
        1 -> gradeColor("C")
        else -> gradeColor("A")
    }
    Card(
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(10.dp),
    ) {
        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier
                    .size(10.dp)
                    .clip(CircleShape)
                    .background(severityColor),
            )
            Spacer(Modifier.size(12.dp))
            Column {
                Text(flag.ingredient, style = MaterialTheme.typography.titleMedium)
                Text(
                    flag.reason,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}
