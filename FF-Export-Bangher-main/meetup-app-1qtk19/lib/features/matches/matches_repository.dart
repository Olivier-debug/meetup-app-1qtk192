// FILE: lib/features/matches/matches_repository.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Repository provider
final matchesRepositoryProvider = Provider<MatchesRepository>((ref) {
  return MatchesRepository(Supabase.instance.client);
});

/// Stream of my matches (hydrated with other profile + last message)
final myMatchesProvider = StreamProvider<List<MatchSummary>>((ref) async* {
  final me = Supabase.instance.client.auth.currentUser?.id;
  if (me == null) {
    yield const <MatchSummary>[];
    return;
  }
  yield* ref.read(matchesRepositoryProvider).watchMyMatches(me);
});

class MatchSummary {
  final int id;
  final DateTime createdAt;
  final List<String> userIds;
  final String otherUserId;
  final String? otherName;
  final String? otherPhoto;
  final String? lastMessage;
  final DateTime? lastMessageAt;

  const MatchSummary({
    required this.id,
    required this.createdAt,
    required this.userIds,
    required this.otherUserId,
    this.otherName,
    this.otherPhoto,
    this.lastMessage,
    this.lastMessageAt,
  });

  MatchSummary copyWith({
    String? otherName,
    String? otherPhoto,
    String? lastMessage,
    DateTime? lastMessageAt,
  }) {
    return MatchSummary(
      id: id,
      createdAt: createdAt,
      userIds: userIds,
      otherUserId: otherUserId,
      otherName: otherName ?? this.otherName,
      otherPhoto: otherPhoto ?? this.otherPhoto,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
    );
  }
}

class MatchesRepository {
  MatchesRepository(this._db);
  final SupabaseClient _db;

  /// Watches matches for the current user (soft-deleted excluded).
  Stream<List<MatchSummary>> watchMyMatches(String myUserId) {
    final stream = _db
        .from('matches')
        .stream(primaryKey: ['id'])
        .eq('is_deleted', false)
        .order('created_at');

    return stream.asyncMap((rows) async {
      // Filter client-side to avoid the Stream.contains vs PostgREST.contains clash.
      final filtered = rows.where((r) {
        final ids = (r['user_ids'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const <String>[];
        return ids.contains(myUserId);
      }).toList();

      final summaries = await Future.wait(
        filtered.map((r) => _toSummary(r, myUserId)),
      );

      // Sort by lastMessageAt desc (fallback to createdAt)
      summaries.sort((a, b) {
        final at = a.lastMessageAt ?? a.createdAt;
        final bt = b.lastMessageAt ?? b.createdAt;
        return bt.compareTo(at);
      });
      return summaries;
    });
  }

  Future<MatchSummary> _toSummary(Map<String, dynamic> row, String myUserId) async {
    final id = (row['id'] as num).toInt();
    final createdAt = DateTime.parse(row['created_at'] as String);
    final rawIds = (row['user_ids'] as List).map((e) => e.toString()).toList();
    final otherId = _otherUserId(rawIds, myUserId);

    String? name;
    String? photo;
    try {
      final prof = await _db
          .from('profiles')
          .select('name, profile_pictures')
          .eq('user_id', otherId)
          .maybeSingle();

      if (prof != null) {
        name = (prof['name'] as String?)?.trim();
        final pics = (prof['profile_pictures'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const <String>[];
        if (pics.isNotEmpty) photo = pics.first;
      }
    } catch (_) {}

    String? lastMsg;
    DateTime? lastAt;
    try {
      final msg = await _db
          .from('messages')
          .select('message, created_at')
          .eq('chat_id', id)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (msg != null) {
        lastMsg = (msg['message'] as String?)?.trim();
        final created = msg['created_at'] as String?;
        if (created != null) lastAt = DateTime.parse(created);
      }
    } catch (_) {}

    return MatchSummary(
      id: id,
      createdAt: createdAt,
      userIds: rawIds,
      otherUserId: otherId,
      otherName: name,
      otherPhoto: photo,
      lastMessage: lastMsg,
      lastMessageAt: lastAt,
    );
  }

  Future<void> deleteMatch(int matchId) async {
    await _db.from('matches').update({'is_deleted': true}).eq('id', matchId);
  }

  Future<void> restoreMatch(int matchId) async {
    await _db.from('matches').update({'is_deleted': false}).eq('id', matchId);
  }

  Future<int> getOrCreateMatch(String userA, String userB) async {
    final existing = await _db
        .from('matches')
        .select('id')
        .contains('user_ids', [userA, userB])
        .maybeSingle();

    if (existing != null) {
      return (existing['id'] as num).toInt();
    }

    final inserted = await _db
        .from('matches')
        .insert({
          'user_ids': [userA, userB],
          'is_deleted': false,
        })
        .select('id')
        .single();

    return (inserted['id'] as num).toInt();
  }

  String _otherUserId(List<String> userIds, String me) {
    if (userIds.isEmpty) return '';
    if (userIds.length == 1) return userIds.first;
    return userIds[0] == me ? userIds[1] : userIds[0];
  }
}
