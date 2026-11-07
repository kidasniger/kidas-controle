package com.kidas.controle.ui.comments

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.expandVertically
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CommentsScreen(viewModel: CommentsViewModel, unansweredCountChanged: (Int) -> Unit = {}) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    var filter by rememberSaveable { mutableStateOf("unanswered") }
    var expandedId by rememberSaveable { mutableStateOf<String?>(null) }
    var replyText by rememberSaveable { mutableStateOf("") }
    val focusRequester = remember { FocusRequester() }
    val keyboard = LocalSoftwareKeyboardController.current

    LaunchedEffect(state.unansweredCount) { unansweredCountChanged(state.unansweredCount) }
    LaunchedEffect(expandedId) {
        if (expandedId != null) {
            kotlinx.coroutines.delay(180)
            runCatching { focusRequester.requestFocus() }
            keyboard?.show()
        }
    }

    val all = state.comments
    val unanswered = all.filter { !it.answered && !it.queued }
    val source = if (filter == "unanswered") unanswered else all
    val visible = source.take(40)

    Scaffold(
        snackbarHost = {},
        containerColor = MaterialTheme.colorScheme.background
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding).padding(horizontal = 18.dp),
            contentPadding = PaddingValues(top = 18.dp, bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text("Avis", style = MaterialTheme.typography.headlineMedium)
                        Text("Commentaires de ta Page Facebook", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    IconButton(onClick = { viewModel.refresh() }, enabled = !state.loading) {
                        Text("↻")
                    }
                }
                state.updatedAt?.let {
                    Text(
                        "Données du dernier audit : ${commentAuditAge(it)}",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = 8.dp)
                    )
                }
            }
            item {
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                    SegmentedButton(
                        selected = filter == "unanswered",
                        onClick = { filter = "unanswered"; expandedId = null; replyText = "" },
                        shape = SegmentedButtonDefaults.itemShape(0, 2)
                    ) { Text("Sans réponse (${unanswered.size})", maxLines = 1) }
                    SegmentedButton(
                        selected = filter == "all",
                        onClick = { filter = "all"; expandedId = null; replyText = "" },
                        shape = SegmentedButtonDefaults.itemShape(1, 2)
                    ) { Text("Tous (${all.size})", maxLines = 1) }
                }
            }
            if (state.loading && all.isEmpty()) {
                item { Box(Modifier.fillMaxWidth().padding(30.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() } }
            } else if (all.isEmpty()) {
                item {
                    ElevatedCard {
                        Column(
                            Modifier.fillMaxWidth().padding(22.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            Text("💬", style = MaterialTheme.typography.headlineLarge)
                            Text("Aucune donnée. Lance Surveiller depuis l'accueil.", style = MaterialTheme.typography.bodyLarge)
                            Button(onClick = { viewModel.runSurveiller() }, enabled = !state.loading) {
                                Text(if (state.loading) "Lancement…" else "Lancer Surveiller")
                            }
                        }
                    }
                }
            } else if (visible.isEmpty()) {
                item {
                    Text(
                        if (filter == "unanswered") "Aucun commentaire sans réponse." else "Aucun commentaire.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(vertical = 24.dp)
                    )
                }
            } else {
                if (source.size > 40) {
                    item {
                        Text("40 plus récents affichés", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                items(visible, key = { it.id }) { comment ->
                    val isExpanded = expandedId == comment.id
                    val status = when {
                        comment.queued -> "En file"
                        comment.answered -> "Répondu"
                        else -> "Sans réponse"
                    }
                    val statusColor by animateColorAsState(
                        targetValue = when (status) {
                            "Répondu" -> MaterialTheme.colorScheme.tertiary
                            "En file" -> MaterialTheme.colorScheme.primary
                            else -> MaterialTheme.colorScheme.error
                        },
                        label = "comment-status"
                    )
                    ElevatedCard(
                        modifier = Modifier
                            .fillMaxWidth()
                            .animateItem()
                            .pointerInput(comment.id) {
                                detectHorizontalDragGestures { _, amount ->
                                    if (amount < -18f && !comment.answered && !comment.queued) {
                                        expandedId = comment.id
                                    }
                                }
                            }
                    ) {
                        Column(Modifier.fillMaxWidth().padding(15.dp), verticalArrangement = Arrangement.spacedBy(9.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(comment.author, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                                Surface(color = statusColor.copy(alpha = 0.13f), shape = RoundedCornerShape(50)) {
                                    Text(status, color = statusColor, style = MaterialTheme.typography.labelMedium, modifier = Modifier.padding(horizontal = 10.dp, vertical = 5.dp))
                                }
                            }
                            Text(commentRelativeTime(comment.createdAt), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(comment.message, style = MaterialTheme.typography.bodyLarge)
                            Text(
                                comment.postExcerpt.replace('\n', ' '),
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            if (!comment.answered && !comment.queued) {
                                TextButton(onClick = {
                                    expandedId = if (isExpanded) null else comment.id
                                    if (isExpanded) replyText = ""
                                }) {
                                    Text(if (isExpanded) "Fermer la réponse" else "Répondre")
                                }
                                AnimatedVisibility(
                                    visible = isExpanded,
                                    enter = fadeIn() + expandVertically()
                                ) {
                                    Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
                                        OutlinedTextField(
                                            value = replyText,
                                            onValueChange = { replyText = it },
                                            modifier = Modifier.fillMaxWidth().focusRequester(focusRequester),
                                            label = { Text("Ta réponse") },
                                            minLines = 2,
                                            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
                                            keyboardActions = KeyboardActions(onSend = {
                                                if (replyText.isNotBlank()) {
                                                    viewModel.sendReply(comment.id, replyText)
                                                    expandedId = null
                                                    replyText = ""
                                                    keyboard?.hide()
                                                }
                                            })
                                        )
                                        Button(
                                            onClick = {
                                                viewModel.sendReply(comment.id, replyText)
                                                expandedId = null
                                                replyText = ""
                                                keyboard?.hide()
                                            },
                                            enabled = replyText.isNotBlank() && comment.id !in state.sendingIds,
                                            modifier = Modifier.align(Alignment.End)
                                        ) {
                                            if (comment.id in state.sendingIds) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                                            else Text("Envoyer")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            state.error?.let { error ->
                item {
                    Text(error, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                }
            }
        }
    }
}
