// FILE: lib/features/profile/pages/edit_profile_page.dart
// Visual refresh to match UserProfilePage:
// - Full-width matte cards with white outline (radius 12)
// - Pink section icons, unified outline color, radius-10 pills/chips
// - Increased horizontal padding (24)
// - Lifestyle subheadings show icon; radio rows don't repeat labels
// - Logic (save/upload/providers) unchanged

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../theme/app_theme.dart';
import '../profile_repository.dart';
import '../edit_profile_repository.dart';
import 'user_profile_gate.dart';

// ── Shared design tokens (file-wide)
const double _screenHPad = 24;
const double _radiusCard = 12;
const double _radiusPill = 10;

class EditProfilePage extends ConsumerStatefulWidget {
  const EditProfilePage({super.key});

  static const String routeName = 'editProfile';
  static const String routePath = '/edit-profile';

  @override
  ConsumerState<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends ConsumerState<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  Color get _outline => AppTheme.ffAlt;

  // Text/controllers
  final _name = TextEditingController();
  final _city = TextEditingController();
  final _bio = TextEditingController();
  final _loveLanguage = TextEditingController();
  final _communicationStyle = TextEditingController(); // persisted
  final _education = TextEditingController(); // persisted
  final _familyPlans = TextEditingController(); // persisted

  // Extra details (persisted)
  final _socialMedia = TextEditingController();       // persisted
  final _personalityType = TextEditingController();   // persisted

  String? _gender;               // UI label: Male/Female/Other
  String? _sexualOrientation;    // persisted
  DateTime? _dob;
  int? _heightCm;                // persisted
  String? _zodiac;               // persisted

  String? _workout;              // persisted
  String? _dietary;              // persisted
  String? _sleeping;             // persisted

  bool _saving = false;
  final _pictures = <String>[];

  // Sets
  final _interests = <String>{};
  final _relationshipGoals = <String>{};
  final _languages = <String>{};

  // Lifestyle (persisted)
  String? _drinking;
  String? _smoking;
  String? _pets;

  // Optional lat/lng
  List<num>? _location2;

  // One-time prefill guard
  bool _prefilled = false;

  // Choices
  static const genders = ['Male', 'Female', 'Other'];
  static const sexualOrientationOptions = [
    'Straight', 'Gay', 'Lesbian', 'Bisexual', 'Asexual', 'Queer', 'Prefer not to say'
  ];

  static const interestOptions = [
    'Travel', 'Music', 'Foodie', 'Art', 'Outdoors', 'Fitness', 'Movies', 'Reading', 'Gaming'
  ];
  static const goalOptions = [
    'Long-term', 'Short-term', 'Open to explore', 'Marriage', 'Friendship'
  ];
  static const languageOptions = [
    'English','Afrikaans','Zulu','Xhosa','Sotho','French','Spanish','German','Italian','Portuguese'
  ];

  // Lifestyle
  static const petsOptions = [
    'No pets', 'Cat person', 'Dog person', 'All the pets'
  ];
  static const drinkingOptions = [
    'Never', 'On special occasions', 'Socially', 'Often'
  ];
  static const smokingOptions = [
    'Never', 'Occasionally', 'Smoker when drinking', 'Regularly'
  ];

  // Extra info
  static const workoutOptions = ['Never', 'Sometimes', 'Often'];
  static const dietaryOptions = ['Omnivore', 'Vegetarian', 'Vegan', 'Pescatarian', 'Halal', 'Kosher'];
  static const sleepingOptions = ['Early bird', 'Night owl', 'Flexible'];
  static const zodiacOptions = [
    'Aries','Taurus','Gemini','Cancer','Leo','Virgo','Libra','Scorpio','Sagittarius','Capricorn','Aquarius','Pisces'
  ];

  // ---- DB <-> UI mappers (gender) ----
  String? _fromDbGender(String? raw) {
    if (raw == null) return null;
    switch (raw.toUpperCase()) {
      case 'M': return 'Male';
      case 'F': return 'Female';
      case 'O': return 'Other';
      default:  return raw;
    }
  }

  String? _toDbGender(String? label) {
    switch (label) {
      case 'Male':   return 'M';
      case 'Female': return 'F';
      case 'Other':  return 'O';
      default:       return label;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _bio.dispose();
    _loveLanguage.dispose();
    _communicationStyle.dispose();
    _education.dispose();
    _familyPlans.dispose();
    _socialMedia.dispose();
    _personalityType.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(myProfileProvider);
    final p = profileAsync.value;

    // One-time prefill from existing profile
    if (!_prefilled && p != null) {
      _prefilled = true;
      _name.text = p.name ?? '';
      _city.text = p.currentCity ?? '';
      _bio.text = p.bio ?? '';
      _loveLanguage.text = p.loveLanguage ?? '';
      _communicationStyle.text = p.communicationStyle ?? '';
      _education.text = p.education ?? '';
      _familyPlans.text = p.familyPlans ?? '';
      _gender = _fromDbGender(p.gender);
      _dob = p.dateOfBirth;
      _pictures..clear()..addAll(p.profilePictures);
      _interests..clear()..addAll(p.interests);
      _relationshipGoals..clear()..addAll(p.relationshipGoals);
      _languages..clear()..addAll(p.languages);

      _drinking = p.drinking;
      _smoking = p.smoking;
      _pets = p.pets;

      _heightCm = p.heightCm;
      _zodiac   = p.zodiacSign;
      _workout  = p.workout;
      _dietary  = p.dietaryPreference;
      _sleeping = p.sleepingHabits;
      _sexualOrientation = p.sexualOrientation;
      _socialMedia.text = p.socialMedia ?? '';
      _personalityType.text = p.personalityType ?? '';
    }

    return Scaffold(
      backgroundColor: AppTheme.ffSecondaryBg,
      appBar: AppBar(
        backgroundColor: AppTheme.ffPrimaryBg,
        title: const Text('Edit Profile'),
        actions: const [SizedBox(width: 8)],
      ),
      body: SafeArea(
        child: profileAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Failed to load profile: $e',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70)),
            ),
          ),
          data: (_) => Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(_screenHPad, 16, _screenHPad, 24),
              children: [
                // PHOTOS
                _Card(
                  radius: _radiusCard,
                  outline: _outline,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Heading(icon: Icons.photo_library_outlined, text: 'Photos'),
                      const SizedBox(height: 12),
                      _PhotosGrid(
                        pictures: _pictures,
                        onAdd: _onAddPhoto,
                        onRemove: (url) async {
                          setState(() => _pictures.remove(url));
                          await ref.read(editProfileRepositoryProvider)
                            .setProfilePictures(userId: _meId(), urls: List<String>.from(_pictures));
                        },
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Tip: Add 3–6 clear photos for the best results.',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // BASICS
                _Card(
                  radius: _radiusCard,
                  outline: _outline,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Heading(icon: Icons.badge_outlined, text: 'Basics'),
                      const SizedBox(height: 12),
                      _LabeledText('Name', _name, required: true),
                      const SizedBox(height: 12),
                      _Dropdown<String>(
                        label: 'Gender',
                        value: _gender,
                        items: genders,
                        onChanged: (v) => setState(() => _gender = v),
                      ),
                      const SizedBox(height: 12),
                      _Dropdown<String>(
                        label: 'Sexual orientation (optional)',
                        value: _sexualOrientation,
                        items: sexualOrientationOptions,
                        onChanged: (v) => setState(() => _sexualOrientation = v),
                      ),
                      const SizedBox(height: 12),
                      _DatePickerRow(
                        label: 'Date of birth',
                        value: _dob,
                        onPick: (d) => setState(() => _dob = d),
                      ),
                      const SizedBox(height: 12),
                      _LabeledText('Current city', _city),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _captureLocation,
                            icon: const Icon(Icons.my_location, size: 18, color: Colors.white),
                            label: const Text('Use my location', style: TextStyle(color: Colors.white)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.ffPrimary, shape: const StadiumBorder(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          if (_location2 != null)
                            const Text('Location set ✓', style: TextStyle(color: Colors.white70)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ABOUT ME
                _Card(
                  radius: _radiusCard,
                  outline: _outline,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Heading(icon: Icons.info_outline, text: 'About me'),
                      const SizedBox(height: 12),
                      _LabeledText('Short bio', _bio, maxLines: 4),
                      const SizedBox(height: 12),
                      _LabeledText('Love style (love language)', _loveLanguage),
                      const SizedBox(height: 12),
                      _LabeledText('Communication style', _communicationStyle),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // LIFESTYLE
                _Card(
                  radius: _radiusCard,
                  outline: _outline,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Heading(icon: Icons.style_outlined, text: 'Lifestyle'),
                      const SizedBox(height: 12),

                      const _Subheading(icon: Icons.pets_outlined, text: 'Pets'),
                      const SizedBox(height: 6),
                      _RadioRow(
                        label: '',
                        value: _pets,
                        options: petsOptions,
                        onChanged: (v) => setState(() => _pets = v),
                        showLabel: false,
                      ),
                      const SizedBox(height: 10),

                      const _Subheading(icon: Icons.local_bar_rounded, text: 'Drinking'),
                      const SizedBox(height: 6),
                      _RadioRow(
                        label: '',
                        value: _drinking,
                        options: drinkingOptions,
                        onChanged: (v) => setState(() => _drinking = v),
                        showLabel: false,
                      ),
                      const SizedBox(height: 10),

                      const _Subheading(icon: Icons.smoke_free, text: 'Smoking'),
                      const SizedBox(height: 6),
                      _RadioRow(
                        label: '',
                        value: _smoking,
                        options: smokingOptions,
                        onChanged: (v) => setState(() => _smoking = v),
                        showLabel: false,
                      ),
                      const SizedBox(height: 10),

                      const _Subheading(icon: Icons.fitness_center, text: 'Workout'),
                      const SizedBox(height: 6),
                      _RadioRow(
                        label: '',
                        value: _workout,
                        options: workoutOptions,
                        onChanged: (v) => setState(() => _workout = v),
                        showLabel: false,
                      ),
                      const SizedBox(height: 10),

                      const _Subheading(icon: Icons.restaurant_menu, text: 'Dietary preference'),
                      const SizedBox(height: 6),
                      _RadioRow(
                        label: '',
                        value: _dietary,
                        options: dietaryOptions,
                        onChanged: (v) => setState(() => _dietary = v),
                        showLabel: false,
                      ),
                      const SizedBox(height: 10),

                      const _Subheading(icon: Icons.nightlight_round, text: 'Sleeping habits'),
                      const SizedBox(height: 6),
                      _RadioRow(
                        label: '',
                        value: _sleeping,
                        options: sleepingOptions,
                        onChanged: (v) => setState(() => _sleeping = v),
                        showLabel: false,
                      ),
                      const SizedBox(height: 12),

                      _LabeledText('Social media (handle / link)', _socialMedia),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // INTERESTS
                _Card(
                  radius: _radiusCard,
                  outline: _outline,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Heading(icon: Icons.interests_outlined, text: 'Interests'),
                      const SizedBox(height: 10),
                      _ChipsSelector(
                        options: interestOptions,
                        values: _interests,
                        onChanged: (v) => setState(() => _interests..clear()..addAll(v)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // RELATIONSHIP GOALS
                _Card(
                  radius: _radiusCard,
                  outline: _outline,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Heading(icon: Icons.flag_outlined, text: 'Relationship goals'),
                      const SizedBox(height: 10),
                      _ChipsSelector(
                        options: goalOptions,
                        values: _relationshipGoals,
                        onChanged: (v) => setState(() => _relationshipGoals..clear()..addAll(v)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // LANGUAGES
                _Card(
                  radius: _radiusCard,
                  outline: _outline,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Heading(icon: Icons.translate_outlined, text: 'Languages I know'),
                      const SizedBox(height: 10),
                      _CheckboxGroup(
                        options: languageOptions,
                        values: _languages,
                        onChanged: (v) => setState(() => _languages..clear()..addAll(v)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // MORE ABOUT ME
                _Card(
                  radius: _radiusCard,
                  outline: _outline,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Heading(icon: Icons.more_horiz_rounded, text: 'More about me'),
                      const SizedBox(height: 12),
                      _LabeledText('Education', _education),
                      const SizedBox(height: 12),
                      _LabeledText('Family plans', _familyPlans),
                      const SizedBox(height: 12),
                      _NumberPickerRow(
                        label: 'Height (cm)',
                        value: _heightCm,
                        min: 120,
                        max: 220,
                        onChanged: (v) => setState(() => _heightCm = v),
                      ),
                      const SizedBox(height: 12),
                      _Dropdown<String>(
                        label: 'Zodiac (optional)',
                        value: _zodiac,
                        items: zodiacOptions,
                        onChanged: (v) => setState(() => _zodiac = v),
                      ),
                      const SizedBox(height: 12),
                      _LabeledText('Personality type (e.g., ENFJ)', _personalityType),
                    ],
                  ),
                ),

                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _saving ? null : _onSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.ffPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _saving
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save Changes', style: TextStyle(color: Colors.white, fontSize: 16)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _captureLocation() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever || perm == LocationPermission.denied) {
        _snack('Location permission denied', isError: true);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() => _location2 = [pos.latitude, pos.longitude]);
    } catch (e) {
      _snack('Failed to get location: $e', isError: true);
    }
  }

  Future<void> _onAddPhoto() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (xfile == null) return;

    final repo = ref.read(editProfileRepositoryProvider);
    try {
      String url;
      if (kIsWeb) {
        final bytes = await xfile.readAsBytes();
        url = await repo.uploadProfileImage(userId: _meId(), filePath: xfile.name, bytes: bytes);
      } else {
        url = await repo.uploadProfileImage(userId: _meId(), filePath: xfile.path);
      }
      setState(() => _pictures.add(url));
      await repo.setProfilePictures(userId: _meId(), urls: List<String>.from(_pictures));
    } catch (e) {
      _snack('Failed to upload photo: $e', isError: true);
    }
  }

  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) return;
    if (_gender == null || _dob == null) {
      _snack('Please select gender and date of birth', isError: true);
      return;
    }
    if (_pictures.isEmpty) {
      _snack('Please keep at least one profile photo', isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final me = _meId();

      int calcAge(DateTime d) {
        final now = DateTime.now();
        int a = now.year - d.year;
        if (now.month < d.month || (now.month == d.month && now.day < d.day)) a--;
        return a;
      }

      // Persist all supported columns.
      final map = <String, dynamic>{
        'user_id': me,
        'name': _name.text.trim(),
        'gender': _toDbGender(_gender!),
        'current_city': _city.text.trim().isEmpty ? null : _city.text.trim(),
        'bio': _bio.text.trim().isEmpty ? null : _bio.text.trim(),
        'love_language': _loveLanguage.text.trim().isEmpty ? null : _loveLanguage.text.trim(),
        'communication_style': _communicationStyle.text.trim().isEmpty ? null : _communicationStyle.text.trim(),
        'education': _education.text.trim().isEmpty ? null : _education.text.trim(),
        'family_plans': _familyPlans.text.trim().isEmpty ? null : _familyPlans.text.trim(),
        'date_of_birth': _dob!.toIso8601String().split('T').first,
        'age': calcAge(_dob!),
        'profile_pictures': List<String>.from(_pictures),
        'interests': List<String>.from(_interests),
        'relationship_goals': List<String>.from(_relationshipGoals),
        'my_languages': List<String>.from(_languages),
        'drinking': _drinking,
        'smoking': _smoking,
        'pets': _pets,
        if (_location2 != null) 'location2': _location2,

        // NEW FIELDS (persisted)
        'sexual_orientation': (_sexualOrientation?.isNotEmpty ?? false) ? _sexualOrientation : null,
        'height_cm': _heightCm,
        'zodiac_sign': _zodiac,
        'workout': _workout,
        'dietary_preference': _dietary,
        'sleeping_habits': _sleeping,
        'social_media': _socialMedia.text.trim().isEmpty ? null : _socialMedia.text.trim(),
        'personality_type': _personalityType.text.trim().isEmpty ? null : _personalityType.text.trim(),
      };

      final editRepo = ref.read(editProfileRepositoryProvider);
      final existing = await editRepo.fetchByUserId(me);
      if (existing == null) {
        await Supabase.instance.client.from('profiles').insert(map).select();
      } else {
        await Supabase.instance.client.from('profiles').update(map).eq('user_id', me).select();
      }

      ref.invalidate(myProfileProvider);
      if (mounted) context.go(UserProfileGate.routePath);
    } catch (e) {
      _snack('Failed to save: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _meId() {
    final me = Supabase.instance.client.auth.currentUser?.id;
    if (me == null) throw Exception('Not authenticated');
    return me;
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.green,
    ));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Building blocks (styled to match the profile page)

class _Card extends StatelessWidget {
  const _Card({required this.child, required this.radius, required this.outline});
  final Widget child;
  final double radius;
  final Color outline;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.ffPrimaryBg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: outline.withValues(alpha: .50), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: child,
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.ffPrimary, size: 18),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: .2,
          ),
        ),
      ],
    );
  }
}

class _Subheading extends StatelessWidget {
  const _Subheading({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.ffPrimary),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 14,
            letterSpacing: .2,
          ),
        ),
      ],
    );
  }
}

class _LabeledText extends StatelessWidget {
  const _LabeledText(this.label, this.controller, {this.maxLines = 1, this.required = false});
  final String label;
  final TextEditingController controller;
  final int maxLines;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        filled: true,
        fillColor: AppTheme.ffPrimaryBg,
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppTheme.ffAlt.withValues(alpha: .9)),
          borderRadius: BorderRadius.circular(_radiusPill),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: AppTheme.ffPrimary),
          borderRadius: BorderRadius.circular(_radiusPill),
        ),
      ),
      validator: required ? (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null : null,
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({required this.label, required this.value, required this.items, required this.onChanged});
  final String label;
  final T? value;
  final List<T> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final T? safeValue = (value != null && items.contains(value)) ? value : null;

    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        filled: true,
        fillColor: AppTheme.ffPrimaryBg,
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppTheme.ffAlt.withValues(alpha: .9)),
          borderRadius: BorderRadius.circular(_radiusPill),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: AppTheme.ffPrimary),
          borderRadius: BorderRadius.circular(_radiusPill),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: safeValue,
          isExpanded: true,
          dropdownColor: AppTheme.ffPrimaryBg,
          items: items
              .map((e) => DropdownMenuItem<T>(
                    value: e,
                    child: Text(e.toString(), style: const TextStyle(color: Colors.white)),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _DatePickerRow extends StatelessWidget {
  const _DatePickerRow({required this.label, required this.value, required this.onPick});
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onPick;

  @override
  Widget build(BuildContext context) {
    Future<void> pick() async {
      final now = DateTime.now();
      final first = DateTime(now.year - 80, 1, 1);
      final last = DateTime(now.year - 18, now.month, now.day);
      final initial = value ?? DateTime(now.year - 25, 1, 1);
      final picked = await showDatePicker(
        context: context,
        firstDate: first,
        lastDate: last,
        initialDate: initial,
        helpText: 'Select your date of birth',
        builder: (context, child) => Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: AppTheme.ffPrimary,
                  onPrimary: Colors.white,
                  surface: AppTheme.ffSecondaryBg,
                  onSurface: Colors.white,
                ),
          ),
          child: child!,
        ),
      );
      onPick(picked);
    }

    const labelStyle = TextStyle(color: Colors.white70);

    return InkWell(
      onTap: pick,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: labelStyle,
          filled: true,
          fillColor: AppTheme.ffPrimaryBg,
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: AppTheme.ffAlt.withValues(alpha: .9)),
            borderRadius: BorderRadius.circular(_radiusPill),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: AppTheme.ffPrimary),
            borderRadius: BorderRadius.circular(_radiusPill),
          ),
        ),
        child: Text(
          value == null
              ? 'Select...'
              : '${value!.year}-${value!.month.toString().padLeft(2, '0')}-${value!.day.toString().padLeft(2, '0')}',
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}

class _ChipsSelector extends StatelessWidget {
  const _ChipsSelector({
    required this.options,
    required this.values,
    required this.onChanged,
  });
  final List<String> options;
  final Set<String> values;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 10,
      children: options.map((opt) {
        final selected = values.contains(opt);
        return FilterChip(
          label: Text(opt),
          selected: selected,
          onSelected: (isSel) {
            final next = {...values};
            isSel ? next.add(opt) : next.remove(opt);
            onChanged(next);
          },
          labelStyle: TextStyle(color: selected ? Colors.white : Colors.white70),
          selectedColor: AppTheme.ffPrimary.withValues(alpha: .55),
          backgroundColor: AppTheme.ffPrimaryBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radiusPill)),
          side: BorderSide(color: AppTheme.ffAlt.withValues(alpha: .9)),
        );
      }).toList(),
    );
  }
}

class _CheckboxGroup extends StatelessWidget {
  const _CheckboxGroup({
    required this.options,
    required this.values,
    required this.onChanged,
  });
  final List<String> options;
  final Set<String> values;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: options.map((opt) {
        final sel = values.contains(opt);
        return InkWell(
          onTap: () {
            final next = {...values};
            sel ? next.remove(opt) : next.add(opt);
            onChanged(next);
          },
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Checkbox(
              value: sel,
              onChanged: (_) {
                final next = {...values};
                sel ? next.remove(opt) : next.add(opt);
                onChanged(next);
              },
              activeColor: AppTheme.ffPrimary,
            ),
            Text(opt, style: const TextStyle(color: Colors.white70)),
          ]),
        );
      }).toList(),
    );
  }
}

class _RadioRow extends StatelessWidget {
  const _RadioRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.showLabel = true,
  });

  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showLabel && label.isNotEmpty)
          Text(label, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
        if (showLabel && label.isNotEmpty) const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((opt) {
            final sel = value == opt;
            return ChoiceChip(
              label: Text(opt),
              selected: sel,
              onSelected: (_) => onChanged(opt),
              labelStyle: TextStyle(color: sel ? Colors.white : Colors.white70),
              selectedColor: AppTheme.ffPrimary.withValues(alpha: .6),
              backgroundColor: AppTheme.ffPrimaryBg,
              side: BorderSide(color: AppTheme.ffAlt.withValues(alpha: .9)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radiusPill)),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _NumberPickerRow extends StatelessWidget {
  const _NumberPickerRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int? value;
  final int min;
  final int max;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        filled: true,
        fillColor: AppTheme.ffPrimaryBg,
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppTheme.ffAlt.withValues(alpha: .9)),
          borderRadius: BorderRadius.circular(_radiusPill),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: AppTheme.ffPrimary),
          borderRadius: BorderRadius.circular(_radiusPill),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: (value ?? min) > min ? () => onChanged((value ?? min) - 1) : null,
            icon: const Icon(Icons.remove, color: Colors.white70),
          ),
          Expanded(
            child: Center(
              child: Text(
                value?.toString() ?? '—',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
          IconButton(
            onPressed: (value ?? min) < max ? () => onChanged((value ?? min) + 1) : null,
            icon: const Icon(Icons.add, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _PhotosGrid extends StatelessWidget {
  const _PhotosGrid({required this.pictures, required this.onAdd, required this.onRemove});
  final List<String> pictures;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[
      ...pictures.map((url) => Stack(
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const ColoredBox(color: Colors.black26, child: Center(child: Icon(Icons.broken_image))),
                  ),
                ),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: InkWell(
                  onTap: () => onRemove(url),
                  child: Container(
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.all(6),
                    child: const Icon(Icons.close, color: Colors.white, size: 16),
                  ),
                ),
              ),
            ],
          )),
      InkWell(
        onTap: onAdd,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppTheme.ffPrimaryBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.ffAlt.withValues(alpha: .9)),
          ),
          child: const Center(child: Icon(Icons.add_a_photo_outlined, color: Colors.white70)),
        ),
      ),
    ];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: cells,
    );
  }
}
