package com.khush.movienight.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.khush.movienight.core.SoundSettings
import kotlin.math.abs
import kotlin.math.roundToInt

/** Boost Dialogue, Night Mode and Balance: in Settings and in the player, changing the sound as you listen. */
@Composable
fun SoundControls(modifier: Modifier = Modifier) {
    val preferences = rememberApp().preferences
    val sound by preferences.sound.collectAsState()
    Column(modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        ToggleRow("Boost Dialogue", "Lifts voices above music and effects.", sound.dialogueBoost) {
            preferences.setSound(sound.copy(dialogueBoost = it))
        }
        ToggleRow("Night Mode", "Evens out loud and quiet scenes, for watching late.", sound.nightMode) {
            preferences.setSound(sound.copy(nightMode = it))
        }
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Balance", style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
                Text(balanceLabel(sound.balance), style = MaterialTheme.typography.bodyMedium, color = Palette.muted)
            }
            // Ten steps either side, so the remote's Left and Right move it in sensible jumps.
            Slider(
                value = sound.balance.toFloat(), onValueChange = { preferences.setSound(sound.copy(balance = (it * 10).roundToInt() / 10.0)) },
                valueRange = -1f..1f, steps = 19,
                colors = SliderDefaults.colors(thumbColor = Palette.accent, activeTrackColor = Palette.accent),
            )
        }
    }
}

private fun balanceLabel(balance: Double): String = when {
    abs(balance) < 0.01 -> "Centre"
    balance < 0 -> "Left ${(abs(balance) * 100).roundToInt()}%"
    else -> "Right ${(balance * 100).roundToInt()}%"
}

@Composable
private fun ToggleRow(title: String, detail: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth().focusCard(RoundedCornerShape(12.dp)) { onChange(!checked) }.padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            Text(detail, style = MaterialTheme.typography.bodySmall, color = Palette.muted)
        }
        Switch(checked, null)
    }
}

/** True when any sound effect is on, for the player's Sound button. */
fun SoundSettings.isActive() = !isNeutral
