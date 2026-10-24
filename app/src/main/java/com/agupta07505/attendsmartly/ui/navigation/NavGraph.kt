/*
 * AttendSmartly (2026)
 * © Animesh Gupta — github.com/agupta07505
 * Licensed under the GNU GPL v3 License
 * Do not remove or alter this notice. - Per GPL-3.0 Section 4 & Section 5
 */

package com.agupta07505.attendsmartly.ui.navigation

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.*
import androidx.navigation.navArgument
import com.agupta07505.attendsmartly.data.preferences.UserPreferences
import com.agupta07505.attendsmartly.ui.screens.analytics.AnalyticsScreen
import com.agupta07505.attendsmartly.ui.screens.analytics.AnalyticsViewModel
import com.agupta07505.attendsmartly.ui.screens.history.AttendanceHistoryScreen
import com.agupta07505.attendsmartly.ui.screens.history.HistoryViewModel
import com.agupta07505.attendsmartly.ui.screens.home.HomeScreen
import com.agupta07505.attendsmartly.ui.screens.home.HomeViewModel
import com.agupta07505.attendsmartly.ui.screens.onboarding.OnboardingScreen
import com.agupta07505.attendsmartly.ui.screens.onboarding.SetupScreen
import com.agupta07505.attendsmartly.ui.screens.settings.SettingsScreen
import com.agupta07505.attendsmartly.ui.screens.settings.SettingsViewModel
import com.agupta07505.attendsmartly.ui.screens.subjectdetails.SubjectDetailScreen
import com.agupta07505.attendsmartly.ui.screens.subjectdetails.SubjectDetailViewModel
import com.agupta07505.attendsmartly.ui.screens.subjects.SubjectsScreen
import com.agupta07505.attendsmartly.ui.screens.subjects.SubjectsViewModel
import com.agupta07505.attendsmartly.ui.screens.timetable.TimetableScreen
import com.agupta07505.attendsmartly.ui.screens.timetable.TimetableViewModel

@Composable
fun NavGraph(
    navController: NavHostController = rememberNavController(),
    userPreferences: UserPreferences,
    onCompleteOnboarding: () -> Unit
) {
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = navBackStackEntry?.destination?.route

    val showBottomBar = currentRoute in Screen.bottomNavItems.map { it.route }
    val initialRoute = remember { if (!userPreferences.onboardingCompleted) Screen.Onboarding.route else Screen.Home.route }

    fun navigateToTab(route: String) {
        if (currentRoute != route) {
            navController.navigate(route) {
                popUpTo(Screen.Home.route) {
                    saveState = true
                }
                launchSingleTop = true
                restoreState = true
            }
        }
    }

    Scaffold(
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        bottomBar = {
            if (showBottomBar) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Color.Transparent)
                        .padding(top = 4.dp, bottom = 8.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 16.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Screen.bottomNavItems.forEach { screen ->
                            val selected = currentRoute == screen.route
                            val buttonWidth by animateDpAsState(
                                targetValue = if (selected) 58.dp else 52.dp,
                                animationSpec = tween(220),
                                label = "nav-width-${screen.route}"
                            )
                            val iconScale by animateFloatAsState(
                                targetValue = if (selected) 1.12f else 1f,
                                animationSpec = spring(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessHigh),
                                label = "nav-icon-${screen.route}"
                            )
                            val itemColor by animateColorAsState(
                                targetValue = if (selected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surface,
                                animationSpec = tween(220),
                                label = "nav-color-${screen.route}"
                            )
                            val foreground = if (selected) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurfaceVariant

                            Box(
                                modifier = Modifier
                                    .size(width = buttonWidth, height = 52.dp)
                                    .shadow(elevation = if (selected) 8.dp else 4.dp, shape = RoundedCornerShape(18.dp))
                                    .clip(RoundedCornerShape(18.dp))
                                    .background(itemColor)
                                    .clickable { navigateToTab(screen.route) }
                                    .testTag("nav_item_${screen.route}"),
                                contentAlignment = Alignment.Center
                            ) {
                                screen.icon?.let {
                                    Icon(
                                        imageVector = it,
                                        contentDescription = screen.title,
                                        tint = foreground,
                                        modifier = Modifier
                                            .size(25.dp)
                                            .graphicsLayer { scaleX = iconScale; scaleY = iconScale }
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    ) { innerPadding ->
        NavHost(
            navController = navController,
            startDestination = initialRoute,
            modifier = Modifier.padding(bottom = innerPadding.calculateBottomPadding()),
            enterTransition = {
                slideInHorizontally(initialOffsetX = { it / 14 }, animationSpec = spring(dampingRatio = 0.78f, stiffness = 420f)) +
                    scaleIn(initialScale = 0.97f, animationSpec = spring(dampingRatio = 0.78f, stiffness = 420f)) +
                    fadeIn(animationSpec = tween(180))
            },
            exitTransition = {
                slideOutHorizontally(targetOffsetX = { -it / 20 }, animationSpec = tween(150)) +
                    scaleOut(targetScale = 0.99f, animationSpec = tween(150)) +
                    fadeOut(animationSpec = tween(140))
            },
            popEnterTransition = {
                slideInHorizontally(initialOffsetX = { -it / 14 }, animationSpec = spring(dampingRatio = 0.78f, stiffness = 420f)) +
                    scaleIn(initialScale = 0.97f, animationSpec = spring(dampingRatio = 0.78f, stiffness = 420f)) +
                    fadeIn(animationSpec = tween(180))
            },
            popExitTransition = {
                slideOutHorizontally(targetOffsetX = { it / 20 }, animationSpec = tween(150)) +
                    scaleOut(targetScale = 0.99f, animationSpec = tween(150)) +
                    fadeOut(animationSpec = tween(140))
            }
        ) {
            composable(Screen.Onboarding.route) {
                OnboardingScreen(
                    onFinishOnboarding = {
                        onCompleteOnboarding()
                        navController.navigate(Screen.Home.route) {
                            popUpTo(Screen.Onboarding.route) { inclusive = true }
                        }
                    },
                    onSkip = {
                        onCompleteOnboarding()
                        navController.navigate(Screen.Home.route) {
                            popUpTo(Screen.Onboarding.route) { inclusive = true }
                        }
                    }
                )
            }

            composable(Screen.Setup.route) {
                val settingsVm: SettingsViewModel = getViewModel { app -> SettingsViewModel(app.repository, app.userPreferencesRepository) }
                val subjectsVm: SubjectsViewModel = getViewModel { app -> SubjectsViewModel(app.repository, app.userPreferencesRepository) }
                val prefs by settingsVm.userPreferences.collectAsState()

                SetupScreen(
                    currentApiKey = prefs.geminiApiKey,
                    onSaveApiKey = { key -> settingsVm.updateGeminiApiKey(key) },
                    onSaveSetup = { targetPercent, startDate, endDate, firstSubject, loadDemo ->
                        settingsVm.updateDefaultTargetAttendance(targetPercent)
                        if (startDate.isNotBlank() && endDate.isNotBlank()) {
                            settingsVm.updateSemesterDates(startDate, endDate)
                        }
                        if (loadDemo) {
                            settingsVm.loadDemoData {}
                        }
                        firstSubject?.let { subjectsVm.addSubject(it) }
                        onCompleteOnboarding()
                        navController.navigate(Screen.Home.route) {
                            popUpTo(Screen.Setup.route) { inclusive = true }
                        }
                    },
                    onNavigateToTimetableOcr = {
                        onCompleteOnboarding()
                        navController.navigate(Screen.Timetable.route) {
                            popUpTo(Screen.Setup.route) { inclusive = true }
                        }
                    },
                    onSkipSetup = {
                        onCompleteOnboarding()
                        navController.navigate(Screen.Home.route) {
                            popUpTo(Screen.Setup.route) { inclusive = true }
                        }
                    }
                )
            }

            composable(Screen.Home.route) {
                val homeVm: HomeViewModel = getViewModel { app -> HomeViewModel(app.repository, app.userPreferencesRepository) }
                HomeScreen(
                    viewModel = homeVm,
                    onNavigateToAddSubject = { navigateToTab(Screen.Subjects.route) },
                    onNavigateToAddTimetable = { navigateToTab(Screen.Timetable.route) },
                    onNavigateToSettings = { navController.navigate(Screen.Settings.route) }
                )
            }

            composable(Screen.Timetable.route) {
                val timetableVm: TimetableViewModel = getViewModel { app -> TimetableViewModel(app.repository, app.userPreferencesRepository) }
                TimetableScreen(
                    viewModel = timetableVm,
                    onNavigateBack = {
                        if (!navController.popBackStack()) {
                            navigateToTab(Screen.Home.route)
                        }
                    }
                )
            }

            composable(Screen.Subjects.route) {
                val subjectsVm: SubjectsViewModel = getViewModel { app -> SubjectsViewModel(app.repository, app.userPreferencesRepository) }
                SubjectsScreen(
                    viewModel = subjectsVm,
                    onNavigateToSubjectDetail = { subId ->
                        navController.navigate(Screen.SubjectDetail.createRoute(subId))
                    },
                    onNavigateBack = {
                        if (!navController.popBackStack()) {
                            navigateToTab(Screen.Home.route)
                        }
                    }
                )
            }

            composable(
                route = Screen.SubjectDetail.route,
                arguments = listOf(navArgument("subjectId") { type = NavType.LongType })
            ) { backStackEntry ->
                val subjectId = backStackEntry.arguments?.getLong("subjectId") ?: 0L
                val detailVm: SubjectDetailViewModel = getViewModel { app -> SubjectDetailViewModel(app.repository, subjectId, app.userPreferencesRepository) }
                SubjectDetailScreen(
                    viewModel = detailVm,
                    onNavigateBack = { navController.popBackStack() }
                )
            }

            composable(Screen.Analytics.route) {
                val analyticsVm: AnalyticsViewModel = getViewModel { app -> AnalyticsViewModel(app.repository, app.userPreferencesRepository) }
                AnalyticsScreen(
                    viewModel = analyticsVm,
                    onNavigateToSubjectDetail = { subId ->
                        navController.navigate(Screen.SubjectDetail.createRoute(subId))
                    }
                )
            }

            composable(Screen.History.route) {
                val historyVm: HistoryViewModel = getViewModel { app -> HistoryViewModel(app.repository) }
                AttendanceHistoryScreen(viewModel = historyVm)
            }

            composable(Screen.Settings.route) {
                val settingsVm: SettingsViewModel = getViewModel { app -> SettingsViewModel(app.repository, app.userPreferencesRepository) }
                SettingsScreen(
                    viewModel = settingsVm,
                    onNavigateBack = { navController.popBackStack() }
                )
            }
        }
    }
}
