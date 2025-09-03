// FILE: lib/features/matches/pages/matches_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../theme/app_theme.dart';
import '../matches_repository.dart';

class MatchesPage extends ConsumerStatefulWidget {
  const MatchesPage({super.key});

  static const String routeName = 'matches';
  static const String routePath = '/matches';

  @override
  ConsumerState<MatchesPage> createState() => _MatchesPageState();
}

class _MatchesPageState extends ConsumerState<MatchesPage> {
  Future<void> _onRefresh() async {
    // Force a quick resubscribe; stream then delivers latest snapshot
    ref.invalidate(myMatchesProvider);
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  // Safe navigation helper (decoupled from ChatPage static fields)
  void _openChat(int matchId) {
    if (!mounted) return;
    // Navigate by path to avoid relying on ChatPage.routeName/routePath
    context.go('/chat?id=$matchId');
  }

  @override
  Widget build(BuildContext context) {
    final matchesAsync = ref.watch(myMatchesProvider);

    return Scaffold(
      backgroundColor: AppTheme.ffSecondaryBg,
      appBar: AppBar(
        backgroundColor: AppTheme.ffPrimaryBg,
        elevation: 2,
        title: const Text('Matches'),
      ),
      body: SafeArea(
        child: matchesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorView(
            message: 'Failed to load matches',
            detail: '$e',
            onRetry: _onRefresh,
          ),
          data: (matches) {
            if (matches.isEmpty) {
              return const _EmptyMatches();
            }
            return RefreshIndicator(
              color: AppTheme.ffPrimary,
              onRefresh: _onRefresh,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                itemCount: matches.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final m = matches[i];
                  return _MatchTile(
                    summary: m,
                    onOpenChat: () => _openChat(m.id),
                    onDelete: () => _softDeleteWithUndo(m.id),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _softDeleteWithUndo(int matchId) async {
    // Grab messenger BEFORE any awaits to avoid use_build_context_synchronously
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(matchesRepositoryProvider);

    await repo.deleteMatch(matchId);

    final controller = messenger.showSnackBar(
      SnackBar(
        content: const Text('Match removed'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await repo.restoreMatch(matchId);
          },
        ),
      ),
    );

    // Optional: wait for snackbar to close and then refresh
    await controller.closed;
    if (mounted) ref.invalidate(myMatchesProvider);
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({
    required this.summary,
    required this.onOpenChat,
    required this.onDelete,
  });

  final MatchSummary summary;
  final VoidCallback onOpenChat;
  final VoidCallback onDelete;

  String _timeLabel() {
    final dt = summary.lastMessageAt ?? summary.createdAt;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dDay = DateTime(dt.year, dt.month, dt.day);
    if (dDay == today) {
      return DateFormat.Hm().format(dt); // 14:32
    }
    if (today.difference(dDay).inDays == 1) {
      return 'Yesterday';
    }
    if (today.difference(dDay).inDays < 7) {
      return DateFormat.E().format(dt); // Mon
    }
    return DateFormat('d MMM').format(dt); // 5 Feb
  }

  @override
  Widget build(BuildContext context) {
    final name = summary.otherName ?? 'Someone';
    final lastMsg = summary.lastMessage ?? 'Say hello 👋';
    final time = _timeLabel();

    return InkWell(
      onTap: onOpenChat,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.ffPrimaryBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.ffAlt, width: 1),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            _Avatar(url: summary.otherPhoto, name: name),
            const SizedBox(width: 12),
            Expanded(
              child: _TitleSubtitle(
                title: name,
                subtitle: lastMsg,
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  time,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(height: 8),
                IconButton(
                  tooltip: 'Remove',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, color: Colors.white70),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.name});
  final String? url;
  final String name;

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty
        ? '💫'
        : name.trim().split(RegExp(r'\s+')).take(2).map((e) => e[0]).join().toUpperCase();

    return Container(
      width: 52,
      height: 52,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [AppTheme.ffPrimary, AppTheme.ffWarning],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: ClipOval(
          child: url == null || url!.isEmpty
              ? Container(
                  color: AppTheme.ffPrimaryBg,
                  child: Center(
                    child: Text(
                      initials,
                      style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                    ),
                  ),
                )
              : Image.network(
                  url!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: AppTheme.ffPrimaryBg,
                    child: Center(
                      child: Text(
                        initials,
                        style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _TitleSubtitle extends StatelessWidget {
  const _TitleSubtitle({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ],
    );
  }
}

class _EmptyMatches extends StatelessWidget {
  const _EmptyMatches();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, color: Colors.white30, size: 64),
            SizedBox(height: 10),
            Text(
              'No matches yet',
              style: TextStyle(color: Colors.white70, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 6),
            Text(
              'Start swiping to find your people.',
              style: TextStyle(color: Colors.white38),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, this.detail, required this.onRetry});
  final String message;
  final String? detail;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 12),
            Text(message, style: const TextStyle(color: Colors.white)),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(detail!, style: const TextStyle(color: Colors.white54), textAlign: TextAlign.center),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.ffPrimary),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
