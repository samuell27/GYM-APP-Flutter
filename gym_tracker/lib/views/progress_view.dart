import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProgressView extends StatefulWidget {
  const ProgressView({super.key});

  @override
  State<ProgressView> createState() => _ProgressViewState();
}

class _ProgressViewState extends State<ProgressView> {
  List<Map<String, dynamic>> _history = [];
  int _totalWorkouts = 0;
  double _totalVolume = 0;
  bool _isLoadingSync = false;

  @override
  void initState() {
    super.initState();
    _loadLocalHistory();
    _syncWithFirebase();
  }

  Future<void> _loadLocalHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String? historyJson = prefs.getString('workout_history');

    if (historyJson != null) {
      try {
        List<dynamic> decoded = jsonDecode(historyJson);
        _updateStateWithHistory(List<Map<String, dynamic>>.from(decoded));
      } catch (e) {
        debugPrint('Erro ao ler cache: $e');
      }
    }
  }

  Future<void> _syncWithFirebase() async {
      setState(() => _isLoadingSync = true);
      try {
        final prefs = await SharedPreferences.getInstance();
        final String userEmail = prefs.getString('userEmail') ?? '';

        // Só procura se tiver e-mail configurado
        if (userEmail.isEmpty) return;

        // Puxa só os treinos DO SEU EMAIL
        final snapshot = await FirebaseFirestore.instance
            .collection('workout_history')
            .where('userEmail', isEqualTo: userEmail)
            .get();

        if (snapshot.docs.isNotEmpty) {
          var docs = snapshot.docs;
          
          // Ordena do mais recente para o mais antigo localmente
          docs.sort((a, b) {
            Timestamp? tA = a.data()['timestamp'] as Timestamp?;
            Timestamp? tB = b.data()['timestamp'] as Timestamp?;
            if (tA == null || tB == null) return 0;
            return tB.compareTo(tA);
          });

          List<Map<String, dynamic>> cloudHistory = docs.map((doc) {
            final data = doc.data();
            return {
              'date': data['date'] ?? '',
              'name': data['name'] ?? 'Treino',
              'exercises': data['exercises'] ?? 0,
              'volume': data['volume']?.toString() ?? '0',
              'exerciseList': data['exerciseList'] ?? [], 
            };
          }).toList();

          _updateStateWithHistory(cloudHistory);
          await prefs.setString('workout_history', jsonEncode(cloudHistory));
        }
      } catch (e) {
        debugPrint('Sincronização falhou: $e');
      } finally {
        if (mounted) setState(() => _isLoadingSync = false);
      }
    }

  void _updateStateWithHistory(List<Map<String, dynamic>> historyData) {
    int count = historyData.length;
    double volume = 0;

    for (var item in historyData) {
      volume += double.tryParse(item['volume'].toString()) ?? 0;
    }

    if (mounted) {
      setState(() {
        _history = historyData;
        _totalWorkouts = count;
        _totalVolume = volume;
      });
    }
  }

  String _formatVolume(double volume) {
    if (volume >= 1000) {
      return '${(volume / 1000).toStringAsFixed(1)}k';
    }
    return volume.toStringAsFixed(0);
  }

  String _formatSeconds(int seconds) {
    if (seconds <= 0) return '0s';
    int m = seconds ~/ 60;
    int s = seconds % 60;
    if (m == 0) return '${s}s';
    return '${m}m ${s}s';
  }

  void _showWorkoutDetails(Map<String, dynamic> workout) {
    List<dynamic> exList = workout['exerciseList'] ?? [];

    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF1c1c1e),
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (context) {
          return SafeArea(
            child: Container(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.85),
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2))),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: const Color(0xFF22c55e).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16)),
                        child: const Icon(LucideIcons.calendarCheck,
                            color: Color(0xFF22c55e), size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(workout['name'] ?? 'Treino',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold)),
                            Text('Realizado a ${workout['date']}',
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 14)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      _buildDetailMiniCard(LucideIcons.dumbbell, 'Exercícios',
                          '${workout['exercises']} concluídos'),
                      const SizedBox(width: 12),
                      _buildDetailMiniCard(LucideIcons.barChart2, 'Volume',
                          '${workout['volume']} kg'),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text('Lista de Exercícios',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                  const SizedBox(height: 12),
                  Flexible(
                    child: exList.isEmpty
                        ? Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                                color: const Color(0xFF0a0a0a),
                                borderRadius: BorderRadius.circular(16)),
                            child: const Text(
                              'Os detalhes das séries ficarão disponíveis para os novos treinos gerados a partir de agora.',
                              style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                  height: 1.5),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: exList.length,
                            itemBuilder: (context, index) {
                              final ex = exList[index];
                              final setsDetail = ex['sets_detail'] ?? [];
                              final duration = ex['duration_seconds'] ?? 0;

                              return Card(
                                color: const Color(0xFF0a0a0a),
                                margin: const EdgeInsets.only(bottom: 8),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
                                child: Theme(
                                  data: Theme.of(context).copyWith(
                                      dividerColor: Colors.transparent),
                                  child: ExpansionTile(
                                    iconColor: const Color(0xFF22c55e),
                                    collapsedIconColor: Colors.grey,
                                    title: Text(ex['name'] ?? 'Exercício',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold)),
                                    subtitle: Text(
                                        '${ex['sets_completed']} séries • ${ex['volume']} kg',
                                        style: const TextStyle(
                                            color: Colors.grey, fontSize: 12)),
                                    children: [
                                      ...List.generate(setsDetail.length, (i) {
                                        var s = setsDetail[i];
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 6),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text('Série ${i + 1}',
                                                  style: const TextStyle(
                                                      color: Colors.grey,
                                                      fontWeight:
                                                          FontWeight.bold)),
                                              Text(
                                                  '${s['weight']} kg  x  ${s['reps']} reps',
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.bold)),
                                            ],
                                          ),
                                        );
                                      }),
                                      if (duration > 0)
                                        Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              const Icon(LucideIcons.clock,
                                                  color: Color(0xFF22c55e),
                                                  size: 16),
                                              const SizedBox(width: 8),
                                              Text(
                                                  'Tempo gasto: ${_formatSeconds(duration)}',
                                                  style: const TextStyle(
                                                      color: Color(0xFF22c55e),
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.bold)),
                                            ],
                                          ),
                                        ),
                                      const SizedBox(height: 8),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF22c55e),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('FECHAR',
                          style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
  }

  Widget _buildDetailMiniCard(IconData icon, String title, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: const Color(0xFF0a0a0a),
            borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.grey, size: 20),
            const SizedBox(height: 12),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            Text(title,
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('O seu Progresso',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1)),
                if (_isLoadingSync)
                  const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Color(0xFF22c55e), strokeWidth: 2)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1c1c1e),
                        borderRadius: BorderRadius.circular(24),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.05)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(LucideIcons.checkCircle2,
                              color: Color(0xFF22c55e), size: 32),
                          const Spacer(),
                          const SizedBox(height: 16),
                          Text('$_totalWorkouts',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 36,
                                  fontWeight: FontWeight.bold)),
                          const Text('Treinos\nConcluídos',
                              style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 14,
                                  height: 1.2)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1c1c1e),
                        borderRadius: BorderRadius.circular(24),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.05)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(LucideIcons.dumbbell,
                              color: Colors.orangeAccent, size: 32),
                          const Spacer(),
                          const SizedBox(height: 16),
                          Text(_formatVolume(_totalVolume),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 36,
                                  fontWeight: FontWeight.bold)),
                          const Text('Volume Total (kg)',
                              style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 14,
                                  height: 1.2)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text('HISTÓRICO RECENTE',
                style: TextStyle(
                    color: Colors.grey,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5)),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _history.isEmpty
                ? const Center(
                    child: Text('Ainda não tem treinos concluídos.',
                        style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 100),
                    itemCount: _history.length,
                    itemBuilder: (context, index) {
                      final item = _history[index];

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _showWorkoutDetails(item),
                            borderRadius: BorderRadius.circular(24),
                            highlightColor:
                                const Color(0xFF22c55e).withOpacity(0.1),
                            splashColor:
                                const Color(0xFF22c55e).withOpacity(0.2),
                            child: Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1c1c1e),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                    color: Colors.white.withOpacity(0.05)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                        color: const Color(0xFF0a0a0a),
                                        borderRadius:
                                            BorderRadius.circular(16)),
                                    child: const Icon(LucideIcons.calendar,
                                        color: Color(0xFF22c55e), size: 20),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(item['name'],
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 4),
                                        Text(
                                            '${item['date']} • ${item['exercises']} exercícios',
                                            style: const TextStyle(
                                                color: Colors.grey,
                                                fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      const Text('Volume',
                                          style: TextStyle(
                                              color: Colors.grey,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 4),
                                      Text('${item['volume']} kg',
                                          style: const TextStyle(
                                              color: Color(0xFF22c55e),
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
