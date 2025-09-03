// ─────────────────────────────────────────────────────────────────────────────
// FILE: lib/routing/router.dart
// Purpose: Centralize routing; safe redirects; 4-tab bottom nav shell.
// Change: AppBar header appears ONLY on TestSwipeStackPage. Other shell pages
// (UserProfile, ChatList, ChatPage, ConfessionsFeed) keep the bottom nav but no header.
// Also: Confessions wired into router + replaces the placeholder "Matches" tab.
// Update: Enlarge header area (toolbar), logo, and action buttons (bell/filter)
// without altering other behavior/structure.

import 'package:bangher/features/confessions/confessions_feature.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/splash/splash_page.dart';
import '../features/onboarding/onboarding_page.dart';
import '../features/auth/login_page_widget.dart';
import '../features/profile/pages/create_or_complete_profile_page.dart';
import '../features/profile/pages/edit_profile_page.dart';
import '../features/profile/pages/user_profile_page.dart';
import '../features/swipe/pages/test_swipe_stack_page.dart';
import '../features/matches/chat_list_page.dart';
import '../features/matches/chat_page.dart';
import '../features/paywall/paywall_page.dart';
import '../filters/filter_matches_sheet.dart';
import 'go_router_refresh.dart';

// Reusable 4-tab nav
import '../widgets/app_bottom_nav.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final auth = Supabase.instance.client.auth;

  final refresh = GoRouterRefreshStream(auth.onAuthStateChange);
  ref.onDispose(refresh.dispose);

  String? redirect(_, GoRouterState state) {
    final session = auth.currentSession;
    final atLogin = state.matchedLocation == LoginPageWidget.routePath;
    final atSplash = state.matchedLocation == SplashPage.routePath;

    if (atSplash) return null;
    if (session == null) return atLogin ? null : LoginPageWidget.routePath;
    if (atLogin) return CreateOrCompleteProfilePage.routePath;
    return null;
  }

  return GoRouter(
    debugLogDiagnostics: kDebugMode,
    refreshListenable: refresh,
    initialLocation: SplashPage.routePath,
    routes: [
      GoRoute(
        path: SplashPage.routePath,
        name: SplashPage.routeName,
        builder: (_, __) => const SplashPage(),
      ),
      GoRoute(
        path: OnboardingPage.routePath,
        name: OnboardingPage.routeName,
        builder: (_, __) => const OnboardingPage(),
      ),
      GoRoute(
        path: LoginPageWidget.routePath,
        name: LoginPageWidget.routeName,
        builder: (_, __) => const LoginPageWidget(),
      ),
      GoRoute(
        path: CreateOrCompleteProfilePage.routePath,
        name: CreateOrCompleteProfilePage.routeName,
        builder: (_, __) => const CreateOrCompleteProfilePage(),
      ),
      GoRoute(
        path: EditProfilePage.routePath,
        name: EditProfilePage.routeName,
        builder: (_, __) => const EditProfilePage(),
      ),

      // Confessions: bottom nav (no header)
      GoRoute(
        name: ConfessionsFeedPage.routeName,
        path: ConfessionsFeedPage.routePath,
        builder: (context, state) => _AppScaffold(
          body: const ConfessionsFeedPage(),
          currentLocation: state.matchedLocation,
          showHeader: false,
        ),
      ),

      // Profile: bottom nav (no header)
      GoRoute(
        path: UserProfilePage.routePath,
        name: UserProfilePage.routeName,
        builder: (context, state) => _AppScaffold(
          body: const UserProfilePage(),
          currentLocation: state.matchedLocation,
          showHeader: false,
        ),
      ),

      // Swipe: bottom nav + header
      GoRoute(
        path: TestSwipeStackPage.routePath,
        name: TestSwipeStackPage.routeName,
        builder: (context, state) => _AppScaffold(
          body: const TestSwipeStackPage(),
          currentLocation: state.matchedLocation,
          showHeader: true, // ← header ONLY here
        ),
      ),

      // Chats list: bottom nav (no header)
      GoRoute(
        path: ChatListPage.routePath,
        name: ChatListPage.routeName,
        builder: (context, state) => _AppScaffold(
          body: const ChatListPage(),
          currentLocation: state.matchedLocation,
          showHeader: false,
        ),
      ),

      // Chat thread: bottom nav (no header)
      GoRoute(
        path: ChatPage.routePath,
        name: ChatPage.routeName,
        builder: (context, state) {
          final idStr = state.uri.queryParameters['id'];
          final matchId = int.tryParse(idStr ?? '') ?? 0;
          return _AppScaffold(
            body: ChatPage(matchId: matchId),
            currentLocation: state.matchedLocation,
            showHeader: false,
          );
        },
      ),

      GoRoute(
        path: PaywallPage.routePath,
        name: PaywallPage.routeName,
        builder: (_, __) => const PaywallPage(),
      ),
    ],
    redirect: redirect,
  );
});

/// ─────────────────────────────────────────────────────────────────────────────
/// Header sizing constants (kept local to this file for easy tuning)
const double _kHeaderHeight = 92; // taller top bar
const double _kHeaderLeadingWidth = 160; // more space for the logo
const double _kLogoMaxWidth = 140;
const double _kLogoMaxHeight = 64;
const double _kHeaderIconSize = 28; // larger action icons
const double _kHeaderTapTarget = 56; // accessible tap target

/// ─────────────────────────────────────────────────────────────────────────────
/// Shared shell with optional header (AppBar) + 4-tab bottom nav.
/// Header is enabled only when [showHeader] is true.
class _AppScaffold extends StatelessWidget {
  const _AppScaffold({
    required this.body,
    required this.currentLocation,
    this.showHeader = false,
  });

  final Widget body;
  final String currentLocation;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: showHeader
          ? AppBar(
              toolbarHeight: _kHeaderHeight,
              leadingWidth: _kHeaderLeadingWidth,
              leading: Padding(
                padding: const EdgeInsets.only(left: 12, top: 6, bottom: 6),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: _kLogoMaxWidth,
                    maxHeight: _kLogoMaxHeight,
                  ),
                  child: Image.asset(
                    'assets/images/Bangher_Logo.png',
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high, // crisper upscaling
                  ),
                ),
              ),
              actions: [
                _HeaderBell(count: 3, iconSize: _kHeaderIconSize),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Filters',
                  iconSize: _kHeaderIconSize,
                  constraints: const BoxConstraints(
                    minWidth: _kHeaderTapTarget,
                    minHeight: _kHeaderTapTarget,
                  ),
                  splashRadius: _kHeaderTapTarget / 2,
                  icon: const Icon(Icons.filter_list),
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      backgroundColor: Colors.transparent,
                      builder: (ctx) => const FilterMatchesSheet(),
                    );
                  },
                ),
                const SizedBox(width: 8),
              ],
            )
          : null,
      body: SafeArea(child: body),
      bottomNavigationBar: AppBottomNav(
        currentPath: currentLocation,
        items: const [
          NavItem(
            icon: Icons.explore_rounded,
            label: 'Discover',
            path: TestSwipeStackPage.routePath,
            selectedStartsWith: [TestSwipeStackPage.routePath],
          ),
          // Replaces placeholder Matches tab with Confessions
          NavItem(
            icon: Icons.auto_awesome, // fits the vibe of "Confess"
            label: 'Confess',
            path: ConfessionsFeedPage.routePath,
            selectedStartsWith: [ConfessionsFeedPage.routePath],
          ),
          NavItem(
            icon: Icons.chat_bubble_outline,
            label: 'Chats',
            path: ChatListPage.routePath,
            selectedStartsWith: [ChatListPage.routePath, ChatPage.routePath],
          ),
          NavItem(
            icon: Icons.person_outline,
            label: 'Profile',
            path: UserProfilePage.routePath,
            selectedStartsWith: [
              UserProfilePage.routePath,
              CreateOrCompleteProfilePage.routePath,
              EditProfilePage.routePath,
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderBell extends StatelessWidget {
  const _HeaderBell({
    required this.count,
    this.iconSize = _kHeaderIconSize,
  });

  final int count;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          iconSize: iconSize,
          splashRadius: _kHeaderTapTarget / 2,
          constraints: const BoxConstraints(
            minWidth: _kHeaderTapTarget,
            minHeight: _kHeaderTapTarget,
          ),
          icon: const Icon(Icons.notifications_none),
          onPressed: () {},
        ),
        if (count > 0)
          Positioned(
            right: 8,
            top: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ),
      ],
    );
  }
}
