import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

class HealthService {
  static final Health _health = Health();

  static final List<HealthDataType> _types = [
    HealthDataType.WORKOUT,
    HealthDataType.TOTAL_CALORIES_BURNED,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.STEPS,
  ];

  static final List<HealthDataAccess> _permissions = [
    HealthDataAccess.READ_WRITE,
    HealthDataAccess.READ_WRITE,
    HealthDataAccess.READ_WRITE,
    HealthDataAccess.READ,
  ];

  /// Configura e solicita permissão ao Google Health Connect
  static Future<bool> requestPermissions() async {
    if (kIsWeb) return false;

    try {
      await _health.configure();
      
      bool? hasPermissions = await _health.hasPermissions(_types, permissions: _permissions);
      if (hasPermissions != true) {
        bool authorized = await _health.requestAuthorization(_types, permissions: _permissions);
        return authorized;
      }
      return true;
    } catch (e) {
      debugPrint('Erro ao solicitar permissões do Health Connect: $e');
      return false;
    }
  }

  /// Grava a sessão de musculação com as calorias calculadas pela IA no Google Health Connect
  static Future<bool> saveWorkout({
    required String title,
    required DateTime startTime,
    required DateTime endTime,
    required int caloriesBurned,
  }) async {
    if (kIsWeb) return false;

    try {
      await _health.configure();

      bool? hasPerms = await _health.hasPermissions(_types, permissions: _permissions);
      if (hasPerms != true) {
        await _health.requestAuthorization(_types, permissions: _permissions);
      }

      if (endTime.difference(startTime).inSeconds < 60) {
        startTime = endTime.subtract(const Duration(minutes: 1));
      }

      final int estimatedCalories = caloriesBurned > 0 ? caloriesBurned : 50;

      // 1. Grava explicitamente as calorias ativas no intervalo do treino
      try {
        await _health.writeHealthData(
          value: estimatedCalories.toDouble(),
          type: HealthDataType.ACTIVE_ENERGY_BURNED,
          startTime: startTime,
          endTime: endTime,
          unit: HealthDataUnit.KILOCALORIE,
        );
      } catch (e) {
        debugPrint('Aviso ao gravar calorias isoladas: $e');
      }

      // 2. Grava a sessão de treino com as calorias da IA acopladas
      bool success = await _health.writeWorkoutData(
        activityType: HealthWorkoutActivityType.STRENGTH_TRAINING,
        title: title,
        start: startTime,
        end: endTime,
        totalEnergyBurned: estimatedCalories,
        totalEnergyBurnedUnit: HealthDataUnit.KILOCALORIE,
      );

      // 3. Fallback caso o aparelho bloqueie o totalEnergyBurned
      if (!success) {
        success = await _health.writeWorkoutData(
          activityType: HealthWorkoutActivityType.STRENGTH_TRAINING,
          title: title,
          start: startTime,
          end: endTime,
        );
      }

      return success;
    } catch (e) {
      debugPrint('Erro ao exportar treino para o Google Health: $e');
      return false;
    }
  }

  /// Busca o total de passos do dia atual para exibir na HomeView
  static Future<int> getTodaySteps() async {
    if (kIsWeb) return 0;

    try {
      await _health.configure();
      final now = DateTime.now();
      final midnight = DateTime(now.year, now.month, now.day);
      
      int? steps = await _health.getTotalStepsInInterval(midnight, now);
      return steps ?? 0;
    } catch (e) {
      debugPrint('Erro ao ler passos: $e');
      return 0;
    }
  }
}