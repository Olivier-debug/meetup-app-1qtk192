// FILE: lib/features/profile/pages/create_or_complete_profile_page.dart
// FINAL — overwrite rows, M/F/O mapping, no debounce, compiler-clean

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:http/http.dart' as http;
import 'package:flutter/painting.dart' as painting show PaintingBinding; // image cache
import 'package:extended_image/extended_image.dart';
import 'package:image/image.dart' as img; // cropping helper

import '../../../theme/app_theme.dart';
import '../profile_repository.dart';
import '../edit_profile_repository.dart';
import '../../swipe/pages/test_swipe_stack_page.dart';

class CreateOrCompleteProfilePage extends ConsumerStatefulWidget {
  const CreateOrCompleteProfilePage({super.key});

  static const String routeName = 'createOrCompleteProfile';
  static const String routePath = '/create-or-complete-profile';

  @override
  ConsumerState<CreateOrCompleteProfilePage> createState() => _CreateOrCompleteProfilePageState();
}

class _CreateOrCompleteProfilePageState extends ConsumerState<CreateOrCompleteProfilePage> {
  final _pages = <_StepSpec>[];
  final _page = PageController();
  int _index = 0;

  final _name = TextEditingController();
  final _city = TextEditingController();
  final _bio = TextEditingController();
  final _loveLanguage = TextEditingController();

  String? _gender;        // "Male" | "Female" | "Other"
  String? _interestedIn;  // "Males" | "Females" | "Both"
  DateTime? _dob;

  final List<String?> _pictures = List<String?>.filled(6, null, growable: false);

  final _interests = <String>{};
  final _relationshipGoals = <String>{};
  final _languages = <String>{};

  RangeValues _ageRange = const RangeValues(21, 35);
  int _maxDistanceKm = 50;

  List<num>? _location2; // [lat, lng]
  bool _saving = false;
  bool _prefilled = false;
  bool _prefilledPrefs = false;

  static const genders = ['Male', 'Female', 'Other'];
  static const interestedInOptions = ['Males', 'Females', 'Both'];

  static const interestOptions = [
    'Travel','Music','Foodie','Art','Outdoors','Fitness','Movies','Reading','Gaming','Photography','Hiking','Dancing','Yoga','Cooking','Tech','Pets','Fashion','Coffee','Rugby','Soccer','Cycling','Running','Road Trips','Self-Improvement','Startups'
  ];
  static const goalOptions = [
    'Long-term','Short-term','Open to explore','Marriage','Friendship'
  ];
  static const languageOptions = [
    'English','Afrikaans','Zulu','Xhosa','Sotho','Tswana','Venda','Tsonga','Swati','Ndebele','French','Spanish','German','Italian','Portuguese'
  ];

  @override
  void initState() {
    super.initState();

    final cache = painting.PaintingBinding.instance.imageCache;
    cache.maximumSize = 300;
    cache.maximumSizeBytes = 120 << 20;

    _pages.addAll(const [
      _StepSpec("What's your first name?", _PlaceholderBuilder._name),
      _StepSpec('I am interested in:', _PlaceholderBuilder._gender),
      _StepSpec("When's your birthday?", _PlaceholderBuilder._dob),
      _StepSpec('Where are you based?', _PlaceholderBuilder._city),
      _StepSpec('About you', _PlaceholderBuilder._about),
      _StepSpec('Pick your interests', _PlaceholderBuilder._interests),
      _StepSpec('Relationship goals', _PlaceholderBuilder._goals),
      _StepSpec('I want to see matches who can speak:', _PlaceholderBuilder._languages),
      _StepSpec('Photos & preferences', _PlaceholderBuilder._photosAndPrefs),
    ]);
  }

  @override
  void dispose() {
    _page.dispose();
    _name.dispose();
    _city.dispose();
    _bio.dispose();
    _loveLanguage.dispose();
    super.dispose();
  }

  String _meId() {
    final me = Supabase.instance.client.auth.currentUser?.id;
    if (me == null) throw Exception('Not authenticated');
    return me;
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating, backgroundColor: isError ? Colors.red : Colors.green),
    );
  }

  // ---------- Mappings ----------
  String? _mapDbGenderToUi(String? g) {
    switch ((g ?? '').toUpperCase()) {
      case 'M': return 'Male';
      case 'F': return 'Female';
      case 'O': return 'Other';
      default:  return g?.isEmpty ?? true ? null : g;
    }
  }

  String? _mapUiGenderToDb(String? g) {
    switch (g) {
      case 'Male': return 'M';
      case 'Female': return 'F';
      case 'Other': return 'O';
      default: return g;
    }
  }

  // interested_in_gender (DB) uses M/F/O; UI uses Males/Females/Both
  String? _mapInterestedInToDb(String? ui) {
    switch ((ui ?? '').toLowerCase()) {
      case 'males': return 'M';
      case 'females': return 'F';
      case 'both': return 'O';
      default: return ui?.isEmpty ?? true ? null : ui;
    }
  }

  String? _mapInterestedInFromDb(String? db) {
    switch ((db ?? '').toUpperCase()) {
      case 'M': return 'Males';
      case 'F': return 'Females';
      case 'O': return 'Both';
      default: return (db == null || db.isEmpty) ? null : db;
    }
  }

  // ---------- Prefill ----------
  void _prefillOnce(UserProfile? p) {
    if (_prefilled || p == null) return;
    _prefilled = true;
    _name.text = p.name ?? '';
    _city.text = p.currentCity ?? '';
    _bio.text = p.bio ?? '';
    _loveLanguage.text = p.loveLanguage ?? '';
    _gender = _mapDbGenderToUi(p.gender);
    _dob = p.dateOfBirth;

    final list = p.profilePictures;
    for (int i = 0; i < _pictures.length; i++) {
      _pictures[i] = i < list.length ? list[i] : null;
    }

    _interests..clear()..addAll(p.interests);
    _relationshipGoals..clear()..addAll(p.relationshipGoals);
    _languages..clear()..addAll(p.languages);
  }

  Future<void> _prefillInterestedIn() async {
    if (_prefilledPrefs) return;
    try {
      final me = _meId();
      final res = await Supabase.instance.client
          .from('preferences')
          .select('interested_in_gender, age_min, age_max, distance_radius')
          .eq('user_id', me)
          .maybeSingle();

      if (!mounted) return;
      if (res != null) {
        setState(() {
          _interestedIn = _mapInterestedInFromDb((res['interested_in_gender'] as String?)?.trim());
          final aMin = res['age_min'];
          final aMax = res['age_max'];
          if (aMin is int && aMax is int && aMin >= 18 && aMax >= aMin) {
            _ageRange = RangeValues(aMin.toDouble(), aMax.toDouble());
          }
          final dist = res['distance_radius'];
          if (dist is int && dist >= 1) _maxDistanceKm = dist;
          _prefilledPrefs = true;
        });
      } else {
        _prefilledPrefs = true;
      }
    } catch (_) {
      _prefilledPrefs = true;
    }
  }

  // ---------- Helpers ----------
  @visibleForTesting
  static int ageFromDate(DateTime dob, {DateTime? now}) {
    final n = now ?? DateTime.now();
    var years = n.year - dob.year;
    final hadBirthday = (n.month > dob.month) || (n.month == dob.month && n.day >= dob.day);
    if (!hadBirthday) years -= 1;
    return years;
  }

  int _ageFrom(DateTime dob) => ageFromDate(dob);

  int? _firstOpenSlot() {
    for (int i = 0; i < _pictures.length; i++) {
      if (_pictures[i] == null) return i;
    }
    return null;
  }

  List<String> _nonNullPictures() => _pictures.whereType<String>().toList(growable: false);

  // Overwrite-by-user_id with upsert; fallback to update-else-insert if the table lacks UNIQUE(user_id).
  Future<void> _putRowByUserId({
    required String table,
    required Map<String, dynamic> payloadWithUserId,
  }) async {
    try {
      await Supabase.instance.client.from(table).upsert(payloadWithUserId, onConflict: 'user_id');
      return;
    } on PostgrestException catch (e) {
      if (e.code != '42P10') rethrow; // "no unique or exclusion constraint matching the ON CONFLICT specification"
      final userId = payloadWithUserId['user_id'];
      final List updated = await Supabase.instance.client
          .from(table)
          .update(payloadWithUserId)
          .eq('user_id', userId)
          .select('user_id');
      if (updated.isEmpty) {
        await Supabase.instance.client.from(table).insert(payloadWithUserId);
      }
    }
  }

  // ---------- Location ----------
  Future<void> _captureLocation() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever || perm == LocationPermission.denied) {
        _snack('Location permission denied', isError: true);
        return;
      }

      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      if (!mounted) return; setState(() => _location2 = [pos.latitude, pos.longitude]);

      bool setOk = false;
      try {
        final placemarks = await geocoding.placemarkFromCoordinates(
          pos.latitude, pos.longitude, localeIdentifier: 'en',
        );
        String pick(List<String?> xs) {
          for (final s in xs) {
            if (s != null && s.trim().isNotEmpty) return s.trim();
          }
          return '';
        }
        if (placemarks.isNotEmpty) {
          final pm = placemarks.first;
          final city = pick([pm.locality, pm.subAdministrativeArea, pm.administrativeArea, pm.subLocality]);
          final country = pick([pm.country]);
          final parts = <String>[if (city.isNotEmpty) city, if (country.isNotEmpty) country];
          if (parts.isNotEmpty) {
            if (!mounted) return; setState(() => _city.text = parts.join(', '));
            setOk = true;
          }
        }
      } catch (_) {/* fallback below */}

      if (!setOk) {
        final label = await _reverseGeocodeWeb(pos.latitude, pos.longitude);
        if (!mounted) return; setState(() => _city.text = label ?? 'Unknown');
      }
    } catch (e) {
      _snack('Failed to get location: $e', isError: true);
    }
  }

  Future<String?> _reverseGeocodeWeb(double lat, double lon) async {
    try {
      final uri = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=$lat&lon=$lon');
      final res = await http
          .get(
            uri,
            headers: const {
              'User-Agent': 'meetup-app/1.0 (reverse-geocode)',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        final addr = (data['address'] ?? {}) as Map<String, dynamic>;
        String pick(List<String?> xs) {
          for (final s in xs) {
            if (s != null && s.trim().isNotEmpty) return s.trim();
          }
          return '';
        }
        final city = pick([
          addr['city'] as String?,
          addr['town'] as String?,
          addr['village'] as String?,
          addr['municipality'] as String?,
          addr['county'] as String?,
          addr['state'] as String?,
        ]);
        final country = addr['country'] as String? ?? '';
        final parts = <String>[if (city.isNotEmpty) city, if (country.isNotEmpty) country];
        return parts.isEmpty ? null : parts.join(', ');
      }
    } catch (_) {}
    return null;
  }

  // ---------- Crop dialog ----------
  Future<Uint8List?> _cropWithDialogPro(Uint8List srcBytes) async {
    final editorKey = GlobalKey<ExtendedImageEditorState>();
    final imgController = ImageEditorController(); // <-- your version uses this controller
    Uint8List? result;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        const double aspect = 4 / 5; // enforce 4:5
        bool busy = false;

        Future<void> doCrop() async {
          HapticFeedback.selectionClick();
          final state = editorKey.currentState;
          if (state == null) return;
          try {
            final data = await _cropImageDataWithDartLibrary(state: state, quality: 92);
            result = data;
            if (ctx.mounted) Navigator.of(ctx).pop();
          } catch (e) {
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text('Crop failed: $e'), backgroundColor: Colors.red),
              );
            }
          }
        }

        return StatefulBuilder(
          builder: (ctx, setState) {
            return Dialog(
              backgroundColor: AppTheme.ffPrimaryBg,
              insetPadding: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560, maxHeight: 780),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Text('Edit photo', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Reset',
                            onPressed: () {
                              imgController.reset();
                              imgController.updateCropAspectRatio(aspect);
                              HapticFeedback.lightImpact();
                            },
                            icon: const Icon(Icons.restore, color: Colors.white70),
                          ),
                          IconButton(
                            tooltip: 'Rotate 90°',
                            onPressed: () {
                              imgController.rotate();
                              HapticFeedback.selectionClick();
                            },
                            icon: const Icon(Icons.rotate_90_degrees_ccw, color: Colors.white70),
                          ),
                          IconButton(
                            tooltip: 'Flip',
                            onPressed: () {
                              imgController.flip();
                              HapticFeedback.selectionClick();
                            },
                            icon: const Icon(Icons.flip, color: Colors.white70),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            color: Colors.black,
                            child: ExtendedImage.memory(
                              srcBytes,
                              fit: BoxFit.contain,
                              mode: ExtendedImageMode.editor,
                              filterQuality: FilterQuality.high,
                              extendedImageEditorKey: editorKey,
                              cacheRawData: true,
                              initEditorConfigHandler: (state) {
                                return EditorConfig(
                                  maxScale: 8.0,
                                  cropRectPadding: const EdgeInsets.all(16),
                                  hitTestSize: 24,
                                  lineColor: Colors.white70,
                                  editorMaskColorHandler: (context, down) =>
                                      Colors.black.withValues(alpha: down ? 0.45 : 0.6),
                                  cropAspectRatio: aspect,
                                  initCropRectType: InitCropRectType.imageRect,
                                  cropLayerPainter: const EditorCropLayerPainter(),
                                  controller: imgController,
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: AppTheme.ffPrimary),
                            onPressed: busy
                                ? null
                                : () async {
                                    setState(() => busy = true);
                                    await doCrop();
                                    if (ctx.mounted) setState(() => busy = false);
                                  },
                            child: busy
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Use photo', style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    return result;
  }

  // ---------- Photos ----------
  Future<void> _onAddPhotoAt(int index) async {
    if (_pictures.whereType<String>().length >= 6) {
      _snack('You can add up to 6 photos.');
      return;
    }

    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 96,
      maxWidth: 2048,
      maxHeight: 2048,
    );
    if (xfile == null) return;

    final originalBytes = await xfile.readAsBytes();
    final croppedBytes = await _cropWithDialogPro(originalBytes);
    if (croppedBytes == null) return; // canceled

    final repo = ref.read(editProfileRepositoryProvider);
    try {
      final uid = _meId();
      var safeName = xfile.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
      if (safeName.length > 64) safeName = safeName.substring(safeName.length - 64); // keep tail
      final fileName = 'p_${DateTime.now().millisecondsSinceEpoch}_$safeName';
      final url = await repo.uploadProfileImage(
        userId: uid,
        filePath: fileName,
        bytes: croppedBytes,
      );

      final target = _firstOpenSlot() ?? index;
      setState(() => _pictures[target] = url);
      await repo.setProfilePictures(userId: uid, urls: _nonNullPictures());
    } catch (e) {
      _snack('Failed to upload photo: $e', isError: true);
    }
  }

  Future<void> _onAddPhotoNextOpen() async {
    final slot = _firstOpenSlot();
    if (slot == null) {
      _snack('You can add up to 6 photos.');
      return;
    }
    await _onAddPhotoAt(slot);
  }

  // ---------- Save ----------
  Future<void> _onSave() async {
    if (_name.text.trim().isEmpty) return _snack('Please enter your name', isError: true);
    if (_gender == null) return _snack('Please select your gender', isError: true);
    if (_dob == null || _ageFrom(_dob!) < 18) return _snack('You must be 18+ years old', isError: true);
    if (_pictures.whereType<String>().isEmpty) return _snack('Please add at least one photo', isError: true);

    setState(() => _saving = true);
    HapticFeedback.lightImpact();
    try {
      final me = _meId();

      // profiles
      final update = ProfileUpdate(
        name: _name.text.trim(),
        gender: _mapUiGenderToDb(_gender),
        currentCity: _city.text.trim().isEmpty ? null : _city.text.trim(),
        bio: _bio.text.trim().isEmpty ? null : _bio.text.trim(),
        loveLanguage: _loveLanguage.text.trim().isEmpty ? null : _loveLanguage.text.trim(),
        dateOfBirth: _dob,
        profilePictures: _nonNullPictures(),
        interests: List<String>.from(_interests),
        relationshipGoals: List<String>.from(_relationshipGoals),
        myLanguages: List<String>.from(_languages),
      );

      final map = update.toMap();
      map['user_id'] = me;
      if (_location2 != null) map['location2'] = _location2;
      if (_dob != null) {
        map['age'] = _ageFrom(_dob!);
        final d = _dob!;
        map['date_of_birth'] = '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
      }
      if (_city.text.trim().isNotEmpty) map['current_city'] = _city.text.trim();

      await _putRowByUserId(table: 'profiles', payloadWithUserId: map);

      // preferences (save once, like age/distance)
      final prefsPayload = {
        'user_id': me,
        'age_min': _ageRange.start.round(),
        'age_max': _ageRange.end.round(),
        'distance_radius': _maxDistanceKm,
        'interested_in_gender': _mapInterestedInToDb(_interestedIn), // M/F/O
      };

      await _putRowByUserId(table: 'preferences', payloadWithUserId: prefsPayload);

      ref.invalidate(myProfileProvider);
      if (mounted) context.go(TestSwipeStackPage.routePath);
    } on AuthException catch (e) {
      _snack(e.message, isError: true);
    } catch (e) {
      _snack('Failed to save: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    final profileAsync = ref.watch(myProfileProvider);
    final profile = profileAsync.valueOrNull;
    if (user != null) _prefillOnce(profile);
    if (user != null && !_prefilledPrefs) _prefillInterestedIn();

    final media = MediaQuery.of(context);
    final stepPercent = ((_index + 1) / _pages.length).clamp(0.0, 1.0);

    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Scaffold(
        backgroundColor: AppTheme.ffSecondaryBg,
        appBar: AppBar(
          backgroundColor: AppTheme.ffPrimaryBg,
          title: const Text('Create your profile'),
          centerTitle: true,
        ),
        body: SafeArea(
          bottom: true,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: LinearPercentIndicator(
                        lineHeight: 8,
                        barRadius: const Radius.circular(8),
                        animation: !media.accessibleNavigation,
                        percent: stepPercent,
                        animateFromLastPercent: true,
                        restartAnimation: false,
                        progressColor: AppTheme.ffPrimary,
                        backgroundColor: Colors.white10,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('${_index + 1}/${_pages.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.ffPrimaryBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.ffAlt),
                    ),
                    child: PageView.builder(
                      controller: _page,
                      physics: const ClampingScrollPhysics(),
                      itemCount: _pages.length,
                      onPageChanged: (i) => setState(() => _index = i),
                      itemBuilder: (context, i) => _pages[i].builder(context, this),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _index == 0 ? null : () => _page.previousPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOut),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white24),
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          backgroundColor: Colors.transparent,
                        ),
                        child: const Text('Back'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _saving
                            ? null
                            : () async {
                                if (_index == _pages.length - 1) {
                                  await _onSave();
                                } else {
                                  _page.nextPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.ffPrimary,
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _saving
                            ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Save & Continue', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- Step builders ----------
  Widget _buildPadding({required Widget child}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        child: ScrollConfiguration(
          behavior: const _NoGlowScrollBehavior(),
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [child],
          ),
        ),
      );

  Widget _buildNameStep(BuildContext context) => _buildPadding(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _StepTitle("What's your first name?"),
            _LabeledText(label: 'First name', controller: _name, hint: 'Enter your first name', required: true),
            const SizedBox(height: 16),
            const _StepTitle('I am a:'),
            const SizedBox(height: 6),
            _ChoiceChips(
              options: genders,
              value: _gender,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                setState(() => _gender = v);
              },
            ),
          ],
        ),
      );

  Widget _buildGenderStep(BuildContext context) => _buildPadding(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _StepTitle('I am interested in:'),
            _ChoiceChips(
              options: interestedInOptions,
              value: _interestedIn,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                setState(() => _interestedIn = v);
              },
            ),
          ],
        ),
      );

  Widget _buildDobStep(BuildContext context) => _buildPadding(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _StepTitle("When's your birthday?"),
            _DatePickerRow(
              label: 'Date of birth',
              value: _dob,
              onPick: (d) => setState(() => _dob = d),
            ),
            const SizedBox(height: 8),
            const Text('You must be at least 18 years old.', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );

  Widget _buildCityStep(BuildContext context) => _buildPadding(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _StepTitle('Where are you based?'),
            _LabeledText(label: 'City', controller: _city, hint: 'Type your city'),
            const SizedBox(height: 8),
            Wrap(spacing: 10, runSpacing: 8, children: [
              ElevatedButton.icon(
                onPressed: _captureLocation,
                icon: const Icon(Icons.my_location, size: 18, color: Colors.white),
                label: const Text('Use my location', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.ffPrimary, shape: const StadiumBorder()),
              ),
              if (_location2 != null) const Text('Location set ✓', style: TextStyle(color: Colors.white70)),
            ]),
          ],
        ),
      );

  Widget _buildAboutStep(BuildContext context) => _buildPadding(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _StepTitle('About you'),
            _LabeledText(label: 'Short bio', controller: _bio, hint: 'Tell people a little about you', maxLines: 4),
            const SizedBox(height: 12),
            _LabeledText(label: 'Love language (optional)', controller: _loveLanguage, hint: 'e.g. Quality Time'),
          ],
        ),
      );

  Widget _buildInterestsStep(BuildContext context) => _buildPadding(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _StepTitle('Pick your interests'),
            _ChipsSelector(
              options: interestOptions,
              values: _interests,
              onChanged: (next) => setState(() {
                _interests..clear()..addAll(next);
              }),
            ),
            const SizedBox(height: 10),
            const Text('Pick at least 3', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );

  Widget _buildGoalsStep(BuildContext context) => _buildPadding(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _StepTitle('Relationship goals'),
            _ChipsSelector(
              options: goalOptions,
              values: _relationshipGoals,
              onChanged: (next) => setState(() {
                _relationshipGoals..clear()..addAll(next);
              }),
            ),
          ],
        ),
      );

  Widget _buildLanguagesStep(BuildContext context) => _buildPadding(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _StepTitle('I want to see matches who can speak:'),
            _CheckboxGroup(
              options: languageOptions,
              values: _languages,
              onChanged: (next) => setState(() {
                _languages..clear()..addAll(next);
              }),
            ),
          ],
        ),
      );

  Widget _buildPhotosAndPrefsStep(BuildContext context) => _buildPadding(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _StepTitle('Add your photos'),
            _PhotosGrid(
              pictures: _pictures,
              onAddAt: _onAddPhotoAt,
              onAddNextOpen: _onAddPhotoNextOpen,
              onRemoveAt: (idx) async {
                setState(() => _pictures[idx] = null);
                await ref.read(editProfileRepositoryProvider).setProfilePictures(userId: _meId(), urls: _nonNullPictures());
              },
            ),
            const SizedBox(height: 16),
            const _StepTitle('Preferences'),
            const SizedBox(height: 8),
            Text('Age range: ${_ageRange.start.round()} - ${_ageRange.end.round()}', style: const TextStyle(color: Colors.white)),
            RangeSlider(
              values: _ageRange,
              min: 18,
              max: 100,
              divisions: 82,
              labels: RangeLabels('${_ageRange.start.round()}', '${_ageRange.end.round()}'),
              activeColor: AppTheme.ffPrimary,
              onChanged: (v) => setState(() => _ageRange = v),
            ),
            const SizedBox(height: 8),
            Text('Max distance: $_maxDistanceKm km', style: const TextStyle(color: Colors.white)),
            Slider(
              value: _maxDistanceKm.toDouble(),
              min: 5,
              max: 200,
              divisions: 39,
              activeColor: AppTheme.ffPrimary,
              label: '$_maxDistanceKm km',
              onChanged: (v) => setState(() => _maxDistanceKm = v.round()),
            ),
          ],
        ),
      );

  @visibleForTesting
  Widget buildPhotosGridForTest({
    required List<String?> pictures,
    required ValueChanged<int> onAddAt,
    required VoidCallback onAddNextOpen,
    required ValueChanged<int> onRemoveAt,
  }) {
    return _PhotosGrid(
      pictures: pictures,
      onAddAt: onAddAt,
      onAddNextOpen: onAddNextOpen,
      onRemoveAt: onRemoveAt,
    );
  }
}

// ----------------- Small UI widgets -----------------
class _StepSpec {
  const _StepSpec(this.title, this.builder);
  final String title;
  final Widget Function(BuildContext, _CreateOrCompleteProfilePageState) builder;
}

class _PlaceholderBuilder {
  const _PlaceholderBuilder._();
  static Widget _name(BuildContext c, _CreateOrCompleteProfilePageState s) => s._buildNameStep(c);
  static Widget _gender(BuildContext c, _CreateOrCompleteProfilePageState s) => s._buildGenderStep(c);
  static Widget _dob(BuildContext c, _CreateOrCompleteProfilePageState s) => s._buildDobStep(c);
  static Widget _city(BuildContext c, _CreateOrCompleteProfilePageState s) => s._buildCityStep(c);
  static Widget _about(BuildContext c, _CreateOrCompleteProfilePageState s) => s._buildAboutStep(c);
  static Widget _interests(BuildContext c, _CreateOrCompleteProfilePageState s) => s._buildInterestsStep(c);
  static Widget _goals(BuildContext c, _CreateOrCompleteProfilePageState s) => s._buildGoalsStep(c);
  static Widget _languages(BuildContext c, _CreateOrCompleteProfilePageState s) => s._buildLanguagesStep(c);
  static Widget _photosAndPrefs(BuildContext c, _CreateOrCompleteProfilePageState s) => s._buildPhotosAndPrefsStep(c);
}

class _StepTitle extends StatelessWidget {
  const _StepTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
      );
}

class _LabeledText extends StatelessWidget {
  const _LabeledText({
    required this.label,
    required this.controller,
    this.hint,
    this.maxLines = 1,
    this.required = false,
  });
  final String label;
  final String? hint;
  final TextEditingController controller;
  final int maxLines;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      textInputAction: maxLines == 1 ? TextInputAction.next : TextInputAction.newline,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.white70),
        hintStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: AppTheme.ffPrimaryBg,
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.white24),
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: AppTheme.ffPrimary),
          borderRadius: BorderRadius.circular(12),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      validator: required ? (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null : null,
    );
  }
}

class _ChoiceChips extends StatelessWidget {
  const _ChoiceChips({required this.options, required this.value, required this.onChanged});
  final List<String> options;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 10,
      children: options.map((opt) {
        final selected = value == opt;
        return ChoiceChip(
          label: Text(opt),
          selected: selected,
          onSelected: (_) => onChanged(selected ? null : opt),
          labelStyle: TextStyle(color: selected ? Colors.white : Colors.white70),
          selectedColor: AppTheme.ffPrimary.withValues(alpha: 0.6),
          backgroundColor: AppTheme.ffPrimaryBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          side: const BorderSide(color: Colors.white24),
        );
      }).toList(),
    );
  }
}

class _ChipsSelector extends StatelessWidget {
  const _ChipsSelector({required this.options, required this.values, required this.onChanged});
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
          selectedColor: AppTheme.ffPrimary.withValues(alpha: 0.6),
          backgroundColor: AppTheme.ffPrimaryBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          side: const BorderSide(color: Colors.white24),
        );
      }).toList(),
    );
  }
}

class _CheckboxGroup extends StatelessWidget {
  const _CheckboxGroup({required this.options, required this.values, required this.onChanged});
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
            Flexible(child: Text(opt, style: const TextStyle(color: Colors.white70), overflow: TextOverflow.ellipsis)),
          ]),
        );
      }).toList(),
    );
  }
}

class _PhotosGrid extends StatelessWidget {
  const _PhotosGrid({
    required this.pictures,
    required this.onAddAt,
    required this.onAddNextOpen,
    required this.onRemoveAt,
  });
  final List<String?> pictures;
  final ValueChanged<int> onAddAt;
  final VoidCallback onAddNextOpen;
  final ValueChanged<int> onRemoveAt;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cols = width < 360 ? 2 : 3;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: 6,
      itemBuilder: (context, index) {
        final url = pictures[index];
        if (url == null) {
          return InkWell(
            onTap: () => onAddAt(index),
            borderRadius: BorderRadius.circular(12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppTheme.ffPrimaryBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: const Center(child: Icon(Icons.add_a_photo_outlined, color: Colors.white70, size: 28)),
            ),
          );
        }
        return Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                  cacheWidth: ((MediaQuery.of(context).size.width / cols) * MediaQuery.of(context).devicePixelRatio).round(),
                  frameBuilder: (context, child, frame, wasSyncLoaded) {
                    if (wasSyncLoaded) return child;
                    return AnimatedOpacity(
                      opacity: frame == null ? 0 : 1,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      child: child,
                    );
                  },
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Stack(
                      fit: StackFit.expand,
                      children: const [
                        ColoredBox(color: Colors.black26),
                        Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ],
                    );
                  },
                  errorBuilder: (_, __, ___) => const ColoredBox(
                    color: Colors.black26,
                    child: Center(child: Icon(Icons.broken_image)),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: Semantics(
                label: 'Remove photo',
                button: true,
                child: Container(
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                    icon: const Icon(Icons.close, color: Colors.white, size: 18),
                    onPressed: () => onRemoveAt(index),
                  ),
                ),
              ),
            ),
          ],
        );
      },
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
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: AppTheme.ffPrimary),
            ), dialogTheme: DialogThemeData(backgroundColor: AppTheme.ffPrimaryBg),
          ),
          child: child!,
        ),
      );
      onPick(picked);
    }

    return InkWell(
      onTap: pick,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          filled: true,
          fillColor: AppTheme.ffPrimaryBg,
          enabledBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: Colors.white24),
            borderRadius: BorderRadius.circular(12),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: AppTheme.ffPrimary),
            borderRadius: BorderRadius.circular(12),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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

class _NoGlowScrollBehavior extends ScrollBehavior {
  const _NoGlowScrollBehavior();
  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;
}

// ----------------- Image crop helpers (dart library) -----------------
Future<Uint8List> _cropImageDataWithDartLibrary({required ExtendedImageEditorState state, int quality = 92}) async {
  final Rect? cropRect = state.getCropRect();
  final EditActionDetails action = state.editAction!;
  final Uint8List data = state.rawImageData;

  final img.Image? decoded = img.decodeImage(data);
  if (decoded == null) {
    throw Exception('Unsupported image format');
  }

  img.Image image = img.bakeOrientation(decoded);

  if (action.hasRotateDegrees) {
    image = img.copyRotate(image, angle: action.rotateDegrees);
  }
  // Older extended_image exposes only flipY; keep the common path that compiles on your setup.
  if (action.flipY) {
    image = img.flipHorizontal(image);
  }

  if (action.needCrop && cropRect != null) {
    final int x = cropRect.left.round().clamp(0, image.width - 1);
    final int y = cropRect.top.round().clamp(0, image.height - 1);
    final int w = cropRect.width.round().clamp(1, image.width - x);
    final int h = cropRect.height.round().clamp(1, image.height - y);
    image = img.copyCrop(image, x: x, y: y, width: w, height: h);
  }

  final List<int> jpg = img.encodeJpg(image, quality: quality.clamp(1, 100));
  return Uint8List.fromList(jpg);
}
