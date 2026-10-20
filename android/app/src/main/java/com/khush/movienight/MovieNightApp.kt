package com.khush.movienight

import android.app.Application
import android.content.Context
import com.khush.movienight.core.SoundSettings
import com.khush.movienight.data.LibraryDatabase
import com.khush.movienight.library.LibraryStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class MovieNightApp : Application() {
    lateinit var store: LibraryStore
        private set
    lateinit var preferences: Preferences
        private set

    override fun onCreate() {
        super.onCreate()
        store = LibraryStore(this, LibraryDatabase.open(this).dao())
        preferences = Preferences(this)
    }
}

/** Small settings, kept on this device. */
class Preferences(context: Context) {
    private val prefs = context.getSharedPreferences("settings", Context.MODE_PRIVATE)

    private val _startFromBeginning = MutableStateFlow(prefs.getBoolean(START_FROM_BEGINNING, false))
    /** "Always Watch from Beginning": ignore saved positions. */
    val startFromBeginning: StateFlow<Boolean> = _startFromBeginning.asStateFlow()

    fun setStartFromBeginning(value: Boolean) {
        prefs.edit().putBoolean(START_FROM_BEGINNING, value).apply()
        _startFromBeginning.value = value
    }

    private val _playIntro = MutableStateFlow(prefs.getBoolean(PLAY_INTRO, true))
    val playIntro: StateFlow<Boolean> = _playIntro.asStateFlow()

    fun setPlayIntro(value: Boolean) {
        prefs.edit().putBoolean(PLAY_INTRO, value).apply()
        _playIntro.value = value
    }

    private val _sound = MutableStateFlow(SoundSettings(
        dialogueBoost = prefs.getBoolean(DIALOGUE_BOOST, false),
        nightMode = prefs.getBoolean(NIGHT_MODE, false),
        balance = prefs.getFloat(BALANCE, 0f).toDouble(),
    ))
    /** Boost Dialogue, Night Mode and Balance. Read by the player on every audio buffer, so changes are heard at once. */
    val sound: StateFlow<SoundSettings> = _sound.asStateFlow()

    fun setSound(value: SoundSettings) {
        prefs.edit().putBoolean(DIALOGUE_BOOST, value.dialogueBoost).putBoolean(NIGHT_MODE, value.nightMode)
            .putFloat(BALANCE, value.balance.toFloat()).apply()
        _sound.value = value
    }

    private companion object {
        const val START_FROM_BEGINNING = "startFromBeginning"
        const val PLAY_INTRO = "playIntro"
        const val DIALOGUE_BOOST = "dialogueBoost"
        const val NIGHT_MODE = "nightMode"
        const val BALANCE = "audioBalance"
    }
}
