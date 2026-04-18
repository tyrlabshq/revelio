package app.revelio.ui.pantry

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.revelio.data.db.PantryItemEntity
import app.revelio.ui.theme.gradeColor

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PantryScreen(viewModel: PantryViewModel = hiltViewModel()) {
    val items by viewModel.items.collectAsStateWithLifecycle()
    val ui by viewModel.ui.collectAsStateWithLifecycle()

    Scaffold(topBar = { TopAppBar(title = { Text("Pantry") }) }) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {
            ui.score?.let { score ->
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.surfaceVariant,
                    ),
                    shape = RoundedCornerShape(12.dp),
                ) {
                    Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(
                            modifier = Modifier
                                .size(56.dp)
                                .clip(CircleShape)
                                .background(gradeColor(score.grade)),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                score.grade,
                                color = Color.White,
                                fontWeight = FontWeight.Bold,
                                style = MaterialTheme.typography.titleLarge,
                            )
                        }
                        Spacer(Modifier.size(12.dp))
                        Column {
                            Text(
                                "Household score: ${score.score} / 100",
                                style = MaterialTheme.typography.titleMedium,
                            )
                            Text(
                                "${score.cleanPct}% clean • ${score.avoidPct}% avoid",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }

            if (items.isEmpty()) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(
                        "Your pantry is empty. Scan products and tap \"Add to pantry\".",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(items, key = { it.id }) { item ->
                        PantryRow(item, onRemove = { viewModel.remove(item.barcode) })
                    }
                    item { Spacer(Modifier.height(16.dp)) }
                }
            }
        }
    }
}

@Composable
private fun PantryRow(item: PantryItemEntity, onRemove: () -> Unit) {
    Card(
        modifier = Modifier.padding(horizontal = 16.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        shape = RoundedCornerShape(10.dp),
    ) {
        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .background(gradeColor(item.grade)),
                contentAlignment = Alignment.Center,
            ) {
                Text(item.grade, color = Color.White, fontWeight = FontWeight.Bold)
            }
            Spacer(Modifier.size(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(item.productName, style = MaterialTheme.typography.titleMedium)
                item.brand?.let {
                    Text(
                        it,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            TextButton(onClick = onRemove) { Text("Remove") }
        }
    }
}
