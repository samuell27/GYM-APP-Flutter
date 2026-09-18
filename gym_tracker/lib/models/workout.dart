class SetLog {
  int weight;
  int reps;
  bool isCompleted;

  SetLog({
    required this.weight,
    required this.reps,
    this.isCompleted = false,
  });

  Map<String, dynamic> toJson() => {
    'weight': weight,
    'reps': reps,
    'isCompleted': isCompleted,
  };

  factory SetLog.fromJson(Map<String, dynamic> json) => SetLog(
    weight: int.tryParse(json['weight'].toString()) ?? 0,
    reps: int.tryParse(json['reps'].toString()) ?? 0,
    isCompleted: json['isCompleted'] ?? false,
  );
}

class Exercise {
  String id;
  String name;
  List<SetLog> sets;
  int restSeconds;

  Exercise({
    required this.id,
    required this.name,
    required this.sets,
    this.restSeconds = 60,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'sets': sets.map((s) => s.toJson()).toList(),
    'restSeconds': restSeconds,
  };

  factory Exercise.fromJson(Map<String, dynamic> json) => Exercise(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? 'Exercício',
    sets: (json['sets'] as List<dynamic>? ?? [])
        .map((s) => SetLog.fromJson(s as Map<String, dynamic>))
        .toList(),
    restSeconds: int.tryParse(json['restSeconds'].toString()) ?? 60,
  );
}

class WorkoutSession {
  String id;
  String dateIso;
  String name;
  List<Exercise> exercises;
  String userUid;

  WorkoutSession({
    required this.id,
    required this.dateIso,
    required this.name,
    required this.exercises,
    required this.userUid,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'dateIso': dateIso,
    'name': name,
    'exercises': exercises.map((e) => e.toJson()).toList(),
    'userUid': userUid,
    'timestamp': DateTime.now().toUtc().toIso8601String(),
  };
}