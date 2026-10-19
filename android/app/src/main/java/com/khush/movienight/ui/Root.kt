package com.khush.movienight.ui

import android.net.Uri
import androidx.compose.foundation.Image
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Movie
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Tv
import androidx.compose.material.icons.outlined.VideoLibrary
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.focusProperties
import androidx.compose.foundation.focusGroup
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.khush.movienight.MovieNightApp
import com.khush.movienight.R
import com.khush.movienight.core.ContentKind
import com.khush.movienight.data.MediaItem
import com.khush.movienight.playback.PlayerScreen

@Composable
fun rememberApp(): MovieNightApp = LocalContext.current.applicationContext as MovieNightApp

enum class Tab(val route: String, val label: String, val icon: ImageVector) {
    HOME("home", "Home", Icons.Outlined.Home),
    FILMS("films", "Films", Icons.Outlined.Movie),
    TV_SHOWS("tv", "TV Shows", Icons.Outlined.Tv),
    HOME_VIDEOS("homevideos", "Home Videos", Icons.Outlined.VideoLibrary),
    SETTINGS("settings", "Settings", Icons.Outlined.Settings),
}

/** Routes and how to get to them. */
class Navigator(val controller: NavHostController) {
    fun open(item: MediaItem) = controller.navigate("detail/${Uri.encode(item.key)}")
    fun openShow(name: String) = controller.navigate("show/${Uri.encode(name)}")
    /** [from] null resumes where you left off (unless Always Watch from Beginning is on); 0 starts over. */
    fun play(item: MediaItem, from: Double? = null) = controller.navigate("player/${Uri.encode(item.key)}?start=${from ?: -1.0}")
    fun sources() = controller.navigate("sources")
    fun back() = controller.popBackStack()
}

@Composable
fun MovieNightRoot() {
    val app = rememberApp()
    val items by app.store.items.collectAsState()
    val playIntro by app.preferences.playIntro.collectAsState()
    var showIntro by remember { mutableStateOf(playIntro) }
    val controller = rememberNavController()
    val navigator = remember(controller) { Navigator(controller) }
    val entry by controller.currentBackStackEntryAsState()
    val route = entry?.destination?.route

    // A section appears once there's something in it.
    val kinds = items.orEmpty().map { it.contentKind }.toSet()
    val tabs = Tab.entries.filter {
        when (it) {
            Tab.FILMS -> ContentKind.FILM in kinds
            Tab.TV_SHOWS -> ContentKind.EPISODE in kinds
            Tab.HOME_VIDEOS -> ContentKind.HOME_VIDEO in kinds
            else -> true
        }
    }
    val current = Tab.entries.firstOrNull { it.route == route }
    val showChrome = route?.startsWith("player") != true
    val select: (Tab) -> Unit = { tab ->
        controller.navigate(tab.route) {
            popUpTo(Tab.HOME.route) { saveState = true }
            launchSingleTop = true
            restoreState = true
        }
    }

    androidx.compose.material3.Surface(Modifier.fillMaxSize(), color = Palette.ink, contentColor = Palette.text) { Box(Modifier.fillMaxSize()) {
        when (LocalFormFactor.current) {
            FormFactor.PHONE -> Column(Modifier.fillMaxSize()) {
                Box(Modifier.weight(1f)) { Routes(navigator) }
                if (showChrome) {
                    NavigationBar(containerColor = Palette.surface) {
                        tabs.forEach { tab ->
                            NavigationBarItem(selected = current == tab, onClick = { select(tab) },
                                icon = { Icon(tab.icon, null) }, label = { Text(tab.label, maxLines = 1) })
                        }
                    }
                }
            }
            FormFactor.TABLET -> Row(Modifier.fillMaxSize()) {
                if (showChrome) {
                    NavigationRail(containerColor = Palette.surface, header = {
                        Image(painterResource(R.drawable.ic_launcher_art), "Movie Night", Modifier.padding(vertical = 12.dp).width(40.dp))
                    }) {
                        Spacer(Modifier.height(12.dp))
                        tabs.forEach { tab ->
                            NavigationRailItem(selected = current == tab, onClick = { select(tab) },
                                icon = { Icon(tab.icon, null) }, label = { Text(tab.label, maxLines = 1) })
                        }
                    }
                }
                Box(Modifier.weight(1f)) { Routes(navigator) }
            }
            // TV: tabs along the top like the Apple TV app; the remote moves up into them from any page.
            FormFactor.TV -> Box(Modifier.fillMaxSize()) {
                // Only Up leaves a page for the tabs; Left, Right and Down at the edge of a page stay put.
                Box(Modifier.fillMaxSize().focusProperties {
                    onExit = { if (requestedFocusDirection != androidx.compose.ui.focus.FocusDirection.Up) cancelFocusChange() }
                }.focusGroup()) { Routes(navigator) }
                if (showChrome && current != null) {
                    Row(
                        Modifier.fillMaxWidth()
                            .background(androidx.compose.ui.graphics.Brush.verticalGradient(listOf(Palette.ink.copy(alpha = 0.85f), Color.Transparent)))
                            .padding(horizontal = 48.dp, vertical = 18.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Image(painterResource(R.drawable.logo_horizontal), "Movie Night", Modifier.height(26.dp))
                        Spacer(Modifier.width(24.dp))
                        tabs.forEach { tab ->
                            val selected = current == tab
                            TvTab(tab.label, selected) { select(tab) }
                        }
                    }
                }
            }
        }
        if (showIntro) StartupIntro { showIntro = false }
    } }
}

@Composable
private fun Routes(navigator: Navigator) {
    NavHost(navigator.controller, startDestination = Tab.HOME.route) {
        composable(Tab.HOME.route) { HomeScreen(navigator) }
        composable(Tab.FILMS.route) { FilmsScreen(navigator) }
        composable(Tab.TV_SHOWS.route) { TvShowsScreen(navigator) }
        composable(Tab.HOME_VIDEOS.route) { HomeVideosScreen(navigator) }
        composable(Tab.SETTINGS.route) { SettingsScreen(navigator) }
        composable("sources") { SourcesScreen(navigator) }
        composable("detail/{key}", listOf(navArgument("key") { type = NavType.StringType })) {
            DetailScreen(Uri.decode(it.arguments?.getString("key").orEmpty()), navigator)
        }
        composable("show/{name}", listOf(navArgument("name") { type = NavType.StringType })) {
            ShowScreen(Uri.decode(it.arguments?.getString("name").orEmpty()), navigator)
        }
        composable(
            "player/{key}?start={start}",
            listOf(navArgument("key") { type = NavType.StringType }, navArgument("start") { type = NavType.FloatType; defaultValue = -1f }),
        ) {
            val start = it.arguments?.getFloat("start")?.takeIf { value -> value >= 0 }?.toDouble()
            PlayerScreen(Uri.decode(it.arguments?.getString("key").orEmpty()), start, navigator)
        }
    }
}

@Composable
private fun TvTab(label: String, selected: Boolean, onSelect: () -> Unit) {
    val interaction = rememberCardInteraction()
    val focused by interaction.source.collectIsFocusedAsState()
    Text(
        label,
        style = MaterialTheme.typography.titleMedium,
        fontWeight = if (selected || focused) FontWeight.Bold else FontWeight.Medium,
        color = if (focused) Color.Black else Palette.text,
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(when { focused -> Color.White; selected -> Color.White.copy(alpha = 0.2f); else -> Color.Transparent })
            .cardClick(interaction, onClick = onSelect)
            .padding(horizontal = 18.dp, vertical = 8.dp),
    )
}
