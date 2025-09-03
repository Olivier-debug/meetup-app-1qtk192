// FILE: lib/features/matches/widgets/empty_matches_list.dart
import 'package:flutter/material.dart';

class EmptyMatchesList extends StatelessWidget {
  const EmptyMatchesList({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.favorite_border, size: 56, color: Colors.white30),
            SizedBox(height: 12),
            Text('No matches yet', style: TextStyle(color: Colors.white70, fontSize: 16)),
            SizedBox(height: 4),
            Text('Keep swiping to find your match.', style: TextStyle(color: Colors.white38)),
          ],
        ),
      ),
    );
  }
}
