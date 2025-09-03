// =========================
// FIXED FILE: lib/features/swipe/pages/test_swipe_stack_page.dart
// =========================
// Hero-expanding full profile + visuals
// - 9:16 top-aligned card (fills screen nicely).
// - Star button + UP swipe open ViewProfilePage with Hero animation.
// - Undo is single-level; after undo the button greys out instantly.
// - Image warmup for top card for snappier feel.
// - Visual-only changes; business logic preserved (except UP no longer likes).

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:swipable_stack/swipable_stack.dart';

// Loader page (pure Flutter)
import '../../matches/pages/finding_nearby_matches_page.dart';
// Public profile page (for expanded view with the desired visual style)
import '../../profile/pages/view_profile_page.dart';

class TestSwipeStackPage extends StatefulWidget {
  const TestSwipeStackPage({super.key});

  static const String routeName = 'SwipePage';
  static const String routePath = '/swipe';

  @override
  State<TestSwipeStackPage> createState() => _TestSwipeStackPageState();
}

class _TestSwipeStackPageState extends State<TestSwipeStackPage>
    with TickerProviderStateMixin {
  // ─────────────────────────────── Constants
  static const _rpcGetMatches = 'get_potential_matches';
  static const _rpcHandleSwipe = 'handle_swipe';
  static const _presenceChannel = 'Online';
  static const _rpcBatch = 16;
  static const _minTopUp = 3;

  // ─────────────────────────────── Services
  final SupabaseClient _supa = Supabase.instance.client;
  final SwipableStackController _stack = SwipableStackController();

  // ─────────────────────────────── State
  final List<Map<String, dynamic>> _cards = <Map<String, dynamic>>[];
  final Map<int, int> _photoIndex = <int, int>{};

  // swipe bookkeeping (guards)
  final Set<String> _inFlight = <String>{};
  final Set<String> _handled = <String>{};
  final List<_SwipeEvent> _history = <_SwipeEvent>[];
  final Set<String> _swipedIds = <String>{};

  // Presence
  RealtimeChannel? _presence;
  final Set<String> _onlineUserIds = <String>{};

  // UI state
  bool _fetching = false;
  bool _online = true;

  // Show loader page logic
  bool _initializing = true; // blocks empty-state UI until first load finishes
  bool _exhausted = false;   // true when a load returns 0 new cards
  bool _loaderVisible = false;

  // Prefs (minimal)
  String _prefGender = 'F';
  int _prefAgeMin = 18;
  int _prefAgeMax = 60;
  double _prefRadiusKm = 50.0;

  // Connectivity
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  // Fallback loader state
  bool _preferDirect = false;
  int _directOffset = 0;
  static const int _directLimit = 60;

  // Bottom bar button scales
  double _scaleUndo = 1, _scaleNope = 1, _scaleStar = 1, _scaleLike = 1, _scaleBoost = 1;

  // latest measured card size so we can size/position the bottom bar precisely
  double? _lastCardW;
  double? _lastCardH;

  // Loader avatar (my first profile photo)
  String? _myPhoto;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _ensureConnectivity();
    _listenConnectivity();
    await _startPresence();
    await _loadMyPhoto();              // avatar for loader
    _showLoader();                     // show loader immediately for first fetch
    await _loadPreferences();
    await _loadBatch();                // sets _exhausted when 0 added
    _hideLoader();
    if (mounted) {
      setState(() {
        _initializing = false;
      });
    }
    _warmTopCard();
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _presence?.unsubscribe();
    _stack.dispose();
    super.dispose();
  }

  // ───────────────────────────── Loader page control
  void _showLoader() {
    if (_loaderVisible || !mounted) return;
    _loaderVisible = true;
    final route = _FullscreenLoaderRoute(
      child: FindingNearbyMatchesPage(
        profileImageUrl: _myPhoto,
        backgroundAsset: 'assets/images/Earth Picture.png',
        message: 'Finding people near you ...',
      ),
    );
    unawaited(Navigator.of(context, rootNavigator: true).push(route).then((_) {
      _loaderVisible = false;
    }));
  }

  void _hideLoader() {
    if (!_loaderVisible || !mounted) return;
    Navigator.of(context, rootNavigator: true).maybePop();
    _loaderVisible = false;
  }

  // ───────────────────────────── Connectivity
  void _listenConnectivity() {
    _connSub = Connectivity().onConnectivityChanged.listen((_) async {
      final ok = await _ensureConnectivity();
      if (!ok && mounted) setState(() => _online = false);
    });
  }

  Future<bool> _ensureConnectivity() async {
    try {
      final result = await Connectivity().checkConnectivity();
      if (result.contains(ConnectivityResult.none)) {
        if (mounted) setState(() => _online = false);
        return false;
      }
      if (!kIsWeb) {
        final sw = Stopwatch()..start();
        final socket = await Socket.connect('8.8.8.8', 53,
            timeout: const Duration(milliseconds: 900));
        socket.destroy();
        if (sw.elapsedMilliseconds < 3000) {
          if (mounted) setState(() => _online = true);
          return true;
        }
      }
      if (mounted) setState(() => _online = true);
      return true;
    } catch (_) {
      if (mounted) setState(() => _online = false);
      return false;
    }
  }

  // ───────────────────────────── Presence (v2 API)
  Future<void> _startPresence() async {
    final me = _supa.auth.currentUser?.id;
    if (me == null) return;

    await _presence?.unsubscribe();
    final ch = _supa.channel(_presenceChannel,
        opts: const RealtimeChannelConfig(self: true));

    ch
        .onPresenceSync((_) {
          final states = ch.presenceState();
          _onlineUserIds
            ..clear()
            ..addAll(states
                .expand((s) => s.presences)
                .map((p) => p.payload['user_id']?.toString())
                .whereType<String>());
          if (mounted) setState(() {});
        })
        .onPresenceJoin((payload) {
          for (final p in payload.newPresences) {
            final id = p.payload['user_id']?.toString();
            if (id != null) _onlineUserIds.add(id);
          }
          if (mounted) setState(() {});
        })
        .onPresenceLeave((payload) {
          for (final p in payload.leftPresences) {
            final id = p.payload['user_id']?.toString();
            if (id != null) _onlineUserIds.remove(id);
          }
          if (mounted) setState(() {});
        })
        .subscribe((status, error) async {
          if (status == RealtimeSubscribeStatus.subscribed) {
            await ch.track({
              'user_id': me,
              'online_at': DateTime.now().toUtc().toIso8601String(),
            });
          }
        });

    _presence = ch;
  }

  // ───────────────────────────── My avatar (for loader)
  Future<void> _loadMyPhoto() async {
    try {
      final me = _supa.auth.currentUser?.id;
      if (me == null) return;
      final row = await _supa
          .from('profiles')
          .select('profile_pictures')
          .eq('user_id', me)
          .maybeSingle();
      final pics = (row?['profile_pictures'] as List?)
              ?.map((e) => e?.toString() ?? '')
              .where((s) => s.isNotEmpty)
              .toList() ??
          const <String>[];
      if (pics.isNotEmpty && mounted) {
        setState(() => _myPhoto = pics.first);
      }
    } catch (e) {
      debugPrint('Load my photo error: $e');
    }
  }

  // ───────────────────────────── Preferences
  Future<void> _loadPreferences() async {
    try {
      final me = _supa.auth.currentUser?.id;
      if (me == null) return;
      final row = await _supa
          .from('preferences')
          .select('interested_in_gender, age_min, age_max, distance_radius')
          .eq('user_id', me)
          .maybeSingle();
      if (row != null) {
        setState(() {
          _prefGender = (row['interested_in_gender'] ?? _prefGender).toString();
          _prefAgeMin = (row['age_min'] ?? _prefAgeMin) as int;
          _prefAgeMax = (row['age_max'] ?? _prefAgeMax) as int;
          _prefRadiusKm = (row['distance_radius'] ?? _prefRadiusKm).toDouble();
        });
      }
    } catch (e) {
      debugPrint('Prefs load error: $e');
    }
  }

  // ───────────────────────────── Data Loading (RPC → direct fallback)
  Future<void> _loadBatch() async {
    if (_fetching) return;

    final bool showForTopUp = _cards.isNotEmpty;
    setState(() => _fetching = true);
    if (showForTopUp) _showLoader();

    int added = 0;
    try {
      if (!_preferDirect) {
        added = await _loadBatchRpc();
      }
      if (added == 0) {
        _preferDirect = true;
        added = await _loadBatchDirect();
      }
    } finally {
      if (mounted) {
        setState(() {
          _exhausted = (_cards.isEmpty && added == 0);
        });
      }
      if (showForTopUp) _hideLoader();
      if (mounted) setState(() => _fetching = false);
      _warmTopCard();
    }
  }

  Future<int> _loadBatchRpc() async {
    try {
      final me = _supa.auth.currentUser?.id;
      if (me == null) return 0;

      final res = await _supa.rpc(_rpcGetMatches, params: {
        'user_id_arg': me,
        'gender_arg': _prefGender,
        'radius_arg': _prefRadiusKm,
        'age_min_arg': _prefAgeMin,
        'age_max_arg': _prefAgeMax,
        'limit_arg': _rpcBatch,
        'offset_arg': 0,
      });

      final list = (res as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          <Map<String, dynamic>>[];

      return _mergeIncoming(list,
          idKey: 'potential_match_id',
          photosKey: 'photos',
          distanceKey: 'distance');
    } catch (e) {
      debugPrint('RPC load error → fallback: $e');
      return 0;
    }
  }

  Future<int> _loadBatchDirect() async {
    try {
      final me = _supa.auth.currentUser?.id;
      if (me == null) return 0;

      final already = await _alreadySwiped(me);

      final rows = await _supa
          .from('profiles')
          .select(
              'user_id, name, profile_pictures, current_city, bio, age, is_online, last_seen')
          .neq('user_id', me)
          .range(_directOffset, _directOffset + _directLimit - 1);

      _directOffset += _directLimit;

      final mapped = (rows as List).cast<Map<String, dynamic>>().map((row) {
        final photos = (row['profile_pictures'] is List)
            ? (row['profile_pictures'] as List)
                .map((e) => e?.toString() ?? '')
                .where((s) => s.isNotEmpty)
                .toList()
            : const <String>[];
        return {
          'potential_match_id': row['user_id']?.toString(),
          'photos': photos,
          'name': (row['name'] ?? 'Someone').toString(),
          'age': (row['age'] is int)
              ? row['age']
              : int.tryParse('${row['age']}') ?? 0,
          'bio': (row['bio'] ?? '').toString(),
          'is_online': row['is_online'] == true,
          'last_seen': row['last_seen'],
          'distance': (row['current_city'] ?? '').toString(),
        };
      }).where((m) {
        final id = m['potential_match_id']?.toString();
        return id != null && !already.contains(id);
      }).toList(growable: false);

      return _mergeIncoming(mapped,
          idKey: 'potential_match_id',
          photosKey: 'photos',
          distanceKey: 'distance');
    } catch (e) {
      debugPrint('Direct load error: $e');
      return 0;
    }
  }

  int _mergeIncoming(
    List<Map<String, dynamic>> rows, {
    required String idKey,
    required String photosKey,
    required String distanceKey,
  }) {
    if (rows.isEmpty) return 0;
    final existing =
        _cards.map((e) => e[idKey]?.toString()).whereType<String>().toSet();
    final filtered = rows.where((m) {
      final id = m[idKey]?.toString();
      return id != null && !_swipedIds.contains(id) && !existing.contains(id);
    }).map((m) {
      final photos = (m[photosKey] is List)
          ? (m[photosKey] as List)
              .map((e) => e?.toString() ?? '')
              .where((s) => s.isNotEmpty)
              .toList()
          : const <String>[];
      return {...m, photosKey: photos};
    }).toList();
    if (filtered.isEmpty) return 0;
    setState(() => _cards.addAll(filtered));
    return filtered.length;
  }

  Future<List<String>> _alreadySwiped(String me) async {
    try {
      final rows = await _supa
          .from('swipes')
          .select('swipee_id')
          .eq('swiper_id', me)
          .eq('status', 'active');
      return (rows as List)
          .map((e) => (e as Map<String, dynamic>)['swipee_id']?.toString())
          .whereType<String>()
          .toList(growable: false);
    } catch (e) {
      debugPrint('already swiped error: $e');
      return const [];
    }
  }

  // ───────────────────────────── Swipes
  Future<void> _recordSwipe({required String swipeeId, required bool liked}) async {
    if (_inFlight.contains(swipeeId)) return;
    _inFlight.add(swipeeId);
    try {
      try {
        await _supa.rpc(_rpcHandleSwipe, params: {
          'swiper_id_arg': _supa.auth.currentUser?.id,
          'swipee_id_arg': swipeeId,
          'liked_arg': liked,
        });
      } catch (_) {
        await _supa.from('swipes').upsert(
          {
            'swiper_id': _supa.auth.currentUser?.id,
            'swipee_id': swipeeId,
            'liked': liked,
            'status': 'active',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          onConflict: 'swiper_id,swipee_id',
        );
      }
      _swipedIds.add(swipeeId);
    } catch (e) {
      debugPrint('recordSwipe error: $e');
    } finally {
      _inFlight.remove(swipeeId);
    }
  }

  Future<void> _undoLast() async {
    if (_history.isEmpty) return;
    final last = _history.removeLast();
    final me = _supa.auth.currentUser?.id;
    if (me == null) return;

    if (_stack.canRewind) {
      try {
        _stack.rewind();
      } catch (e) {
        debugPrint('rewind err: $e');
      }
    }

    _handled.remove('${last.index}|${last.swipeeId}');
    _swipedIds.remove(last.swipeeId);

    // Only single-level undo: clear history so the button greys out
    _history.clear();

    unawaited(
      _supa
          .from('swipes')
          .delete()
          .match({'swiper_id': me, 'swipee_id': last.swipeeId}).catchError((e) {
        debugPrint('undo delete error: $e');
      }),
    );

    HapticFeedback.selectionClick();
    setState(() {});
  }

  // ───────────────────────────── UI helpers

  void _openViewProfile(int index) {
    if (index < 0 || index >= _cards.length) return;
    final data = _cards[index];
    final userId = data['potential_match_id']?.toString();
    if (userId == null || userId.isEmpty) return;

    // Warm first photo to make hero start crisp
    final photos = (data['photos'] as List?)?.cast<String>() ?? const <String>[];
    if (photos.isNotEmpty) {
      unawaited(precacheImage(CachedNetworkImageProvider(photos.first), context));
    }

    Navigator.of(context).push(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => ViewProfilePage(userId: userId),
      transitionsBuilder: (_, anim, __, child) {
        // Subtle scale + fade for modern feel; Hero handles image morph
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(scale: Tween<double>(begin: 0.98, end: 1).animate(curved), child: child),
        );
      },
    ));
  }

  void _precachePhotos(Iterable<String> urls) {
    for (final u in urls) {
      if (u.isEmpty) continue;
      unawaited(precacheImage(CachedNetworkImageProvider(u), context));
    }
  }

  void _warmTopCard() {
    if (_cards.isEmpty) return;
    final idx = _stack.currentIndex;
    if (idx < 0 || idx >= _cards.length) return;
    final photos = (_cards[idx]['photos'] as List?)?.cast<String>() ?? const [];
    _precachePhotos(photos.take(3));
  }

  @override
  Widget build(BuildContext context) {
    final me = _supa.auth.currentUser;
    if (me == null) {
      return _notLoggedIn();
    }

    if (_initializing) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        if (!_online) const _OfflineBanner(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: (_cards.isEmpty && _exhausted)
                ? _emptyState()
                : _buildStackAndMeasure(),
          ),
        ),
        _bottomBar(),
      ],
    );
  }

  Widget _notLoggedIn() {
    return const Center(
      child: Text('Please sign in to discover profiles',
          style: TextStyle(fontSize: 16)),
    );
  }

  Widget _emptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.verified_rounded, size: 64, color: Color(0xFF6759FF)),
          SizedBox(height: 10),
          Text("You're all caught up",
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
          SizedBox(height: 6),
          Text('Check back later for more profiles.',
              style: TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  // Measures the card and saves width/height for the bottom bar.
  Widget _buildStackAndMeasure() {
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.biggest;

        // Fixed 9:16 ratio (w/h) to fill more vertical space.
        const ratio = 9 / 16;
        const hMargin = 8.0; // tighter horizontal margins

        final maxW = size.width - hMargin * 2;
        final maxH = size.height;

        final cardW = math.min(maxW, maxH * ratio);
        final cardH = cardW / ratio;

        if ((_lastCardW == null || (_lastCardW! - cardW).abs() > 0.5) ||
            (_lastCardH == null || (_lastCardH! - cardH).abs() > 0.5)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _lastCardW = cardW;
              _lastCardH = cardH;
            });
          });
        }

        return Stack(
          children: [
            SwipableStack(
              controller: _stack,
              detectableSwipeDirections: const {
                SwipeDirection.left,
                SwipeDirection.right,
                SwipeDirection.up,
              },
              stackClipBehaviour: Clip.none,
              horizontalSwipeThreshold: 0.25,
              verticalSwipeThreshold: 0.28,
              onWillMoveNext: (index, direction) {
                if (direction == SwipeDirection.up) {
                  _openViewProfile(index);
                  HapticFeedback.selectionClick();
                  return false; // intercept: open full profile instead of like
                }
                return true;
              },
              onSwipeCompleted: (index, direction) async {
                if (index < 0 || index >= _cards.length) return;
                final data = _cards[index];
                final id = data['potential_match_id']?.toString() ?? '';
                if (id.isEmpty) return;

                final key = '$index|$id';
                if (_handled.contains(key)) return;
                _handled.add(key);

                final liked = direction == SwipeDirection.right; // UP no longer likes

                // Persist (guarded), keep UI snappy
                unawaited(_recordSwipe(swipeeId: id, liked: liked));

                // Single-level undo behaviour
                _history
                  ..clear()
                  ..add(_SwipeEvent(index: index, swipeeId: id, liked: liked));
                setState(() {}); // refresh bottom bar state

                HapticFeedback.lightImpact();

                final remaining = _cards.length - (index + 1);
                if (remaining < _minTopUp) unawaited(_loadBatch());

                // Precache next card's first image for smoothness
                final next = index + 1;
                if (next < _cards.length) {
                  final photos = (_cards[next]['photos'] as List?)?.cast<String>() ?? const [];
                  if (photos.isNotEmpty) {
                    unawaited(precacheImage(
                        CachedNetworkImageProvider(photos.first), context));
                  }
                }
              },
              itemCount: _cards.length,
              builder: (context, props) {
                final i = props.index;
                if (i >= _cards.length) return const SizedBox.shrink();
                return _card(i, _cards[i], cardW, cardH);
              },
            ),
          ],
        );
      },
    );
  }

  // Card with left/right photo tap, dots top, gradient info bottom
  Widget _card(int index, Map<String, dynamic> data, double cardW, double cardH) {
    final String name = (data['name'] ?? 'Unknown').toString();
    final int age = (data['age'] is int)
        ? data['age'] as int
        : int.tryParse('${data['age']}') ?? 0;
    final String bio = (data['bio'] ?? '').toString();
    final String distance = (data['distance'] ?? '').toString();

    final List<String> photos = ((data['photos'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[]);
    _photoIndex.putIfAbsent(index, () => 0);

    return Align(
      alignment: Alignment.topCenter,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: cardW,
          height: cardH,
          child: LayoutBuilder(
            builder: (context, c) {
              final cw = c.maxWidth;
              final hasPhotos = photos.isNotEmpty;
              final currentIndex =
                  _photoIndex[index]!.clamp(0, photos.length - 1);
              final currentPhoto = hasPhotos ? photos[currentIndex] : null;

              // Precache next/prev for instant taps
              if (photos.length > 1) {
                final next = (currentIndex + 1).clamp(0, photos.length - 1);
                final prev = (currentIndex - 1).clamp(0, photos.length - 1);
                if (next != currentIndex) {
                  unawaited(precacheImage(
                      CachedNetworkImageProvider(photos[next]), context));
                }
                if (prev != currentIndex) {
                  unawaited(precacheImage(
                      CachedNetworkImageProvider(photos[prev]), context));
                }
              }

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  if (photos.length < 2) return;
                  final isRight = details.localPosition.dx > cw / 2;
                  setState(() {
                    final next =
                        (currentIndex + (isRight ? 1 : -1)).clamp(0, photos.length - 1);
                    _photoIndex[index] = next;
                  });
                },
                onLongPress: () => _openViewProfile(_stack.currentIndex),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: currentPhoto == null
                          ? const ColoredBox(color: Colors.black26)
                          : Hero(
                              // IMPORTANT: tag matches ViewProfilePage ('public_profile_photo_0')
                              // We always animate from the first image for a reliable flight.
                              tag: 'public_profile_photo_0',
                              child: CachedNetworkImage(
                                imageUrl: currentPhoto,
                                fit: BoxFit.cover,
                                fadeInDuration: const Duration(milliseconds: 80),
                                errorWidget: (_, __, ___) => const ColoredBox(
                                  color: Colors.black26,
                                  child: Center(
                                    child: Icon(Icons.broken_image,
                                        size: 36, color: Colors.white54),
                                  ),
                                ),
                              ),
                            ),
                    ),

                    if (photos.length > 1)
                      Positioned(
                        top: 14,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            photos.length,
                            (dot) => Container(
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: dot == currentIndex
                                    ? Colors.pink
                                    : Colors.grey.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        ),
                      ),

                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: InkWell(
                        onTap: () => _openViewProfile(index), // tap name to expand
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Color.fromARGB(255, 0, 0, 0),
                                Color.fromARGB(204, 0, 0, 0),
                                Color.fromARGB(77, 0, 0, 0),
                              ],
                              stops: [0.0, 0.5, 1.0],
                            ),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(10)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                age > 0 ? '$name, $age' : name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 21,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                              if (distance.isNotEmpty) ...[
                                const SizedBox(height: 5),
                                Text(
                                  distance,
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 16),
                                ),
                              ],
                              if (bio.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Text(
                                  bio,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 14),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // Width ties to cardW - 10. Buttons lowered (no overlap) + safe-area padding.
  Widget _bottomBar() {
    final cardW = (_lastCardW ?? MediaQuery.of(context).size.width - 24);

    final double btn = cardW < 320 ? 50 : (cardW < 360 ? 56 : 60);
    final double bigBtn = btn + 10;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        12 + MediaQuery.of(context).padding.bottom * .6,
      ),
      child: Align(
        alignment: Alignment.center,
        child: SizedBox(
          width: (cardW - 10).clamp(220, double.infinity),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _roundAction(
                icon: Icons.rotate_left, // visual hint it's single-level
                color: _history.isEmpty ? Colors.white24 : Colors.green,
                size: btn,
                scale: _scaleUndo,
                onTapDown: _history.isEmpty
                    ? null
                    : () => setState(() => _scaleUndo = 1.12),
                onTapUp: _history.isEmpty
                    ? null
                    : () => setState(() => _scaleUndo = 1.0),
                onTap: _history.isEmpty
                    ? null
                    : () {
                        HapticFeedback.lightImpact();
                        _undoLast();
                      },
              ),
              _roundAction(
                icon: Icons.cancel,
                color: Colors.red,
                size: btn,
                scale: _scaleNope,
                onTapDown: () => setState(() => _scaleNope = 1.12),
                onTapUp: () => setState(() => _scaleNope = 1.0),
                onTap: () {
                  _stack.next(swipeDirection: SwipeDirection.left);
                },
              ),
              _roundAction(
                icon: Icons.star,
                color: Colors.blue,
                size: bigBtn,
                scale: _scaleStar,
                onTapDown: () => setState(() => _scaleStar = 1.12),
                onTapUp: () => setState(() => _scaleStar = 1.0),
                onTap: () {
                  _openViewProfile(_stack.currentIndex);
                },
              ),
              _roundAction(
                icon: Icons.favorite,
                color: Colors.pink,
                size: btn,
                scale: _scaleLike,
                onTapDown: () => setState(() => _scaleLike = 1.12),
                onTapUp: () => setState(() => _scaleLike = 1.0),
                onTap: () {
                  _stack.next(swipeDirection: SwipeDirection.right);
                },
              ),
              _roundAction(
                icon: Icons.flash_on,
                color: Colors.purple,
                size: btn,
                scale: _scaleBoost,
                onTapDown: () => setState(() => _scaleBoost = 1.12),
                onTapUp: () => setState(() => _scaleBoost = 1.0),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Boost sent ✨')),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roundAction({
    required IconData icon,
    required Color color,
    required double scale,
    required double size,
    required VoidCallback? onTap,
    VoidCallback? onTapDown,
    VoidCallback? onTapUp,
  }) {
    const Color bg = Color(0xFF1E1F24);
    return GestureDetector(
      onTap: onTap,
      onTapDown: onTapDown == null ? null : (_) => onTapDown(),
      onTapUp: onTapUp == null ? null : (_) => onTapUp(),
      onTapCancel: onTapUp,
      child: AnimatedScale(
        scale: scale,
        duration: const Duration(milliseconds: 100),
        child: SizedBox(
          width: size,
          height: size,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(blurRadius: 10, color: Colors.black38, offset: Offset(0, 4)),
              ],
            ),
            child: Center(child: Icon(icon, color: color, size: size * 0.44)),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── Helper Widgets
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: .3)),
      ),
      child: Row(
        children: const [
          Icon(Icons.wifi_off_rounded, color: Colors.redAccent),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              "You're offline. Swipes will queue when you're back online.",
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}

// Fullscreen fade route for the loader page
class _FullscreenLoaderRoute extends PageRouteBuilder<void> {
  _FullscreenLoaderRoute({required this.child})
      : super(
          opaque: true,
          barrierDismissible: false,
          transitionDuration: const Duration(milliseconds: 150),
          reverseTransitionDuration: const Duration(milliseconds: 120),
          pageBuilder: (context, animation, secondaryAnimation) => child,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          },
        );

  final Widget child;
}

// ───────────────────────────── Models
class _SwipeEvent {
  final int index; // stack index at time of swipe
  final String swipeeId;
  final bool liked;
  const _SwipeEvent({
    required this.index,
    required this.swipeeId,
    required this.liked,
  });
}
