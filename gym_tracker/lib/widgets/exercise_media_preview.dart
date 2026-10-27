import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_icons_flutter/lucide_icons.dart';

class ExerciseMediaPreview extends StatefulWidget {
  final String exerciseName;
  final double height;

  const ExerciseMediaPreview({
    super.key,
    required this.exerciseName,
    this.height = 190,
  });

  @override
  State<ExerciseMediaPreview> createState() => _ExerciseMediaPreviewState();
}

class _ExerciseMediaPreviewState extends State<ExerciseMediaPreview> {
  static List<dynamic>? _cachedCatalog;
  static final Map<String, List<String>> _resolvedUrlsCache = {};
  // Guarda quais pastas de imagem já foram usadas por outros exercícios para nunca repetir a mesma foto
  static final Map<String, String> _assignedFolderByExercise = {};

  List<String> _imageUrls = [];
  bool _isLoading = true;
  bool _isPlaying = true;
  int _currentFrame = 0;
  Timer? _frameTimer;

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  @override
  void didUpdateWidget(covariant ExerciseMediaPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.exerciseName != widget.exerciseName) {
      _loadMedia();
    }
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadMedia() async {
    setState(() => _isLoading = true);

    final urls = await _resolveExerciseImages(widget.exerciseName);

    if (!mounted) return;

    for (final url in urls) {
      precacheImage(NetworkImage(url), context).catchError((_) {});
    }

    setState(() {
      _imageUrls = urls;
      _isLoading = false;
    });

    _startAnimationLoop();
  }

  void _startAnimationLoop() {
    _frameTimer?.cancel();
    if (_imageUrls.length > 1) {
      _frameTimer = Timer.periodic(const Duration(milliseconds: 1100), (timer) {
        if (mounted && _isPlaying) {
          setState(() {
            _currentFrame = (_currentFrame + 1) % _imageUrls.length;
          });
        }
      });
    }
  }

  Future<List<String>> _resolveExerciseImages(String ptName) async {
    final cleanKey = ptName.trim().toLowerCase();
    if (_resolvedUrlsCache.containsKey(cleanKey)) {
      return _resolvedUrlsCache[cleanKey]!;
    }

    const String baseUrl = 'https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/';

    // Pastas já em uso por outros exercícios diferentes
    final Set<String> usedFolders = _assignedFolderByExercise.entries
        .where((e) => e.key != cleanKey)
        .map((e) => e.value)
        .toSet();

    // 1. Verifica mapeamento direto de alta precisão (priorizando não repetir imagem)
    final List<String> candidateFolders = _getCandidateFolders(cleanKey);
    String? chosenFolder;

    for (final folder in candidateFolders) {
      if (!usedFolders.contains(folder)) {
        chosenFolder = folder;
        break;
      }
    }

    // 2. Se não encontrou candidato livre direto, pesquisa no catálogo completo da API
    if (chosenFolder == null) {
      try {
        if (_cachedCatalog == null) {
          final res = await http
              .get(Uri.parse('https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json'))
              .timeout(const Duration(seconds: 8));
          if (res.statusCode == 200) {
            _cachedCatalog = jsonDecode(res.body) as List<dynamic>;
          }
        }

        final List<String> searchTerms = _translateToEnglishKeywords(cleanKey);

        if (_cachedCatalog != null && _cachedCatalog!.isNotEmpty) {
          Map<String, dynamic>? bestMatch;
          int bestScore = -1;

          for (final item in _cachedCatalog!) {
            final String enName = (item['name'] ?? '').toString().toLowerCase();
            final String enId = (item['id'] ?? '').toString();

            // Penaliza fortemente se esta imagem já estiver a ser exibida noutro exercício da lista
            if (usedFolders.contains(enId)) continue;

            int score = 0;
            for (int i = 0; i < searchTerms.length; i++) {
              final term = searchTerms[i].toLowerCase();
              if (enName == term || enId.toLowerCase() == term.replaceAll(' ', '_')) {
                score += 60 - (i * 5);
              } else if (enName.contains(term)) {
                score += 25 - (i * 3);
              }
            }

            if (score > bestScore && item['images'] is List && (item['images'] as List).isNotEmpty) {
              bestScore = score;
              bestMatch = item as Map<String, dynamic>;
            }
          }

          if (bestMatch != null && bestScore > 0) {
            final String matchedId = bestMatch['id'].toString();
            _assignedFolderByExercise[cleanKey] = matchedId;
            final List<String> urls = (bestMatch['images'] as List)
                .map((img) => '$baseUrl$img')
                .toList();
            _resolvedUrlsCache[cleanKey] = urls;
            return urls;
          }
        }
      } catch (e) {
        debugPrint('Aviso ao buscar catálogo de mídia: $e');
      }
    }

    chosenFolder ??= candidateFolders.first;
    _assignedFolderByExercise[cleanKey] = chosenFolder;

    final urls = [
      '$baseUrl$chosenFolder/0.jpg',
      '$baseUrl$chosenFolder/1.jpg',
    ];
    _resolvedUrlsCache[cleanKey] = urls;
    return urls;
  }

  /// Retorna uma lista ordenada de pastas exatas do Free Exercise DB para cada variação
  List<String> _getCandidateFolders(String pt) {
    final bool isMachine = pt.contains('máquina') || pt.contains('maquina') || pt.contains('articulad');
    final bool isSmith = pt.contains('smith') || pt.contains('guiada');
    final bool isDumbbell = pt.contains('halter');
    final bool isCable = pt.contains('polia') || pt.contains('cabo') || pt.contains('cross');
    final bool isIncline = pt.contains('inclinad');
    final bool isDecline = pt.contains('declinad');

    // --- PEITO ---
    if (pt.contains('supino')) {
      if (isIncline && isMachine) {
        return ['Leverage_Incline_Chest_Press', 'Smith_Machine_Incline_Bench_Press', 'Incline_Cable_Chest_Press'];
      }
      if (isDecline && isMachine) {
        return ['Leverage_Decline_Chest_Press', 'Smith_Machine_Decline_Press', 'Decline_Barbell_Bench_Press'];
      }
      if (isMachine) {
        return ['Leverage_Chest_Press', 'Machine_Bench_Press', 'Smith_Machine_Bench_Press'];
      }
      if (isIncline && isSmith) {
        return ['Smith_Machine_Incline_Bench_Press', 'Leverage_Incline_Chest_Press'];
      }
      if (isSmith) {
        return ['Smith_Machine_Bench_Press', 'Machine_Bench_Press'];
      }
      if (isIncline && isDumbbell) {
        return ['Incline_Dumbbell_Press', 'Incline_Dumbbell_Press_Reverse-Grip'];
      }
      if (isDecline && isDumbbell) {
        return ['Decline_Dumbbell_Bench_Press', 'Dumbbell_Bench_Press'];
      }
      if (isDumbbell) {
        return ['Dumbbell_Bench_Press', 'One-Arm_Dumbbell_Bench_Press'];
      }
      if (isIncline) {
        return ['Barbell_Incline_Bench_Press_-_Medium_Grip', 'Leverage_Incline_Chest_Press'];
      }
      if (isDecline) {
        return ['Decline_Barbell_Bench_Press', 'Leverage_Decline_Chest_Press'];
      }
      return ['Barbell_Bench_Press_-_Medium_Grip', 'Wide-Grip_Barbell_Bench_Press', 'Dumbbell_Bench_Press'];
    }

    if (pt.contains('voador') || pt.contains('peck deck')) {
      return ['Butterfly', 'Cable_Chest_Press', 'Dumbbell_Flyes'];
    }
    if (pt.contains('crucifixo')) {
      if (isIncline) return ['Incline_Dumbbell_Flyes', 'Incline_Cable_Flye'];
      if (isMachine) return ['Butterfly', 'Cable_Crossover'];
      if (isCable) return ['Cable_Crossover', 'Flat_Bench_Cable_Flyes'];
      return ['Dumbbell_Flyes', 'Butterfly', 'Incline_Dumbbell_Flyes'];
    }
    if (pt.contains('crossover') || pt.contains('cross over')) {
      if (pt.contains('baixa') || pt.contains('inferior')) {
        return ['Low_Cable_Crossover', 'Single-Arm_Cable_Crossover', 'Cable_Crossover'];
      }
      if (pt.contains('média') || pt.contains('media')) {
        return ['Single-Arm_Cable_Crossover', 'Flat_Bench_Cable_Flyes', 'Cable_Crossover'];
      }
      return ['Cable_Crossover', 'Low_Cable_Crossover', 'Single-Arm_Cable_Crossover'];
    }
    if (pt.contains('paralela') || pt.contains('mergulho')) {
      return ['Dips_-_Chest_Version', 'Dips_-_Triceps_Version', 'Bench_Dips'];
    }
    if (pt.contains('flexão') || pt.contains('flexao')) {
      return ['Pushups', 'Incline_Push-Up', 'Decline_Push-Up'];
    }

    // --- COSTAS ---
    if (pt.contains('puxada')) {
      if (pt.contains('fechada') || pt.contains('triângulo') || pt.contains('triangulo') || pt.contains('neutra')) {
        return ['Close-Grip_Front_Lat_Pulldown', 'V-Bar_Pulldown', 'Underhand_Cable_Pulldowns'];
      }
      if (pt.contains('supinada') || pt.contains('inversa')) {
        return ['Underhand_Cable_Pulldowns', 'Close-Grip_Front_Lat_Pulldown'];
      }
      if (isMachine || pt.contains('articulada')) {
        return ['Leverage_Iso_Row', 'Wide-Grip_Lat_Pulldown'];
      }
      return ['Wide-Grip_Lat_Pulldown', 'Full_Range-Of-Motion_Lat_Pulldown', 'Close-Grip_Front_Lat_Pulldown'];
    }
    if (pt.contains('pulldown') || pt.contains('pull down') || pt.contains('pull-down')) {
      return ['Straight-Arm_Pulldown', 'Rope_Straight-Arm_Pulldown', 'Wide-Grip_Lat_Pulldown'];
    }
    if (pt.contains('remada')) {
      if (pt.contains('unilateral') || pt.contains('serrote')) {
        return ['One-Arm_Dumbbell_Row', 'Single-Arm_Cable_Seated_Row'];
      }
      if (pt.contains('cavalinho') || pt.contains('barra t')) {
        return ['T-Bar_Row_with_Handle', 'Lying_T-Bar_Row', 'Bent_Over_Two-Arm_Long_Bar_Row'];
      }
      if (isMachine) {
        return ['Leverage_Iso_Row', 'Seated_Cable_Rows'];
      }
      if (pt.contains('baixa') || pt.contains('sentad') || pt.contains('triângulo') || isCable) {
        return ['Seated_Cable_Rows', 'Leverage_Iso_Row'];
      }
      if (pt.contains('alta')) {
        return ['Upright_Barbell_Row', 'Upright_Cable_Row'];
      }
      return ['Bent_Over_Barbell_Row', 'Reverse_Grip_Bent-Over_Rows', 'Leverage_Iso_Row'];
    }

    // --- BÍCEPS ---
    if (pt.contains('scott')) {
      if (isMachine) return ['Machine_Preacher_Curls', 'Preacher_Curl', 'Cable_Preacher_Curl'];
      if (isDumbbell || pt.contains('unilateral')) return ['One_Arm_Dumbbell_Preacher_Curl', 'Zottman_Preacher_Curl'];
      return ['Preacher_Curl', 'Machine_Preacher_Curls', 'Cable_Preacher_Curl'];
    }
    if (pt.contains('martelo')) {
      if (isCable || pt.contains('corda')) return ['Cable_Hammer_Curls_-_Rope_Attachment', 'Hammer_Curls'];
      return ['Hammer_Curls', 'Alternate_Hammer_Curl', 'Cross_Body_Hammer_Curl'];
    }
    if (pt.contains('rosca')) {
      if (isIncline || pt.contains('45')) return ['Incline_Dumbbell_Curl', 'Alternate_Incline_Dumbbell_Curl'];
      if (pt.contains('concentrada')) return ['Concentration_Curls', 'Standing_Concentration_Curl'];
      if (pt.contains('alternada')) return ['Dumbbell_Alternate_Bicep_Curl', 'Dumbbell_Bicep_Curl'];
      if (isCable) return ['Standing_Biceps_Cable_Curl', 'High_Cable_Curls'];
      if (pt.contains('inversa')) return ['Reverse_Barbell_Curl', 'Standing_Dumbbell_Reverse_Curl'];
      return ['Barbell_Curl', 'EZ-Bar_Curl', 'Dumbbell_Bicep_Curl'];
    }

    // --- TRÍCEPS ---
    if (pt.contains('tríceps') || pt.contains('triceps')) {
      if (pt.contains('corda')) return ['Triceps_Pushdown_-_Rope_Attachment', 'Triceps_Pushdown'];
      if (pt.contains('testa')) return ['Lying_Triceps_Press', 'EZ-Bar_Skullcrusher', 'Decline_EZ_Bar_Triceps_Extension'];
      if (pt.contains('francês') || pt.contains('frances')) {
        return ['Standing_Dumbbell_Triceps_Extension', 'Seated_Triceps_Press', 'Cable_Rope_Overhead_Triceps_Extension'];
      }
      if (pt.contains('coice')) return ['Tricep_Dumbbell_Kickback', 'One-Arm_Tricep_Extension'];
      if (isMachine) return ['Dip_Machine', 'Leverage_Chest_Press'];
      return ['Triceps_Pushdown', 'Triceps_Pushdown_-_V-Bar_Attachment', 'Reverse_Grip_Triceps_Pushdown'];
    }

    // --- OMBROS ---
    if (pt.contains('elevação lateral') || pt.contains('elevacao lateral')) {
      if (isCable) return ['One-Arm_Side_Laterals', 'Cable_Seated_Lateral_Raise'];
      if (isMachine) return ['Lateral_Raise_-_With_Bands', 'Side_Lateral_Raise'];
      return ['Side_Lateral_Raise', 'Seated_Side_Lateral_Raise', 'One-Arm_Side_Laterals'];
    }
    if (pt.contains('elevação frontal') || pt.contains('elevacao frontal')) {
      return ['Front_Dumbbell_Raise', 'Front_Cable_Raise', 'Front_Plate_Raise'];
    }
    if (pt.contains('desenvolvimento')) {
      if (isMachine) return ['Leverage_Shoulder_Press', 'Machine_Shoulder_(Military)_Press', 'Smith_Machine_Overhead_Shoulder_Press'];
      if (isDumbbell) return ['Seated_Dumbbell_Press', 'Standing_Dumbbell_Press', 'Arnold_Dumbbell_Press'];
      return ['Seated_Barbell_Military_Press', 'Standing_Military_Press', 'Leverage_Shoulder_Press'];
    }
    if (pt.contains('posterior') || pt.contains('crucifixo inverso') || pt.contains('face pull')) {
      if (pt.contains('face pull') || isCable) return ['Face_Pull', 'Cable_Rear_Delt_Fly'];
      if (isMachine) return ['Reverse_Machine_Flyes', 'Seated_Bent-Over_Rear_Delt_Raise'];
      return ['Seated_Bent-Over_Rear_Delt_Raise', 'Reverse_Flyes', 'Face_Pull'];
    }
    if (pt.contains('encolhimento')) {
      return ['Dumbbell_Shrug', 'Barbell_Shrug', 'Smith_Machine_Shrug'];
    }

    // --- PERNAS ---
    if (pt.contains('leg press')) {
      return ['Leg_Press', 'Narrow_Stance_Leg_Press'];
    }
    if (pt.contains('extensora')) {
      return ['Leg_Extensions', 'Single-Leg_Leg_Extension'];
    }
    if (pt.contains('flexora')) {
      if (pt.contains('sentad')) return ['Seated_Leg_Curl', 'Lying_Leg_Curls'];
      if (pt.contains('em pé') || pt.contains('unilateral')) return ['Standing_Leg_Curl', 'Lying_Leg_Curls'];
      return ['Lying_Leg_Curls', 'Seated_Leg_Curl', 'Standing_Leg_Curl'];
    }
    if (pt.contains('hack')) {
      return ['Hack_Squat', 'Barbell_Hack_Squat'];
    }
    if (pt.contains('agachamento')) {
      if (pt.contains('búlgaro') || pt.contains('bulgaro')) return ['Single_Leg_Squat', 'Dumbbell_Lunges'];
      if (pt.contains('sumô') || pt.contains('sumo')) return ['Sumo_Deadlift', 'Goblet_Squat'];
      if (isSmith) return ['Smith_Machine_Squat', 'Barbell_Squat'];
      return ['Barbell_Squat', 'Barbell_Full_Squat', 'Front_Barbell_Squat'];
    }
    if (pt.contains('stiff') || pt.contains('terra')) {
      return ['Romanian_Deadlift', 'Stiff-Legged_Barbell_Deadlift', 'Stiff-Legged_Dumbbell_Deadlift'];
    }
    if (pt.contains('passada') || pt.contains('afundo')) {
      return ['Dumbbell_Lunges', 'Barbell_Walking_Lunge', 'Barbell_Lunge'];
    }
    if (pt.contains('pélvica') || pt.contains('pelvica')) {
      return ['Barbell_Hip_Thrust', 'Barbell_Glute_Bridge'];
    }
    if (pt.contains('abdutora') || pt.contains('abdução')) {
      return ['Thigh_Abductor', 'Cable_Hip_Adduction'];
    }
    if (pt.contains('adutora') || pt.contains('adução')) {
      return ['Thigh_Adductor', 'Side_Lying_Groin_Stretch'];
    }
    if (pt.contains('panturrilha') || pt.contains('gêmeos') || pt.contains('gemeos')) {
      if (pt.contains('sentad')) return ['Seated_Calf_Raise', 'Barbell_Seated_Calf_Raise'];
      return ['Standing_Calf_Raises', 'Calf_Press_On_The_Leg_Press_Machine', 'Seated_Calf_Raise'];
    }

    return ['Barbell_Bench_Press_-_Medium_Grip', 'Dumbbell_Bench_Press', 'Pushups'];
  }

  List<String> _translateToEnglishKeywords(String pt) {
    final folders = _getCandidateFolders(pt);
    return folders.map((f) => f.replaceAll('_', ' ')).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: widget.height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF141416),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: Color(0xFF22c55e), strokeWidth: 2),
        ),
      );
    }

    if (_imageUrls.isEmpty) {
      return const SizedBox.shrink();
    }

    final currentUrl = _imageUrls[_currentFrame];

    return Container(
      height: widget.height,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: Image.network(
              currentUrl,
              key: ValueKey<String>(currentUrl),
              fit: BoxFit.cover,
              width: double.infinity,
              height: widget.height,
              errorBuilder: (context, error, stackTrace) {
                return const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.dumbbell, color: Colors.white24, size: 36),
                      SizedBox(height: 8),
                      Text(
                        'Prévia indisponível offline',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 54,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.85),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            left: 12,
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.75),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF22c55e).withOpacity(0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: _isPlaying ? const Color(0xFF22c55e) : Colors.orange,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _currentFrame == 0 ? 'MOVIMENTO • INÍCIO (1/2)' : 'MOVIMENTO • CONTRAÇÃO (2/2)',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
          ),

          Positioned(
            right: 10,
            bottom: 8,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _isPlaying = !_isPlaying;
                  if (!_isPlaying) {
                    _currentFrame = (_currentFrame + 1) % _imageUrls.length;
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isPlaying ? LucideIcons.pause : LucideIcons.play,
                      color: const Color(0xFF22c55e),
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _isPlaying ? 'Pausar' : 'Animar',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}