// main.dart
// AI-Compass v2.10.8 - Groq AI Engine & Enhanced Twin Physics
// ============================================================
// v2.10.8 핵심 수정:
// - TASK 1: Groq API 전환 (llama-3.3-70b-versatile)
// - TASK 2: Twin 충돌 방지 강화 (Wait & Retry 로직)
// - TASK 3: UI 텍스트 정리 (Gemini → AI Analysis)
// - FIX: 안전거리 15% 보장 + 최대 5회 재시도
// ============================================================

import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'gpt_calculator.dart';

// ============================================================
// 색상 정의
// ============================================================
const Color primaryColor = Color(0xFF1565C0);
const Color primaryDark = Color(0xFF0D47A1);
const Color primaryLight = Color(0xFF42A5F5);
const Color accentColor = Color(0xFF00ACC1);
const Color successColor = Color(0xFF2E7D32);
const Color warningColor = Color(0xFFE65100);
const Color errorColor = Color(0xFFC62828);
const Color tabSelectedColor = Colors.white;
const Color tabUnselectedColor = Color(0xFFB3E5FC);
const Color aiPurple = Color(0xFF7C4DFF);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AICompassApp());
}

class AICompassApp extends StatelessWidget {
  const AICompassApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI-Compass v2.10.8',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: primaryColor,
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        colorScheme: ColorScheme.fromSeed(seedColor: primaryColor),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(backgroundColor: primaryColor, foregroundColor: Colors.white, elevation: 0),
        cardTheme: CardThemeData(elevation: 2, shadowColor: Colors.black.withOpacity(0.1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
        inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
        elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.white, elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 16))),
      ),
      home: const InputScreen(),
    );
  }
}

// ============================================================
// 유틸리티 함수
// ============================================================
String formatCurrency(double value) => NumberFormat('#,###', 'ko_KR').format(value.round());
String formatNumber(int value) => NumberFormat('#,###', 'ko_KR').format(value);
String formatDouble(double value, [int decimals = 0]) => decimals == 0 ? NumberFormat('#,###', 'ko_KR').format(value.round()) : value.toStringAsFixed(decimals);
String formatTime(double seconds) {
  if (seconds < 60) return '${seconds.toStringAsFixed(0)}초';
  int m = (seconds / 60).floor();
  int s = (seconds % 60).round();
  return s == 0 ? '$m분' : '$m분 $s초';
}
Color getCongestionColor(int level) {
  if (level <= 25) return const Color(0xFF4CAF50);
  if (level <= 40) return const Color(0xFF8BC34A);
  if (level <= 55) return const Color(0xFFFFC107);
  if (level <= 70) return const Color(0xFFFF9800);
  if (level <= 85) return const Color(0xFFFF5722);
  return const Color(0xFFF44336);
}
double calculateCleanYMax(double dataMax) {
  if (dataMax <= 0) return 100;
  return ((dataMax * 1.1) / 50).ceil() * 50.0;
}

// ============================================================
// ESG 계산 (건물 전체 기준)
// ============================================================
const double carbonFactor = 0.424; // v2.10.8: 한국 2024 표준
const double pineTreeAbsorption = 6.6;

class ESGResult {
  final double annualEnergySaving, annualCostSaving, annualCarbonReduction;
  final int pineTreeEquivalent;
  ESGResult({required this.annualEnergySaving, required this.annualCostSaving, required this.annualCarbonReduction, required this.pineTreeEquivalent});
}

ESGResult calculateESG({required double currentMonthlyEnergy, required double bestMonthlyEnergy, required int lifts}) {
  final monthlySaving = max(0.0, currentMonthlyEnergy - bestMonthlyEnergy);
  final annualEnergy = monthlySaving * 12;
  final annualCost = annualEnergy * 120;
  final carbonReduction = annualEnergy * carbonFactor;
  final trees = (carbonReduction / pineTreeAbsorption).round();
  return ESGResult(annualEnergySaving: annualEnergy, annualCostSaving: annualCost, annualCarbonReduction: carbonReduction, pineTreeEquivalent: trees);
}

// ============================================================
// 데이터 모델
// ============================================================
const List<String> controlTypes = ['individual', 'group', 'zone', 'oddeven', 'zone_oddeven', 'double_deck', 'dcs', 'zone_group', 'group_oddeven', 'hybrid_dcs', 'energy_save', 'twin'];
const Map<String, String> controlNames = {
  'individual': 'A. 개별독립', 'group': 'B. 군관리', 'zone': 'C. 고저층분할', 'oddeven': 'D. 홀짝층분할',
  'zone_oddeven': 'E. 고저층+홀짝층', 'double_deck': 'F. 더블 데크', 'dcs': 'G. 목적층 예약(DCS)',
  'zone_group': 'H. 군관리+고저층', 'group_oddeven': 'I. 군관리+홀짝층', 'hybrid_dcs': 'J. 하이브리드 DCS',
  'energy_save': 'K. 에너지 절약모드', 'twin': 'L. 트윈 시스템',
};
const Map<String, String> controlShortNames = {
  'individual': 'A', 'group': 'B', 'zone': 'C', 'oddeven': 'D', 'zone_oddeven': 'E', 'double_deck': 'F',
  'dcs': 'G', 'zone_group': 'H', 'group_oddeven': 'I', 'hybrid_dcs': 'J', 'energy_save': 'K', 'twin': 'L',
};
const Map<String, String> controlDescriptions = {
  'individual': '각 호기가 독립적으로 운행', 'group': '복수 호기를 통합 관리', 'zone': '건물을 고층/저층 존으로 분리',
  'oddeven': '홀수/짝수 층 분리 운행', 'zone_oddeven': '존 분리 + 홀짝 분리 결합', 'double_deck': '2층 연결 카로 동시 수송',
  'dcs': '목적층 사전 등록 시스템', 'zone_group': '존 분리 + 군관리 결합', 'group_oddeven': '군관리 + 홀짝 분리',
  'hybrid_dcs': 'DCS + 기존 방식 혼합', 'energy_save': '에너지 효율 최적화 모드', 'twin': '1승강로 2카 독립 운행',
};

class BuildingData {
  final String buildingName, buildingType, currentControl;
  final int floors, lifts, accessibleLifts, capacity, peoplePerFloor, totalPopulation, lobbyFloors;
  final double ratedSpeed, peakUsagePercent;
  final bool useTotalPopulation;
  int get calculatedPopulation => useTotalPopulation ? totalPopulation : max(1, (floors - lobbyFloors) * peoplePerFloor);
  int get totalLifts => lifts + accessibleLifts;
  BuildingData({required this.buildingName, required this.buildingType, required this.floors, required this.lifts, this.accessibleLifts = 0, required this.capacity, required this.ratedSpeed, required this.currentControl, this.peoplePerFloor = 25, this.totalPopulation = 0, this.useTotalPopulation = false, this.peakUsagePercent = 12.0, this.lobbyFloors = 1});
}

class CalculationResult {
  final String controlType, controlName, controlDescription;
  final int capacity, congestionLevel;
  final double stops, highestReversal, rtt, interval, hc5, hc5Percent, awtAvg, awtPeak, dailyEnergy, monthlyCostPerUnit, saturation;
  final bool regenerationActive, meetsSeoulGuideline;
  double get monthlyEnergy => dailyEnergy * 30;
  CalculationResult({required this.controlType, required this.controlName, required this.controlDescription, required this.capacity, required this.stops, required this.highestReversal, required this.rtt, required this.interval, required this.hc5, required this.hc5Percent, required this.awtAvg, required this.awtPeak, required this.dailyEnergy, required this.monthlyCostPerUnit, required this.congestionLevel, required this.saturation, required this.regenerationActive, required this.meetsSeoulGuideline});
}

// ============================================================
// 입력 화면
// ============================================================
class InputScreen extends StatefulWidget {
  const InputScreen({super.key});
  @override
  State<InputScreen> createState() => _InputScreenState();
}

class _InputScreenState extends State<InputScreen> {
  final _formKey = GlobalKey<FormState>();
  // v2.10.4: 기본 건물명 변경
  final _nameCtrl = TextEditingController(text: '샘플빌딩');
  String _buildingType = 'office', _currentControl = 'group';
  final _floorsCtrl = TextEditingController(text: '35'), _liftsCtrl = TextEditingController(text: '6'), _accessibleCtrl = TextEditingController(text: '0');
  final _capacityCtrl = TextEditingController(text: '17'), _speedCtrl = TextEditingController(text: '3.5');
  final _peoplePerFloorCtrl = TextEditingController(text: '30'), _totalPopCtrl = TextEditingController(text: '1000');
  final _peakCtrl = TextEditingController(text: '12'), _lobbyCtrl = TextEditingController(text: '1');
  bool _useTotalPopulation = false;

  @override
  void dispose() { for (var c in [_nameCtrl, _floorsCtrl, _liftsCtrl, _accessibleCtrl, _capacityCtrl, _speedCtrl, _peoplePerFloorCtrl, _totalPopCtrl, _peakCtrl, _lobbyCtrl]) c.dispose(); super.dispose(); }
  
  void _startAnalysis() {
    if (_formKey.currentState!.validate()) {
      final data = BuildingData(
        buildingName: _nameCtrl.text, buildingType: _buildingType, floors: int.parse(_floorsCtrl.text), lifts: int.parse(_liftsCtrl.text), accessibleLifts: int.parse(_accessibleCtrl.text),
        capacity: int.parse(_capacityCtrl.text), ratedSpeed: double.parse(_speedCtrl.text), currentControl: _currentControl,
        peoplePerFloor: int.parse(_peoplePerFloorCtrl.text), totalPopulation: int.parse(_totalPopCtrl.text), useTotalPopulation: _useTotalPopulation,
        peakUsagePercent: double.parse(_peakCtrl.text), lobbyFloors: int.parse(_lobbyCtrl.text),
      );
      Navigator.push(context, MaterialPageRoute(builder: (_) => ResultScreen(buildingData: data)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI-Compass v2.10.8', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: GPTCalculator.hasApiKey ? successColor.withOpacity(0.3) : Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(GPTCalculator.hasApiKey ? Icons.cloud_done : Icons.computer, size: 14, color: Colors.white),
              const SizedBox(width: 4),
              Text(GPTCalculator.hasApiKey ? 'AI Ready' : 'Local', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ]),
          ),
          Container(margin: const EdgeInsets.only(right: 12), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)), child: const Text('v2.10.8', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
        ],
      ),
      body: Form(key: _formKey, child: ListView(padding: const EdgeInsets.all(16), children: [
        _buildSectionCard('건물 정보', [
          TextFormField(controller: _nameCtrl, decoration: const InputDecoration(labelText: '건물명', prefixIcon: Icon(Icons.business)), validator: (v) => v == null || v.isEmpty ? '필수 입력' : null),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(value: _buildingType, decoration: const InputDecoration(labelText: '건물 용도', prefixIcon: Icon(Icons.category)),
            items: const [DropdownMenuItem(value: 'office', child: Text('오피스')), DropdownMenuItem(value: 'hotel', child: Text('호텔')), DropdownMenuItem(value: 'apartment', child: Text('아파트')), DropdownMenuItem(value: 'hospital', child: Text('병원'))],
            onChanged: (v) => setState(() => _buildingType = v!)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextFormField(controller: _floorsCtrl, decoration: const InputDecoration(labelText: '층수', prefixIcon: Icon(Icons.layers)), keyboardType: TextInputType.number, validator: (v) => v == null || v.isEmpty || int.tryParse(v) == null || int.parse(v) < 2 ? '2 이상' : null)),
            const SizedBox(width: 12),
            Expanded(child: TextFormField(controller: _lobbyCtrl, decoration: const InputDecoration(labelText: '로비층', prefixIcon: Icon(Icons.door_front_door)), keyboardType: TextInputType.number)),
          ]),
        ]),
        _buildSectionCard('승강기 정보', [
          Row(children: [
            Expanded(child: TextFormField(controller: _liftsCtrl, decoration: const InputDecoration(labelText: '일반 승강기', prefixIcon: Icon(Icons.elevator)), keyboardType: TextInputType.number, validator: (v) => v == null || v.isEmpty || int.tryParse(v) == null || int.parse(v) < 1 ? '1 이상' : null)),
            const SizedBox(width: 12),
            Expanded(child: TextFormField(controller: _accessibleCtrl, decoration: const InputDecoration(labelText: '장애인용', prefixIcon: Icon(Icons.accessible)), keyboardType: TextInputType.number)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextFormField(controller: _capacityCtrl, decoration: const InputDecoration(labelText: '정원(인)', prefixIcon: Icon(Icons.people)), keyboardType: TextInputType.number, validator: (v) => v == null || v.isEmpty ? '필수' : null)),
            const SizedBox(width: 12),
            Expanded(child: TextFormField(controller: _speedCtrl, decoration: const InputDecoration(labelText: '속도(m/s)', prefixIcon: Icon(Icons.speed)), keyboardType: TextInputType.number, validator: (v) => v == null || v.isEmpty ? '필수' : null)),
          ]),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(value: _currentControl, decoration: const InputDecoration(labelText: '현재 운행방식', prefixIcon: Icon(Icons.settings)),
            items: controlTypes.map((type) => DropdownMenuItem(value: type, child: Text(controlNames[type]!, style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
            onChanged: (v) => setState(() => _currentControl = v!)),
        ]),
        _buildSectionCard('인구 및 피크', [
          SwitchListTile(title: const Text('총 인구수 직접 입력'), subtitle: const Text('층당 인구 대신 총 인구 사용'), value: _useTotalPopulation, onChanged: (v) => setState(() => _useTotalPopulation = v), activeColor: primaryColor),
          const SizedBox(height: 12),
          _useTotalPopulation
            ? TextFormField(controller: _totalPopCtrl, decoration: const InputDecoration(labelText: '총 인구수', prefixIcon: Icon(Icons.groups)), keyboardType: TextInputType.number)
            : TextFormField(controller: _peoplePerFloorCtrl, decoration: const InputDecoration(labelText: '층당 인구수', prefixIcon: Icon(Icons.person)), keyboardType: TextInputType.number),
          const SizedBox(height: 12),
          TextFormField(controller: _peakCtrl, decoration: const InputDecoration(labelText: '피크 사용률 (%)', prefixIcon: Icon(Icons.trending_up), suffixText: '%'), keyboardType: TextInputType.number),
        ]),
        const SizedBox(height: 24),
        ElevatedButton.icon(onPressed: _startAnalysis, icon: const Icon(Icons.analytics), label: const Text('AI 정밀 진단 시작', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 54))),
        const SizedBox(height: 60),
      ])),
    );
  }

  Widget _buildSectionCard(String title, List<Widget> children) => Card(margin: const EdgeInsets.only(bottom: 16), child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryColor)), const SizedBox(height: 16), ...children])));
}

// ============================================================
// 결과 화면
// ============================================================
class ResultScreen extends StatefulWidget {
  final BuildingData buildingData;
  const ResultScreen({super.key, required this.buildingData});
  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  bool isLoading = true;
  String? errorMessage;
  String calculationSource = 'LOCAL-Calc';
  Map<String, CalculationResult>? results;
  Map<String, dynamic>? rawResults;
  List<CalculationResult>? rankedResults;
  CalculationResult? currentResult;
  ESGResult? esgResult;
  bool isTwinSuitable = false, isDoubleDeckSuitable = false;
  int _loadingStep = 0;
  Timer? _messageTimer;

  String? _aiConsultingReport;
  bool _isLoadingConsulting = false;
  Map<String, Map<String, dynamic>>? _peakAnalysisResults;
  bool _isLoadingPeakAnalysis = false;

  final List<String> _loadingMessages = ['Queue Theory 분석 중...', 'ISO 8100-32 표준 적용 중...', '12가지 운행방식 비교 중...', 'ESG 환경 지표 산출 중...', 'AI 분석 준비 중...'];

  @override
  void initState() { 
    super.initState(); 
    _tabController = TabController(length: 5, vsync: this);
    _startLoadingAnimation(); 
    // v2.10.8: 500ms 지연 후 계산 시작 - UI 렌더링 우선
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _performCalculations();
    });
  }
  void _startLoadingAnimation() { _messageTimer = Timer.periodic(const Duration(milliseconds: 600), (timer) { if (mounted && isLoading) setState(() => _loadingStep = (_loadingStep + 1) % _loadingMessages.length); }); }
  @override
  void dispose() { _tabController.dispose(); _messageTimer?.cancel(); super.dispose(); }

  double _safeDouble(dynamic value) { if (value is num) return value.toDouble(); if (value is String) return double.tryParse(value) ?? 0.0; return 0.0; }
  bool _checkTwinSuitability() => widget.buildingData.floors >= 25 && widget.buildingData.lifts >= 3;
  bool _checkDoubleDeckSuitability() => widget.buildingData.floors >= 35 && widget.buildingData.lifts >= 4;

  bool get isAIMode => calculationSource == 'AI-Hybrid';
  bool get isLocalMode => calculationSource.contains('Local') || calculationSource == 'LOCAL-Calc';

  Future<void> _performCalculations() async {
    setState(() { isLoading = true; errorMessage = null; });
    try {
      final gptCalc = GPTCalculator();
      final aiResults = await gptCalc.calculateWithAI(
        buildingName: widget.buildingData.buildingName, buildingType: widget.buildingData.buildingType,
        floors: widget.buildingData.floors, lifts: widget.buildingData.lifts, accessibleLifts: widget.buildingData.accessibleLifts,
        capacity: widget.buildingData.capacity, ratedSpeed: widget.buildingData.ratedSpeed, currentControl: widget.buildingData.currentControl,
        peoplePerFloor: widget.buildingData.peoplePerFloor, totalPopulation: widget.buildingData.useTotalPopulation ? widget.buildingData.totalPopulation : null,
        peakUsagePercent: widget.buildingData.peakUsagePercent, lobbyFloors: widget.buildingData.lobbyFloors,
      );

      if (aiResults.containsKey('_metadata')) {
        calculationSource = aiResults['_metadata']['source'] ?? 'LOCAL-Calc';
        // v2.10.4: API 에러 시 사용자에게 알림
        if (GPTCalculator.lastError != null && mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('AI 연결 실패: ${GPTCalculator.lastError}'),
                backgroundColor: warningColor,
                duration: const Duration(seconds: 4),
              ),
            );
          });
        }
      }
      
      isTwinSuitable = _checkTwinSuitability();
      isDoubleDeckSuitable = _checkDoubleDeckSuitability();

      final Map<String, CalculationResult> calcResults = {};
      for (var type in controlTypes) {
        bool isCurrentControl = (type == widget.buildingData.currentControl);
        if (type == 'twin' && !isTwinSuitable && !isCurrentControl) continue;
        if (type == 'double_deck' && !isDoubleDeckSuitable && !isCurrentControl) continue;
        if (aiResults.containsKey(type)) {
          final d = aiResults[type] as Map<String, dynamic>;
          calcResults[type] = CalculationResult(
            controlType: type, controlName: controlNames[type]!, controlDescription: controlDescriptions[type] ?? '',
            capacity: widget.buildingData.capacity, stops: _safeDouble(d['stops']), highestReversal: _safeDouble(d['highestReversal']),
            rtt: _safeDouble(d['rtt']), interval: _safeDouble(d['interval']), hc5: _safeDouble(d['hc5']), hc5Percent: _safeDouble(d['hc5_percent']),
            awtAvg: _safeDouble(d['awt_avg']), awtPeak: _safeDouble(d['awt_peak']), dailyEnergy: _safeDouble(d['dailyEnergy']),
            monthlyCostPerUnit: (_safeDouble(d['dailyEnergy']) * 30 * 120) / max(1, widget.buildingData.lifts),
            congestionLevel: (_safeDouble(d['congestionLevel'])).round().clamp(15, 95), saturation: _safeDouble(d['saturation']),
            regenerationActive: _safeDouble(d['regenerationActive']) == 1.0,
            meetsSeoulGuideline: _safeDouble(d['meetsSeoulGuideline']) == 1.0,
          );
        }
      }

      final sorted = calcResults.values.toList()..sort((a, b) => a.awtAvg.compareTo(b.awtAvg));
      final current = calcResults[widget.buildingData.currentControl];
      final best = sorted.isNotEmpty ? sorted.first : null;
      ESGResult? esg;
      if (current != null && best != null) esg = calculateESG(currentMonthlyEnergy: current.monthlyEnergy, bestMonthlyEnergy: best.monthlyEnergy, lifts: widget.buildingData.lifts);

      setState(() { results = calcResults; rawResults = aiResults; rankedResults = sorted; currentResult = current; esgResult = esg; isLoading = false; });
    } catch (e) { setState(() { errorMessage = '계산 중 오류가 발생했습니다: $e'; isLoading = false; }); }
  }

  Future<void> _loadAIConsultingReport() async {
    if (_aiConsultingReport != null || _isLoadingConsulting) return;
    setState(() => _isLoadingConsulting = true);
    
    final best = rankedResults![0];
    final current = currentResult!;
    
    final report = await GPTCalculator().generateAIConsultingReport(
      simulationResults: rawResults ?? {},
      buildingName: widget.buildingData.buildingName,
      buildingType: widget.buildingData.buildingType,
      floors: widget.buildingData.floors,
      lifts: widget.buildingData.lifts,
      currentControl: widget.buildingData.currentControl,
      recommendedControl: best.controlType,
      currentAWT: current.awtAvg,
      bestAWT: best.awtAvg,
      annualEnergySaving: esgResult?.annualEnergySaving ?? 0,
      annualCostSaving: esgResult?.annualCostSaving ?? 0,
    );
    
    setState(() { _aiConsultingReport = report; _isLoadingConsulting = false; });
  }

  Future<void> _loadPeakAnalysis() async {
    if (_peakAnalysisResults != null || _isLoadingPeakAnalysis) return;
    setState(() => _isLoadingPeakAnalysis = true);
    
    final results = await GPTCalculator().analyzeMultiPeakScenarios(
      buildingType: widget.buildingData.buildingType,
      floors: widget.buildingData.floors,
      lifts: widget.buildingData.lifts,
      capacity: widget.buildingData.capacity,
      ratedSpeed: widget.buildingData.ratedSpeed,
      totalPopulation: widget.buildingData.calculatedPopulation,
      lobbyFloors: widget.buildingData.lobbyFloors,
    );
    
    setState(() { _peakAnalysisResults = results; _isLoadingPeakAnalysis = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 정밀 진단', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [IconButton(icon: const Icon(Icons.picture_as_pdf), onPressed: isLoading ? null : _generatePDF), IconButton(icon: const Icon(Icons.share), onPressed: isLoading ? null : _sharePDF)],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white, indicatorWeight: 4,
          labelColor: tabSelectedColor, unselectedLabelColor: tabUnselectedColor,
          labelPadding: EdgeInsets.zero,
          labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          tabs: const [
            Tab(icon: Icon(Icons.dashboard, size: 18), text: '요약'),
            Tab(icon: Icon(Icons.table_chart, size: 18), text: '비교표'),
            Tab(icon: Icon(Icons.bar_chart, size: 18), text: '차트'),
            Tab(icon: Icon(Icons.play_circle, size: 18), text: '시뮬레이션'),
            Tab(icon: Icon(Icons.psychology, size: 18), text: 'AI분석'),
          ],
        )),
      body: isLoading ? _buildLoadingView() : errorMessage != null ? _buildErrorView() : TabBarView(controller: _tabController, children: [_buildSummaryTab(), _buildComparisonTab(), _buildChartTab(), _buildSimulatorTab(), _buildAIAnalysisTab()]),
    );
  }

  Widget _buildLoadingView() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const CircularProgressIndicator(strokeWidth: 3), const SizedBox(height: 20), AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: Text(_loadingMessages[_loadingStep], key: ValueKey(_loadingStep), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)))]));
  Widget _buildErrorView() => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.error_outline, size: 64, color: errorColor), const SizedBox(height: 16), Text(errorMessage!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)), const SizedBox(height: 24), ElevatedButton.icon(onPressed: _performCalculations, icon: const Icon(Icons.refresh), label: const Text('다시 시도'))])));

  Widget _buildSummaryTab() {
    if (results == null || currentResult == null || rankedResults == null || rankedResults!.isEmpty) return const Center(child: CircularProgressIndicator());
    final best = rankedResults![0];
    return SingleChildScrollView(padding: const EdgeInsets.all(12), child: Column(children: [
      _buildStatusCard(),
      const SizedBox(height: 12),
      _buildBuildingInfoCard(),
      const SizedBox(height: 12),
      _buildCurrentPerformanceCard(),
      const SizedBox(height: 12),
      _buildRecommendationCard(best),
      const SizedBox(height: 12),
      if (esgResult != null) _buildESGCard(),
      const SizedBox(height: 12),
      _buildImprovementCard(currentResult!, best),
      const SizedBox(height: 60),
    ]));
  }

  Widget _buildStatusCard() {
    Color statusColor = isAIMode ? successColor : isLocalMode ? warningColor : primaryColor;
    String statusText = isAIMode ? 'AI 분석 완료' : 'Local 계산 완료';
    IconData statusIcon = isAIMode ? Icons.cloud_done : Icons.computer;
    return Card(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
      child: Row(children: [Icon(statusIcon, color: statusColor, size: 20), const SizedBox(width: 10), Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)), const Spacer(), Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: statusColor.withOpacity(0.2), borderRadius: BorderRadius.circular(16)), child: Text(calculationSource, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)))]),
    ));
  }

  // v2.10.4: 로비층 정보 추가
  Widget _buildBuildingInfoCard() => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [const Icon(Icons.business, color: primaryColor), const SizedBox(width: 8), Text(widget.buildingData.buildingName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]),
    const SizedBox(height: 12),
    Wrap(spacing: 12, runSpacing: 8, children: [
      _buildInfoChip(Icons.layers, '${widget.buildingData.floors}층'),
      _buildInfoChip(Icons.door_front_door, '로비 ${widget.buildingData.lobbyFloors}층'),
      _buildInfoChip(Icons.elevator, '${widget.buildingData.totalLifts}대'),
      _buildInfoChip(Icons.people, '${widget.buildingData.capacity}인승'),
      _buildInfoChip(Icons.speed, '${widget.buildingData.ratedSpeed}m/s'),
      _buildInfoChip(Icons.groups, '${formatNumber(widget.buildingData.calculatedPopulation)}명'),
    ]),
  ])));

  Widget _buildInfoChip(IconData icon, String label) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(20)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14, color: Colors.grey[600]), const SizedBox(width: 4), Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[700]))]));

  Widget _buildCurrentPerformanceCard() {
    final r = currentResult!;
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [const Icon(Icons.analytics, color: primaryColor), const SizedBox(width: 8), Text('현재 성능: ${r.controlName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: _buildMetricTile('평균 대기', formatTime(r.awtAvg), Icons.timer, r.awtAvg > 60 ? errorColor : r.awtAvg > 30 ? warningColor : successColor)),
        const SizedBox(width: 12),
        Expanded(child: _buildMetricTile('피크 대기', formatTime(r.awtPeak), Icons.schedule, r.awtPeak > 120 ? errorColor : r.awtPeak > 60 ? warningColor : successColor)),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _buildMetricTile('포화도', '${r.saturation.toStringAsFixed(0)}%', Icons.local_fire_department, r.saturation > 100 ? errorColor : r.saturation > 80 ? warningColor : successColor)),
        const SizedBox(width: 12),
        Expanded(child: _buildMetricTile('혼잡도', '${r.congestionLevel}%', Icons.groups, getCongestionColor(r.congestionLevel))),
      ]),
      const SizedBox(height: 12),
      if (r.saturation > 100) Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: errorColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: errorColor.withOpacity(0.3))),
        child: Row(children: [const Icon(Icons.warning, color: errorColor, size: 18), const SizedBox(width: 8), Expanded(child: Text('⚠️ 시스템 과부하: 포화도 ${r.saturation.toStringAsFixed(0)}% - 승강기 증설 검토 필요', style: const TextStyle(color: errorColor, fontSize: 12, fontWeight: FontWeight.w500)))])),
    ])));
  }

  Widget _buildMetricTile(String label, String value, IconData icon, Color color) => Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Icon(icon, size: 16, color: color), const SizedBox(width: 6), Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600]))]), const SizedBox(height: 6), Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color))]));

  Widget _buildRecommendationCard(CalculationResult best) => Card(color: Colors.amber[50], child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [const Icon(Icons.star, color: Colors.amber), const SizedBox(width: 8), const Text('🏆 AI 추천 운행방식', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.amber))]),
    const SizedBox(height: 12),
    Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.amber, width: 2)),
      child: Column(children: [
        Text(best.controlName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: primaryDark)),
        const SizedBox(height: 4),
        Text(best.controlDescription, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          Column(children: [const Text('평균 대기', style: TextStyle(fontSize: 11, color: Colors.grey)), Text(formatTime(best.awtAvg), style: const TextStyle(fontWeight: FontWeight.bold, color: successColor))]),
          Column(children: [const Text('포화도', style: TextStyle(fontSize: 11, color: Colors.grey)), Text('${best.saturation.toStringAsFixed(0)}%', style: const TextStyle(fontWeight: FontWeight.bold, color: successColor))]),
          Column(children: [const Text('월 에너지', style: TextStyle(fontSize: 11, color: Colors.grey)), Text('${formatDouble(best.monthlyEnergy)}kWh', style: const TextStyle(fontWeight: FontWeight.bold, color: primaryColor))]),
        ]),
      ])),
  ])));

  // v2.10.4: ESG 라벨 "건물 전체 연간 절감"
  Widget _buildESGCard() => Card(color: Colors.green[50], child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Row(children: [Icon(Icons.eco, color: successColor), SizedBox(width: 8), Text('🌿 ESG 환경 기여도 (건물 전체 연간)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: successColor))]),
    const SizedBox(height: 16),
    Row(children: [
      Expanded(child: _buildESGTile('[E] 에너지', '${formatDouble(esgResult!.annualEnergySaving)} kWh', Colors.orange)),
      Expanded(child: _buildESGTile('[C] 탄소', '${formatDouble(esgResult!.annualCarbonReduction, 1)} kg', Colors.blue)),
      Expanded(child: _buildESGTile('[T] 소나무', '${formatNumber(esgResult!.pineTreeEquivalent)} 그루', successColor)),
    ]),
  ])));

  Widget _buildESGTile(String label, String value, Color color) => Column(children: [Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Text(label.substring(1, 2), style: TextStyle(fontWeight: FontWeight.bold, color: color))), const SizedBox(height: 6), Text(label.substring(4), style: TextStyle(fontSize: 11, color: Colors.grey[600])), Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color))]);

  Widget _buildImprovementCard(CalculationResult current, CalculationResult best) {
    double awtImprovement = current.awtAvg > 0 ? ((current.awtAvg - best.awtAvg) / current.awtAvg * 100).clamp(0, 100) : 0;
    double energyImprovement = current.monthlyEnergy > 0 ? ((current.monthlyEnergy - best.monthlyEnergy) / current.monthlyEnergy * 100).clamp(0, 100) : 0;
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [Icon(Icons.trending_up, color: primaryColor), SizedBox(width: 8), Text('📈 예상 개선 효과', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: _buildImprovementTile('대기시간 단축', '${awtImprovement.toStringAsFixed(0)}%', Icons.timer_off, primaryColor)),
        const SizedBox(width: 12),
        Expanded(child: _buildImprovementTile('에너지 절감', '${energyImprovement.toStringAsFixed(0)}%', Icons.bolt, successColor)),
        const SizedBox(width: 12),
        Expanded(child: _buildImprovementTile('연간 절감', '${formatCurrency(esgResult?.annualCostSaving ?? 0)}원', Icons.savings, Colors.amber[700]!)),
      ]),
    ])));
  }

  Widget _buildImprovementTile(String label, String value, IconData icon, Color color) => Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[200]!)),
    child: Column(children: [Icon(icon, color: color, size: 28), const SizedBox(height: 8), Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)), Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600]))]));

  Widget _buildComparisonTab() {
    if (results == null) return const Center(child: CircularProgressIndicator());
    final data = results!.values.toList();
    return SingleChildScrollView(padding: const EdgeInsets.all(12), child: Column(children: [
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('📊 운행방식 비교표', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(
          headingRowColor: WidgetStateProperty.all(Colors.grey[100]),
          columnSpacing: 16, dataRowMinHeight: 44, dataRowMaxHeight: 56,
          columns: const [DataColumn(label: Text('방식', style: TextStyle(fontWeight: FontWeight.bold))), DataColumn(label: Text('평균대기')), DataColumn(label: Text('피크대기')), DataColumn(label: Text('HC5%')), DataColumn(label: Text('포화도')), DataColumn(label: Text('월에너지')), DataColumn(label: Text('혼잡도'))],
          rows: data.map((r) {
            bool isOptimal = rankedResults!.isNotEmpty && r.controlType == rankedResults![0].controlType;
            bool isCurrent = r.controlType == widget.buildingData.currentControl;
            return DataRow(
              color: WidgetStateProperty.all(isOptimal ? Colors.amber[50] : isCurrent ? Colors.green[50] : null),
              cells: [
                DataCell(Row(children: [if (isOptimal) const Icon(Icons.star, size: 14, color: Colors.amber), Text(r.controlName, style: TextStyle(fontWeight: isOptimal ? FontWeight.bold : FontWeight.normal))])),
                DataCell(Text(formatTime(r.awtAvg))),
                DataCell(Text(formatTime(r.awtPeak))),
                DataCell(Text('${r.hc5Percent.toStringAsFixed(1)}%')),
                DataCell(Text('${r.saturation.toStringAsFixed(0)}%', style: TextStyle(color: r.saturation > 100 ? errorColor : null, fontWeight: r.saturation > 100 ? FontWeight.bold : null))),
                DataCell(Text('${formatDouble(r.monthlyEnergy)}kWh')),
                DataCell(Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: getCongestionColor(r.congestionLevel).withOpacity(0.2), borderRadius: BorderRadius.circular(8)), child: Text('${r.congestionLevel}%', style: TextStyle(color: getCongestionColor(r.congestionLevel), fontWeight: FontWeight.bold, fontSize: 12)))),
              ],
            );
          }).toList(),
        )),
      ]))),
      const SizedBox(height: 16),
      _buildLegendWidget(),
    ]));
  }

  Widget _buildChartTab() {
    if (results == null) return const Center(child: CircularProgressIndicator());
    return SingleChildScrollView(padding: const EdgeInsets.all(12), child: Column(children: [
      _buildChartCard('⏱️ 평균 대기시간 (초)', _buildAWTChart()),
      const SizedBox(height: 16),
      _buildChartCard('📊 포화도 (%)', _buildSaturationChart()),
      const SizedBox(height: 16),
      _buildLegendWidget(),
      const SizedBox(height: 50),
    ]));
  }

  Widget _buildLegendWidget() => Container(
    width: double.infinity, padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[300]!)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text("📋 운행 방식 범례", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: primaryDark)),
      const SizedBox(height: 12),
      SelectableText("A: 개별독립 | B: 군관리 | C: 고저층분할 | D: 홀짝층분할\nE: 고저층+홀짝층 | F: 더블 데크 | G: 목적층 예약(DCS)\nH: 군관리+고저층 | I: 군관리+홀짝층 | J: 하이브리드 DCS\nK: 에너지 절약모드 | L: 트윈 시스템",
        style: const TextStyle(fontSize: 12, height: 1.8, color: Colors.black87), textAlign: TextAlign.center),
    ]),
  );

  Widget _buildChartCard(String title, Widget chart) => Card(color: Colors.white, child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)), const SizedBox(height: 16), SizedBox(height: 220, child: chart)])));

  Widget _buildAWTChart() {
    final data = results!.values.toList();
    final maxDataY = data.map((r) => r.awtAvg).reduce(max);
    final maxY = calculateCleanYMax(maxDataY);
    const double interval = 50.0;
    return BarChart(BarChartData(alignment: BarChartAlignment.spaceAround, maxY: maxY,
      barGroups: data.asMap().entries.map((entry) { bool isOptimal = rankedResults!.isNotEmpty && entry.value.controlType == rankedResults![0].controlType; return BarChartGroupData(x: entry.key, barRods: [BarChartRodData(toY: entry.value.awtAvg, color: isOptimal ? Colors.amber : primaryColor, width: 18, borderRadius: const BorderRadius.vertical(top: Radius.circular(4)))]); }).toList(),
      titlesData: FlTitlesData(bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (value, meta) { if (value.toInt() >= data.length) return const Text(''); return Padding(padding: const EdgeInsets.only(top: 8), child: Text(controlShortNames[data[value.toInt()].controlType] ?? '', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))); })),
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, interval: interval, getTitlesWidget: (v, m) { if (v < 0 || v > maxY) return const Text(''); return Text('${v.toInt()}', style: const TextStyle(fontSize: 10)); })), topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false))),
      gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: interval, getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey[300]!, strokeWidth: 0.5)), borderData: FlBorderData(show: false)));
  }

  Widget _buildSaturationChart() {
    final data = results!.values.toList();
    final maxDataY = data.map((r) => r.saturation).reduce(max);
    final maxY = calculateCleanYMax(max(100, maxDataY));
    const double interval = 50.0;
    return BarChart(BarChartData(alignment: BarChartAlignment.spaceAround, maxY: maxY,
      barGroups: data.asMap().entries.map((entry) { bool isOptimal = rankedResults!.isNotEmpty && entry.value.controlType == rankedResults![0].controlType; return BarChartGroupData(x: entry.key, barRods: [BarChartRodData(toY: entry.value.saturation, color: isOptimal ? Colors.amber : entry.value.saturation > 100 ? errorColor : successColor, width: 18, borderRadius: const BorderRadius.vertical(top: Radius.circular(4)))]); }).toList(),
      titlesData: FlTitlesData(bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (value, meta) { if (value.toInt() >= data.length) return const Text(''); return Padding(padding: const EdgeInsets.only(top: 8), child: Text(controlShortNames[data[value.toInt()].controlType] ?? '', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))); })),
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 44, interval: interval, getTitlesWidget: (v, m) { if (v < 0 || v > maxY) return const Text(''); return Text('${v.toInt()}%', style: const TextStyle(fontSize: 10)); })), topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false))),
      gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: interval, getDrawingHorizontalLine: (value) { if ((value - 100).abs() < 0.1) return const FlLine(color: errorColor, strokeWidth: 2, dashArray: [5, 5]); return FlLine(color: Colors.grey[300]!, strokeWidth: 0.5); }), borderData: FlBorderData(show: false)));
  }

  Widget _buildSimulatorTab() {
    if (currentResult == null || rankedResults == null || rankedResults!.isEmpty) return const Center(child: Text('데이터 로딩 중...'));
    return ElevatorSimulatorWidget(
      floors: widget.buildingData.floors, lifts: widget.buildingData.lifts, accessibleLifts: widget.buildingData.accessibleLifts,
      capacity: widget.buildingData.capacity,
      currentControl: widget.buildingData.currentControl, bestControl: rankedResults![0].controlType,
      currentAwt: currentResult!.awtAvg, bestAwt: rankedResults![0].awtAvg,
      currentName: currentResult!.controlName, bestName: rankedResults![0].controlName,
      monthlyEnergySaving: max(0, currentResult!.monthlyEnergy - rankedResults![0].monthlyEnergy),
    );
  }

  Widget _buildAIAnalysisTab() {
    return SingleChildScrollView(padding: const EdgeInsets.all(12), child: Column(children: [
      _buildAIConsultingSection(),
      const SizedBox(height: 16),
      _buildPeakTimeSection(),
      const SizedBox(height: 16),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [Icon(Icons.science, color: accentColor), SizedBox(width: 8), Text('🔬 What-If 시나리오 분석', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]),
        const SizedBox(height: 8),
        const Text('가상 상황에서의 영향도를 미리 분석합니다', style: TextStyle(fontSize: 13, color: Colors.grey)),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: ElevatedButton.icon(
          onPressed: () => _showWhatIfDialog(),
          icon: const Icon(Icons.play_arrow),
          label: const Text('시나리오 분석 시작'),
          style: ElevatedButton.styleFrom(backgroundColor: accentColor),
        )),
      ]))),
      const SizedBox(height: 60),
    ]));
  }

  Widget _buildAIConsultingSection() {
    return Card(color: aiPurple.withOpacity(0.1), child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.auto_awesome, color: aiPurple),
        const SizedBox(width: 8),
        const Expanded(child: Text('🤖 AI 맞춤형 컨설팅', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
        if (_isLoadingConsulting)
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: aiPurple))
        else if (_aiConsultingReport == null)
          TextButton.icon(
            onPressed: _loadAIConsultingReport,
            icon: const Icon(Icons.psychology, size: 18),
            label: const Text('분석 시작'),
            style: TextButton.styleFrom(foregroundColor: aiPurple),
          ),
      ]),
      if (_aiConsultingReport != null) ...[
        const Divider(),
        const SizedBox(height: 8),
        SelectableText(_aiConsultingReport!, style: const TextStyle(fontSize: 13, height: 1.6)),
      ] else if (!_isLoadingConsulting) ...[
        const SizedBox(height: 8),
        Text('AI가 건물 특성에 맞는 상세 컨설팅 보고서를 생성합니다', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
      ],
    ])));
  }

  Widget _buildPeakTimeSection() {
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.schedule, color: warningColor),
        const SizedBox(width: 8),
        const Expanded(child: Text('⏰ 피크타임 시나리오', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
        if (_isLoadingPeakAnalysis)
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: warningColor))
        else if (_peakAnalysisResults == null)
          TextButton.icon(onPressed: _loadPeakAnalysis, icon: const Icon(Icons.analytics, size: 18), label: const Text('분석'), style: TextButton.styleFrom(foregroundColor: warningColor)),
      ]),
      if (_peakAnalysisResults != null) ...[
        const SizedBox(height: 12),
        ..._peakAnalysisResults!.entries.map((e) => _buildPeakScenarioRow(e.key, e.value)),
      ] else if (!_isLoadingPeakAnalysis) ...[
        const SizedBox(height: 8),
        Text('건물 유형별 피크타임 시나리오를 자동 분석합니다', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
      ],
    ])));
  }

  Widget _buildPeakScenarioRow(String name, Map<String, dynamic> data) {
    final direction = data['direction'] == 'up' ? '↑' : data['direction'] == 'down' ? '↓' : '↕';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        Text('$direction $name', style: const TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(width: 8),
        Text('(${data['time']})', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        const Spacer(),
        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
          child: Text(data['bestControlName'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: primaryColor))),
        const SizedBox(width: 8),
        Text('${(data['bestAWT'] as double).toStringAsFixed(0)}초', style: const TextStyle(fontWeight: FontWeight.bold)),
      ]),
    );
  }

  void _showWhatIfDialog() {
    showDialog(context: context, builder: (_) => WhatIfAnalysisDialog(buildingData: widget.buildingData, baseResults: rawResults ?? {}));
  }

  // ============================================================
  // PDF 생성 (v2.10.4 - 로비층 정보 추가)
  // ============================================================
  Future<pw.Document> _createPDF() async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansKRRegular();
    final fontBold = await PdfGoogleFonts.notoSansKRBold();
    final current = currentResult!;
    final best = rankedResults![0];
    double awtImprovement = current.awtAvg > 0 ? ((current.awtAvg - best.awtAvg) / current.awtAvg * 100).clamp(0, 100) : 0;
    double energyImprovement = current.monthlyEnergy > 0 ? ((current.monthlyEnergy - best.monthlyEnergy) / current.monthlyEnergy * 100).clamp(0, 100) : 0;
    double yearlySaving = esgResult?.annualCostSaving ?? 0;
    bool hasOverloadWarning = results!.values.any((r) => r.saturation > 100);

    pdf.addPage(pw.Page(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(20),
      build: (context) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Container(padding: const pw.EdgeInsets.all(12), decoration: pw.BoxDecoration(color: PdfColor.fromHex('#1565C0'), borderRadius: pw.BorderRadius.circular(8)),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('AI-Compass v2.10.8', style: pw.TextStyle(font: fontBold, fontSize: 16, color: PdfColors.white)),
              pw.Text('AI 기반 승강기 정밀 진단 보고서', style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.white)),
            ]),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text('한국승강기안전공단 기준', style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.white)),
              pw.Text(DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()), style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.white)),
            ]),
          ])),
        pw.SizedBox(height: 8),
        
        pw.Text('1. 건물 개요', style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColor.fromHex('#1565C0'))),
        pw.Divider(thickness: 1, color: PdfColor.fromHex('#1565C0')),
        pw.SizedBox(height: 4),
        pw.Container(padding: const pw.EdgeInsets.all(8), decoration: pw.BoxDecoration(color: PdfColors.grey100, borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Column(children: [
            pw.Row(children: [
              pw.Expanded(child: pw.Text('건물명: ${widget.buildingData.buildingName}', style: pw.TextStyle(font: fontBold, fontSize: 10))),
              pw.Text('용도: ${{ 'office': '오피스', 'hotel': '호텔', 'apartment': '아파트', 'hospital': '병원' }[widget.buildingData.buildingType]}', style: pw.TextStyle(font: font, fontSize: 9)),
            ]),
            pw.SizedBox(height: 4),
            // v2.10.4: 로비층 정보 추가
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text('층수: ${widget.buildingData.floors}층', style: pw.TextStyle(font: font, fontSize: 9)),
              pw.Text('로비: ${widget.buildingData.lobbyFloors}층', style: pw.TextStyle(font: font, fontSize: 9)),
              pw.Text('인구: ${formatNumber(widget.buildingData.calculatedPopulation)}명', style: pw.TextStyle(font: font, fontSize: 9)),
              pw.Text('승강기: ${widget.buildingData.totalLifts}대', style: pw.TextStyle(font: font, fontSize: 9)),
              pw.Text('정원: ${widget.buildingData.capacity}인승', style: pw.TextStyle(font: font, fontSize: 9)),
            ]),
          ])),
        pw.SizedBox(height: 8),
        
        pw.Text('2. 운행방식 비교 (${results?.length ?? 0}가지)', style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColor.fromHex('#1565C0'))),
        pw.Divider(thickness: 1, color: PdfColor.fromHex('#1565C0')),
        pw.SizedBox(height: 4),
        pw.Table(border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          columnWidths: { 0: const pw.FlexColumnWidth(2.0), 1: const pw.FlexColumnWidth(1.1), 2: const pw.FlexColumnWidth(1.1), 3: const pw.FlexColumnWidth(0.9), 4: const pw.FlexColumnWidth(0.9), 5: const pw.FlexColumnWidth(1.2), 6: const pw.FlexColumnWidth(0.9) },
          children: [
            pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: ['운행방식', '평균대기', '피크대기', 'HC5%', '포화도', '월에너지', '혼잡도'].map((h) => pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(h, style: pw.TextStyle(font: fontBold, fontSize: 7), textAlign: pw.TextAlign.center))).toList()),
            ...results!.values.map((r) {
              bool isOptimal = r.controlType == rankedResults![0].controlType;
              bool isCurrent = r.controlType == widget.buildingData.currentControl;
              bool isOverload = r.saturation > 100;
              return pw.TableRow(decoration: isOptimal ? const pw.BoxDecoration(color: PdfColors.amber50) : isCurrent ? const pw.BoxDecoration(color: PdfColors.green50) : null,
                children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text('${r.controlName}${isOptimal ? ' *' : ''}', style: pw.TextStyle(font: isOptimal ? fontBold : font, fontSize: 7))),
                  pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(formatTime(r.awtAvg), style: pw.TextStyle(font: font, fontSize: 7), textAlign: pw.TextAlign.center)),
                  pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(formatTime(r.awtPeak), style: pw.TextStyle(font: font, fontSize: 7), textAlign: pw.TextAlign.center)),
                  pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text('${r.hc5Percent.toStringAsFixed(1)}%', style: pw.TextStyle(font: font, fontSize: 7), textAlign: pw.TextAlign.center)),
                  pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text('${r.saturation.toStringAsFixed(0)}%', style: pw.TextStyle(font: isOverload ? fontBold : font, fontSize: 7, color: isOverload ? PdfColors.red : PdfColors.black), textAlign: pw.TextAlign.center)),
                  pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text('${formatDouble(r.monthlyEnergy)}kWh', style: pw.TextStyle(font: font, fontSize: 7), textAlign: pw.TextAlign.center)),
                  pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text('${r.congestionLevel}%', style: pw.TextStyle(font: font, fontSize: 7), textAlign: pw.TextAlign.center)),
                ]);
            }),
          ]),
        
        if (hasOverloadWarning) ...[
          pw.SizedBox(height: 4),
          pw.Container(padding: const pw.EdgeInsets.all(6), decoration: pw.BoxDecoration(color: PdfColors.red50, borderRadius: pw.BorderRadius.circular(4), border: pw.Border.all(color: PdfColors.red)),
            child: pw.Text('[!] 시스템 포화 상태 - 포화도 100% 초과 운행방식 존재', style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.red800))),
        ],
        pw.SizedBox(height: 8),
        
        // v2.10.4: ESG 건물 전체 라벨
        if (esgResult != null) ...[
          pw.Text('3. ESG 환경 기여도 (건물 전체 연간)', style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColor.fromHex('#1565C0'))),
          pw.Divider(thickness: 1, color: PdfColor.fromHex('#1565C0')),
          pw.SizedBox(height: 4),
          pw.Container(padding: const pw.EdgeInsets.all(10), decoration: pw.BoxDecoration(color: PdfColors.green50, borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceAround, children: [
              pw.Column(children: [pw.Text('[E] 에너지 절감', style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.orange700)), pw.SizedBox(height: 2), pw.Text('${formatDouble(esgResult!.annualEnergySaving)} kWh', style: pw.TextStyle(font: fontBold, fontSize: 12, color: PdfColors.orange800))]),
              pw.Column(children: [pw.Text('[C] CO2 감소', style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.blue700)), pw.SizedBox(height: 2), pw.Text('${formatDouble(esgResult!.annualCarbonReduction, 1)} kg', style: pw.TextStyle(font: fontBold, fontSize: 12, color: PdfColors.blue800))]),
              pw.Column(children: [pw.Text('[T] 소나무 환산', style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.green700)), pw.SizedBox(height: 2), pw.Text('${formatNumber(esgResult!.pineTreeEquivalent)} 그루', style: pw.TextStyle(font: fontBold, fontSize: 12, color: PdfColors.green800))]),
            ])),
          pw.SizedBox(height: 8),
        ],
        
        pw.Text('4. 핵심 진단 결과', style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColor.fromHex('#1565C0'))),
        pw.Divider(thickness: 1, color: PdfColor.fromHex('#1565C0')),
        pw.SizedBox(height: 4),
        pw.Container(padding: const pw.EdgeInsets.all(10), decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.amber, width: 2), borderRadius: pw.BorderRadius.circular(8)),
          child: pw.Column(children: [
            pw.Row(children: [
              pw.Expanded(child: pw.Container(padding: const pw.EdgeInsets.all(8), decoration: pw.BoxDecoration(color: PdfColors.grey200, borderRadius: pw.BorderRadius.circular(6)),
                child: pw.Column(children: [pw.Text('현재 방식', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey700)), pw.Text(current.controlName, style: pw.TextStyle(font: fontBold, fontSize: 10)), pw.Text('평균 ${formatTime(current.awtAvg)}', style: pw.TextStyle(font: font, fontSize: 8))]))),
              pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 8), child: pw.Text('->', style: pw.TextStyle(font: fontBold, fontSize: 16, color: PdfColors.green700))),
              pw.Expanded(child: pw.Container(padding: const pw.EdgeInsets.all(8), decoration: pw.BoxDecoration(color: PdfColors.green50, borderRadius: pw.BorderRadius.circular(6), border: pw.Border.all(color: PdfColors.green, width: 1)),
                child: pw.Column(children: [pw.Text('* 추천 방식', style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.green800)), pw.Text(best.controlName, style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.green900)), pw.Text('평균 ${formatTime(best.awtAvg)}', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.green800))]))),
            ]),
            pw.SizedBox(height: 8),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceAround, children: [
              pw.Column(children: [pw.Text('대기시간 단축', style: pw.TextStyle(font: font, fontSize: 8)), pw.Text('${awtImprovement.toStringAsFixed(0)}%', style: pw.TextStyle(font: fontBold, fontSize: 12, color: PdfColors.blue700))]),
              pw.Column(children: [pw.Text('에너지 절감', style: pw.TextStyle(font: font, fontSize: 8)), pw.Text('${energyImprovement.toStringAsFixed(0)}%', style: pw.TextStyle(font: fontBold, fontSize: 12, color: PdfColors.green700))]),
              pw.Column(children: [pw.Text('연간 비용 절감', style: pw.TextStyle(font: font, fontSize: 8)), pw.Text('${formatCurrency(yearlySaving)}원', style: pw.TextStyle(font: fontBold, fontSize: 12, color: PdfColors.amber800))]),
            ]),
          ])),
        
        pw.SizedBox(height: 12),
        
        // v2.10.8 FIX: 섹션 5 전폭 확대
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(12), 
          decoration: pw.BoxDecoration(
            color: PdfColors.blue50, 
            borderRadius: pw.BorderRadius.circular(8), 
            border: pw.Border.all(color: PdfColors.blue300, width: 1.5)
          ),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Row(children: [
              pw.Container(padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: pw.BoxDecoration(color: PdfColors.blue700, borderRadius: pw.BorderRadius.circular(4)),
                child: pw.Text('5', style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.white))),
              pw.SizedBox(width: 6),
              pw.Text('종합 분석 의견', style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.blue800)),
            ]),
            pw.SizedBox(height: 8),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(color: PdfColors.white, borderRadius: pw.BorderRadius.circular(4)),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('■ 현재 상태 분석', style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.grey700)),
                pw.SizedBox(height: 3),
                pw.Text('현재 ${current.controlName} 방식에서 ${best.controlName} 방식으로 전환 시 대기시간 ${awtImprovement.toStringAsFixed(0)}% 개선이 예상됩니다.', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey800)),
                pw.SizedBox(height: 6),
                pw.Text('■ 기대 효과', style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.grey700)),
                pw.SizedBox(height: 3),
                pw.Text('연간 약 ${formatCurrency(yearlySaving)}원의 비용 절감 및 ${formatDouble(esgResult?.annualCarbonReduction ?? 0, 1)}kg CO2 감소 효과가 있습니다.', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey800)),
                pw.SizedBox(height: 6),
                pw.Text('■ 권고사항', style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.grey700)),
                pw.SizedBox(height: 3),
                hasOverloadWarning 
                  ? pw.Text('[주의] 일부 운행방식에서 시스템 과부하가 감지되어 승강기 증설 검토가 권장됩니다.', style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.red700))
                  : pw.Text('현재 승강기 대수는 건물 수요에 적합한 것으로 분석됩니다.', style: pw.TextStyle(font: font, fontSize: 8, color: PdfColors.grey800)),
              ]),
            ),
          ]),
        ),
        pw.SizedBox(height: 8),
        
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(8), 
          decoration: pw.BoxDecoration(color: PdfColors.grey100, borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('* 참고사항', style: pw.TextStyle(font: fontBold, fontSize: 8, color: PdfColors.grey700)),
            pw.SizedBox(height: 3),
            pw.Text('- 본 분석은 한국승강기안전공단 기준 및 국제 표준(ISO 8100-32, CIBSE Guide D)을 기반으로 합니다.', style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey600)),
            pw.Text('- 실제 성능은 건물 구조, 이용 패턴, 장비 상태에 따라 달라질 수 있습니다.', style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey600)),
            pw.Text('- 트윈(30층+, 3대+), 더블데크(35층+, 4대+)는 대규모 고층 건물에서 권장됩니다.', style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey600)),
          ])),
        pw.SizedBox(height: 6),
        pw.Center(child: pw.Text('AI-Compass v2.10.8 | 한국승강기안전공단 기준 준수', style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey500))),
      ]),
    ));

    return pdf;
  }

  Future<void> _generatePDF() async { try { final pdf = await _createPDF(); await Printing.layoutPdf(onLayout: (format) => pdf.save()); } catch (e) { if (mounted) Fluttertoast.showToast(msg: 'PDF 오류: $e'); } }
  Future<void> _sharePDF() async { try { final pdf = await _createPDF(); await Printing.sharePdf(bytes: await pdf.save(), filename: 'AI-Compass_${widget.buildingData.buildingName}.pdf'); } catch (e) { if (mounted) Fluttertoast.showToast(msg: '공유 오류: $e'); } }
}

// ============================================================
// What-If 분석 다이얼로그
// ============================================================
class WhatIfAnalysisDialog extends StatefulWidget {
  final BuildingData buildingData;
  final Map<String, dynamic> baseResults;
  const WhatIfAnalysisDialog({super.key, required this.buildingData, required this.baseResults});
  @override
  State<WhatIfAnalysisDialog> createState() => _WhatIfAnalysisDialogState();
}

class _WhatIfAnalysisDialogState extends State<WhatIfAnalysisDialog> {
  WhatIfScenario? _selectedScenario;
  Map<String, dynamic>? _analysisResult;
  bool _isLoading = false;

  // v2.10.8: 시나리오 정리 (3개만 유지)
  final _scenarios = [
    (WhatIfScenario.liftOutOfService, '🔧 1대 고장 시', '승강기 1대 운휴 상황'),
    (WhatIfScenario.populationIncrease, '📈 입주율 120%', '건물 입주율 20% 증가'),
    (WhatIfScenario.peakOverload, '🔥 피크 150%', '피크 사용률 50% 증가'),
  ];

  Future<void> _runAnalysis() async {
    if (_selectedScenario == null) return;
    setState(() => _isLoading = true);
    
    final result = await GPTCalculator().analyzeWhatIfScenario(
      scenario: _selectedScenario!,
      floors: widget.buildingData.floors,
      lifts: widget.buildingData.lifts,
      capacity: widget.buildingData.capacity,
      ratedSpeed: widget.buildingData.ratedSpeed,
      population: widget.buildingData.calculatedPopulation,
      peakUsagePercent: widget.buildingData.peakUsagePercent,
      currentControl: widget.buildingData.currentControl,
    );
    
    setState(() { _analysisResult = result; _isLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(children: [Icon(Icons.science, color: accentColor), SizedBox(width: 8), Text('🔬 What-If 시나리오')]),
      content: SizedBox(width: 400, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('가상 시나리오를 선택하세요:', style: TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 12),
        ..._scenarios.map((s) => RadioListTile<WhatIfScenario>(value: s.$1, groupValue: _selectedScenario, onChanged: (v) => setState(() => _selectedScenario = v), title: Text(s.$2), subtitle: Text(s.$3, style: const TextStyle(fontSize: 12)), dense: true)),
        const SizedBox(height: 16),
        if (_analysisResult != null) _buildResultCard(),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기')),
        ElevatedButton(onPressed: _isLoading || _selectedScenario == null ? null : _runAnalysis, child: _isLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('분석 실행')),
      ],
    );
  }

  Widget _buildResultCard() {
    final result = _analysisResult!;
    final severity = result['severity'];
    final color = severity == 'critical' ? errorColor : severity == 'warning' ? warningColor : successColor;
    final impactPercent = (result['impactPercent'] as double?) ?? 0.0;
    
    return Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(severity == 'critical' ? Icons.error : severity == 'warning' ? Icons.warning : Icons.check_circle, color: color, size: 20), const SizedBox(width: 8), Text(result['scenarioName'] ?? '', style: TextStyle(fontWeight: FontWeight.bold, color: color))]),
        const SizedBox(height: 8),
        Text('⏱️ 대기시간: ${(result['baseAWT'] as double).toStringAsFixed(0)}초 → ${(result['adjustedAWT'] as double).toStringAsFixed(0)}초'),
        Text('📊 영향도: ${impactPercent.toStringAsFixed(1)}% ${impactPercent > 0 ? '증가 ↑' : '감소 ↓'}', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        if (result['energyChange'] != null && (result['energyChange'] as double).abs() > 1) ...[
          const SizedBox(height: 4),
          Text('⚡ 에너지: ${(result['energyChange'] as double).toStringAsFixed(0)}% ${(result['energyChange'] as double) < 0 ? '절감' : '증가'}'),
        ],
        const Divider(),
        const Text('💡 AI 대응 전략:', style: TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text(result['aiRecommendation'] ?? '', style: const TextStyle(fontSize: 13)),
      ]),
    );
  }
}

// ============================================================
// v2.10.4: 시뮬레이터 - 승객 로드 상태 관리, Twin 샤프트 수정
// ============================================================
class ElevatorSimulatorWidget extends StatefulWidget {
  final int floors, lifts, accessibleLifts, capacity;
  final String currentControl, bestControl, currentName, bestName;
  final double currentAwt, bestAwt, monthlyEnergySaving;

  const ElevatorSimulatorWidget({super.key, required this.floors, required this.lifts, required this.accessibleLifts, required this.capacity, required this.currentControl, required this.bestControl, required this.currentAwt, required this.bestAwt, required this.currentName, required this.bestName, required this.monthlyEnergySaving});

  @override
  State<ElevatorSimulatorWidget> createState() => _ElevatorSimulatorWidgetState();
}

class _ElevatorSimulatorWidgetState extends State<ElevatorSimulatorWidget> with TickerProviderStateMixin {
  final Random _random = Random();
  bool _isRunning = false;
  int _leftPassengers = 0, _rightPassengers = 0;
  Timer? _simulationTimer;
  double _energySaving = 0.0;

  late int _liftCount;
  late int _shaftCount;  // v2.10.8: Twin용 샤프트 수
  
  // v2.10.8: Twin 지원을 위한 Upper/Lower 분리 컨트롤러
  late List<AnimationController> _leftControllers, _rightControllers;
  late List<AnimationController> _leftLowerControllers, _rightLowerControllers;  // Twin Lower
  late List<Animation<double>> _leftAnimations, _rightAnimations;
  late List<Animation<double>> _leftLowerAnimations, _rightLowerAnimations;  // Twin Lower
  
  // v2.10.8: 승객 로드 상태 (Twin Upper/Lower 분리)
  late List<int> _leftCarLoads, _rightCarLoads;
  late List<int> _leftLowerCarLoads, _rightLowerCarLoads;  // Twin Lower
  
  // v2.10.8: Twin 충돌 방지 상수 + 재시도 로직
  static const double _safetyGap = 0.15;  // 15% 최소 간격
  static const int _maxRetries = 5;        // 최대 재시도 횟수
  static const int _retryDelayMs = 100;    // 재시도 딜레이 (ms)

  bool get _isTwinMode => widget.bestControl == 'twin' || widget.currentControl == 'twin';

  @override
  void initState() { 
    super.initState(); 
    _liftCount = max(1, widget.lifts);
    _shaftCount = _isTwinMode ? (_liftCount / 2).ceil() : _liftCount;
    _initAnimations();
  }
  
  void _initAnimations() {
    // 기본 컨트롤러 (Upper Cars)
    _leftControllers = List.generate(_liftCount, (i) => AnimationController(vsync: this, duration: const Duration(milliseconds: 2000)));
    _rightControllers = List.generate(_liftCount, (i) => AnimationController(vsync: this, duration: const Duration(milliseconds: 1500)));
    
    _leftAnimations = _leftControllers.map((c) => Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: c, curve: Curves.easeInOutQuad))).toList();
    _rightAnimations = _rightControllers.map((c) => Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: c, curve: Curves.easeInOutQuad))).toList();
    
    // v2.10.8: Twin Lower Cars 컨트롤러
    _leftLowerControllers = List.generate(_shaftCount, (i) => AnimationController(vsync: this, duration: const Duration(milliseconds: 2200)));
    _rightLowerControllers = List.generate(_shaftCount, (i) => AnimationController(vsync: this, duration: const Duration(milliseconds: 1700)));
    
    _leftLowerAnimations = _leftLowerControllers.map((c) => Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: c, curve: Curves.easeInOutQuad))).toList();
    _rightLowerAnimations = _rightLowerControllers.map((c) => Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: c, curve: Curves.easeInOutQuad))).toList();
    
    // 승객 로드 초기화
    _leftCarLoads = List.filled(_liftCount, 0);
    _rightCarLoads = List.filled(_liftCount, 0);
    _leftLowerCarLoads = List.filled(_shaftCount, 0);
    _rightLowerCarLoads = List.filled(_shaftCount, 0);
  }

  @override
  void dispose() { 
    _simulationTimer?.cancel(); 
    for (var c in [..._leftControllers, ..._rightControllers, ..._leftLowerControllers, ..._rightLowerControllers]) c.dispose(); 
    super.dispose(); 
  }

  void _startSimulation() {
    if (_isRunning) return;
    setState(() { 
      _isRunning = true; 
      _leftPassengers = 0; 
      _rightPassengers = 0; 
      _energySaving = 0.0;
      _leftCarLoads = List.filled(_liftCount, 0);
      _rightCarLoads = List.filled(_liftCount, 0);
      _leftLowerCarLoads = List.filled(_shaftCount, 0);
      _rightLowerCarLoads = List.filled(_shaftCount, 0);
    });
    
    // 일반 엘리베이터 시작
    for (int i = 0; i < _liftCount; i++) { 
      Future.delayed(Duration(milliseconds: i * 400), () {
        if (_isRunning) _runElevatorWithBoarding(_leftControllers[i], true, i, isUpper: true);
      });
      Future.delayed(Duration(milliseconds: i * 250), () {
        if (_isRunning) _runElevatorWithBoarding(_rightControllers[i], false, i, isUpper: true);
      });
    }
    
    // v2.10.8: Twin Lower Cars 시작 (샤프트별)
    if (_isTwinMode) {
      for (int i = 0; i < _shaftCount; i++) {
        Future.delayed(Duration(milliseconds: i * 500 + 300), () {
          if (_isRunning) _runTwinLowerCar(_leftLowerControllers[i], true, i);
        });
        Future.delayed(Duration(milliseconds: i * 350 + 200), () {
          if (_isRunning) _runTwinLowerCar(_rightLowerControllers[i], false, i);
        });
      }
    }
    
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 100), (_) { 
      if (mounted && _isRunning) setState(() {}); 
    });
  }

  // ============================================================
  // v2.10.8 FIX: 승객 하차 애니메이션 + Twin Wait & Retry
  // ============================================================
  Future<void> _runElevatorWithBoarding(AnimationController controller, bool isLeft, int index, {bool isUpper = true}) async {
    if (!_isRunning || !mounted) return;
    
    // 목적층 결정
    double targetPos = _calculateTargetPosition(isLeft, index, isUpper: isUpper);
    
    // v2.10.8: Twin 충돌 방지 (Upper Car) - Wait & Retry 로직
    if (_isTwinMode && isUpper && index < _shaftCount) {
      int retries = 0;
      while (retries < _maxRetries) {
        double lowerPos = isLeft ? _leftLowerControllers[index].value : _rightLowerControllers[index].value;
        double minAllowed = lowerPos + _safetyGap;
        
        if (targetPos >= minAllowed) {
          // 안전거리 확보됨
          targetPos = targetPos.clamp(minAllowed, 1.0);
          break;
        } else {
          // Lower Car가 비켜줄 때까지 대기
          await Future.delayed(Duration(milliseconds: _retryDelayMs));
          if (!_isRunning || !mounted) return;
          retries++;
        }
      }
      // 최종 안전 확인: 재시도 후에도 충돌 위험시 강제 조정
      double finalLowerPos = isLeft ? _leftLowerControllers[index].value : _rightLowerControllers[index].value;
      targetPos = max(targetPos, finalLowerPos + _safetyGap).clamp(finalLowerPos + _safetyGap, 1.0);
    }
    
    // 이동 시간
    final moveDuration = isLeft ? (2200 + _random.nextInt(800)) : (1400 + _random.nextInt(600));
    controller.duration = Duration(milliseconds: moveDuration);
    
    // 1. MOVE: 목적층으로 이동 (승객 변화 없음)
    await controller.animateTo(targetPos);
    if (!_isRunning || !mounted) return;
    
    // 2. STOP: 문 열림 (500ms)
    await Future.delayed(const Duration(milliseconds: 500));
    if (!_isRunning || !mounted) return;
    
    // v2.10.8 FIX: 고층 하차 - 일부 승객 하차
    final currentLoad = isLeft ? _leftCarLoads[index] : _rightCarLoads[index];
    final unloadCount = _random.nextInt((currentLoad * 0.6).round() + 1);
    if (mounted && unloadCount > 0) {
      setState(() {
        if (isLeft) {
          _leftCarLoads[index] = max(0, currentLoad - unloadCount);
        } else {
          _rightCarLoads[index] = max(0, currentLoad - unloadCount);
        }
      });
    }
    await Future.delayed(const Duration(milliseconds: 400));
    if (!_isRunning || !mounted) return;
    
    // 4. 고층 승차 - 일부 승객 승차
    final maxLoad = (widget.capacity * 0.8).round();
    final loadCount = _random.nextInt(3);
    final afterUnload = isLeft ? _leftCarLoads[index] : _rightCarLoads[index];
    if (mounted) {
      setState(() {
        if (isLeft) {
          _leftCarLoads[index] = min(maxLoad, afterUnload + loadCount);
        } else {
          _rightCarLoads[index] = min(maxLoad, afterUnload + loadCount);
        }
      });
    }
    
    // 5. DWELL: 대기 (800ms)
    await Future.delayed(const Duration(milliseconds: 800));
    if (!_isRunning || !mounted) return;
    
    // 6. MOVE: 로비로 복귀
    await controller.animateTo(0.0);
    if (!_isRunning || !mounted) return;
    
    // ============================================================
    // v2.10.8 FIX: 로비 도착 - 전원 하차 후 신규 승차
    // ============================================================
    
    // 7. 로비 문 열림 (500ms)
    await Future.delayed(const Duration(milliseconds: 500));
    if (!_isRunning || !mounted) return;
    
    // 8. 로비 하차: 모든 승객 하차 (시각적으로 0명 표시)
    if (mounted) {
      setState(() {
        if (isLeft) {
          _leftCarLoads[index] = 0;  // 전원 하차!
        } else {
          _rightCarLoads[index] = 0;  // 전원 하차!
        }
      });
    }
    await Future.delayed(const Duration(milliseconds: 600));
    if (!_isRunning || !mounted) return;
    
    // 9. 로비 승차: 새 승객 탑승
    final newLoad = _random.nextInt(maxLoad + 1);
    final boardedPassengers = isLeft ? (1 + _random.nextInt(3)) : (2 + _random.nextInt(4));
    if (mounted) {
      setState(() {
        if (isLeft) {
          _leftCarLoads[index] = newLoad;
          _leftPassengers += boardedPassengers;
        } else {
          _rightCarLoads[index] = newLoad;
          _rightPassengers += boardedPassengers;
          _energySaving = min(widget.monthlyEnergySaving, _energySaving + 0.02 + _random.nextDouble() * 0.03);
        }
      });
    }
    
    // 10. 출발 대기 (400ms)
    await Future.delayed(const Duration(milliseconds: 400));
    
    // 11. 루프
    if (_isRunning && mounted) {
      _runElevatorWithBoarding(controller, isLeft, index, isUpper: isUpper);
    }
  }

  // ============================================================
  // v2.10.8 FIX: Twin Lower Car 운행 (Wait & Retry 충돌 방지)
  // ============================================================
  Future<void> _runTwinLowerCar(AnimationController controller, bool isLeft, int shaftIndex) async {
    if (!_isRunning || !mounted) return;
    
    // v2.10.8: Upper Car 위치 확인 + Wait & Retry
    double upperPos = isLeft 
        ? (shaftIndex < _leftControllers.length ? _leftControllers[shaftIndex].value : 0.5) 
        : (shaftIndex < _rightControllers.length ? _rightControllers[shaftIndex].value : 0.5);
    
    // Wait & Retry: Upper가 공간을 확보할 때까지 대기
    int retries = 0;
    double maxAllowed = max(0.0, upperPos - _safetyGap);
    
    while (retries < _maxRetries) {
      upperPos = isLeft 
          ? (shaftIndex < _leftControllers.length ? _leftControllers[shaftIndex].value : 0.5) 
          : (shaftIndex < _rightControllers.length ? _rightControllers[shaftIndex].value : 0.5);
      maxAllowed = max(0.0, upperPos - _safetyGap);
      
      if (maxAllowed > 0.05) {
        // 충분한 공간 확보됨
        break;
      } else {
        // Upper Car가 올라갈 때까지 대기
        await Future.delayed(Duration(milliseconds: _retryDelayMs));
        if (!_isRunning || !mounted) return;
        retries++;
      }
    }
    
    // 목적층 결정 (0 ~ maxAllowed 범위)
    double targetPos = _random.nextDouble() * maxAllowed * 0.8;  // 저층 운행
    targetPos = targetPos.clamp(0.0, maxAllowed);
    
    // 이동 시간
    final moveDuration = isLeft ? (2500 + _random.nextInt(700)) : (1800 + _random.nextInt(500));
    controller.duration = Duration(milliseconds: moveDuration);
    
    // 1. MOVE: 목적층으로 이동
    await controller.animateTo(targetPos);
    if (!_isRunning || !mounted) return;
    
    // 2. STOP & UNLOAD
    await Future.delayed(const Duration(milliseconds: 500));
    if (!_isRunning || !mounted) return;
    
    // 하차
    final loads = isLeft ? _leftLowerCarLoads : _rightLowerCarLoads;
    final currentLoad = loads[shaftIndex];
    final unloadCount = _random.nextInt((currentLoad * 0.5).round() + 1);
    if (mounted) {
      setState(() {
        if (isLeft) {
          _leftLowerCarLoads[shaftIndex] = max(0, currentLoad - unloadCount);
        } else {
          _rightLowerCarLoads[shaftIndex] = max(0, currentLoad - unloadCount);
        }
      });
    }
    await Future.delayed(const Duration(milliseconds: 400));
    if (!_isRunning || !mounted) return;
    
    // 승차
    final maxLoad = (widget.capacity * 0.8).round();
    final loadCount = _random.nextInt(2);
    final afterUnload = isLeft ? _leftLowerCarLoads[shaftIndex] : _rightLowerCarLoads[shaftIndex];
    if (mounted) {
      setState(() {
        if (isLeft) {
          _leftLowerCarLoads[shaftIndex] = min(maxLoad, afterUnload + loadCount);
        } else {
          _rightLowerCarLoads[shaftIndex] = min(maxLoad, afterUnload + loadCount);
        }
      });
    }
    
    // 3. DWELL
    await Future.delayed(const Duration(milliseconds: 600));
    if (!_isRunning || !mounted) return;
    
    // 4. 로비 복귀
    await controller.animateTo(0.0);
    if (!_isRunning || !mounted) return;
    
    // 5. 로비 하차/승차
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) {
      setState(() {
        if (isLeft) {
          _leftLowerCarLoads[shaftIndex] = 0;
        } else {
          _rightLowerCarLoads[shaftIndex] = 0;
        }
      });
    }
    await Future.delayed(const Duration(milliseconds: 500));
    
    final newLoad = _random.nextInt(maxLoad + 1);
    if (mounted) {
      setState(() {
        if (isLeft) {
          _leftLowerCarLoads[shaftIndex] = newLoad;
          _leftPassengers += 1 + _random.nextInt(2);
        } else {
          _rightLowerCarLoads[shaftIndex] = newLoad;
          _rightPassengers += 1 + _random.nextInt(3);
        }
      });
    }
    
    await Future.delayed(const Duration(milliseconds: 300));
    
    // 6. 루프
    if (_isRunning && mounted) {
      _runTwinLowerCar(controller, isLeft, shaftIndex);
    }
  }

  // v2.10.8: Zone/OddEven 목적층 로직 (Upper/Lower 구분)
  double _calculateTargetPosition(bool isLeft, int index, {bool isUpper = true}) {
    String controlType = isLeft ? widget.currentControl : widget.bestControl;
    double maxPos = 1.0;
    double minPos = 0.0;
    
    // Zone 방식: 고층/저층 분리
    if (controlType.contains('zone')) {
      bool isHighZone = index % 2 == 0;
      if (isHighZone) {
        minPos = 0.5;
        maxPos = 1.0;
      } else {
        minPos = 0.1;
        maxPos = 0.5;
      }
    }
    
    // OddEven 방식: 홀수/짝수 층 분리
    if (controlType.contains('oddeven')) {
      double offset = (index % 2 == 0) ? 0.0 : 0.05;
      minPos += offset;
    }
    
    // Twin: Upper는 상층부, Lower는 하층부
    if (controlType == 'twin' && isUpper) {
      minPos = max(minPos, 0.4);  // Upper는 40% 이상
    }
    
    return minPos + _random.nextDouble() * (maxPos - minPos);
  }

  void _stopSimulation() { 
    setState(() => _isRunning = false); 
    _simulationTimer?.cancel(); 
    for (var c in [..._leftControllers, ..._rightControllers, ..._leftLowerControllers, ..._rightLowerControllers]) c.stop(); 
  }
  
  void _resetSimulation() { 
    _stopSimulation(); 
    setState(() { 
      _leftPassengers = 0; 
      _rightPassengers = 0; 
      _energySaving = 0.0;
      _leftCarLoads = List.filled(_liftCount, 0);
      _rightCarLoads = List.filled(_liftCount, 0);
      _leftLowerCarLoads = List.filled(_shaftCount, 0);
      _rightLowerCarLoads = List.filled(_shaftCount, 0);
    }); 
    for (var c in [..._leftControllers, ..._rightControllers, ..._leftLowerControllers, ..._rightLowerControllers]) c.reset(); 
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(padding: const EdgeInsets.symmetric(vertical: 6), decoration: BoxDecoration(color: Colors.orange[50], borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.warning_amber, color: warningColor, size: 16), SizedBox(width: 6), Text('⏰ 출근 시간대 (Up-Peak) 시뮬레이션', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: warningColor))])),
      Padding(padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        ElevatedButton.icon(onPressed: _isRunning ? null : _startSimulation, icon: const Icon(Icons.play_arrow, size: 16), label: const Text('시작', style: TextStyle(fontSize: 12)), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8))),
        const SizedBox(width: 6),
        ElevatedButton.icon(onPressed: _isRunning ? _stopSimulation : null, icon: const Icon(Icons.stop, size: 16), label: const Text('정지', style: TextStyle(fontSize: 12)), style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8))),
        const SizedBox(width: 6),
        ElevatedButton.icon(onPressed: _resetSimulation, icon: const Icon(Icons.refresh, size: 16), label: const Text('초기화', style: TextStyle(fontSize: 12)), style: ElevatedButton.styleFrom(backgroundColor: Colors.grey, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8))),
      ])),
      Expanded(flex: 3, child: Row(children: [
        Expanded(child: Container(margin: const EdgeInsets.fromLTRB(10, 4, 4, 4), decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.orange, width: 2)), child: Column(children: [
          Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.orange[100], borderRadius: const BorderRadius.vertical(top: Radius.circular(8))), child: Column(children: [Text(widget.currentName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10), overflow: TextOverflow.ellipsis), Text('대기: ${formatTime(widget.currentAwt)}', style: TextStyle(fontSize: 9, color: Colors.orange[800]))])),
          Expanded(child: _buildBuildingView(_leftAnimations, _leftCarLoads, Colors.orange, widget.currentControl, _leftLowerAnimations, _leftLowerCarLoads)),
          Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.orange[50], borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8))), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.person, size: 14, color: Colors.orange), Text(' ${formatNumber(_leftPassengers)}명', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11))])),
        ]))),
        Expanded(child: Container(margin: const EdgeInsets.fromLTRB(4, 4, 10, 4), decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.green, width: 2)), child: Column(children: [
          Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.green[100], borderRadius: const BorderRadius.vertical(top: Radius.circular(8))), child: Column(children: [Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.star, size: 10, color: Colors.amber), const SizedBox(width: 2), Flexible(child: Text(widget.bestName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10), overflow: TextOverflow.ellipsis))]), Text('대기: ${formatTime(widget.bestAwt)}', style: TextStyle(fontSize: 9, color: Colors.green[800]))])),
          Expanded(child: _buildBuildingView(_rightAnimations, _rightCarLoads, Colors.green, widget.bestControl, _rightLowerAnimations, _rightLowerCarLoads)),
          Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.green[50], borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8))), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.person, size: 14, color: Colors.green), Text(' ${formatNumber(_rightPassengers)}명', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 11))])),
        ]))),
      ])),
      Expanded(flex: 1, child: Container(
        margin: const EdgeInsets.fromLTRB(10, 2, 10, 8), padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.green)),
        child: Row(children: [
          Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('📊 수송량 차이', style: TextStyle(fontSize: 9, color: Colors.grey)), Text('+${formatNumber(_rightPassengers - _leftPassengers)}명', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green))])),
          Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('📈 효율 향상', style: TextStyle(fontSize: 9, color: Colors.grey)), Text(_leftPassengers > 0 ? '${((_rightPassengers / _leftPassengers - 1) * 100).toStringAsFixed(0)}%' : '-', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green))])),
          Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [const Text('⚡ 에너지 절약', style: TextStyle(fontSize: 9, color: Colors.grey)), if (_isRunning) ...[const SizedBox(width: 3), SizedBox(width: 6, height: 6, child: CircularProgressIndicator(strokeWidth: 1, color: Colors.blue[700]))]]),
            Text('${_energySaving.toStringAsFixed(1)} kWh', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue[700])),
          ])),
        ]),
      )),
    ]);
  }

  // v2.10.8: Twin Lower 애니메이션 지원
  Widget _buildBuildingView(List<Animation<double>> animations, List<int> carLoads, Color color, String controlType, List<Animation<double>> lowerAnimations, List<int> lowerCarLoads) {
    bool isTwin = controlType == 'twin';
    bool isDoubleDeck = controlType == 'double_deck';
    int visibleShafts = (isTwin || isDoubleDeck) ? (widget.lifts / 2).ceil() : widget.lifts;
    
    // v2.10.8: Twin일 때 Lower 애니메이션도 merge
    List<Listenable> allAnimations = [...animations];
    if (isTwin) {
      allAnimations.addAll(lowerAnimations);
    }
    
    return LayoutBuilder(builder: (context, constraints) => AnimatedBuilder(
      animation: Listenable.merge(allAnimations),
      builder: (context, _) => CustomPaint(
        size: Size(constraints.maxWidth, constraints.maxHeight),
        painter: BuildingPainterV2(
          floors: widget.floors, 
          elevatorPositions: animations.map((a) => a.value).toList(),
          lowerPositions: isTwin ? lowerAnimations.map((a) => a.value).toList() : [],  // v2.10.8
          carLoads: carLoads,
          lowerCarLoads: isTwin ? lowerCarLoads : [],  // v2.10.8
          maxLoad: widget.capacity,
          color: color, 
          controlType: controlType, 
          visibleShafts: visibleShafts,
          isTwin: isTwin,
          isDoubleDeck: isDoubleDeck,
        ),
      ),
    ));
  }
}

// ============================================================
// v2.10.8: BuildingPainter - Twin Upper/Lower 독립 렌더링 + 충돌 방지
// ============================================================
class BuildingPainterV2 extends CustomPainter {
  final int floors, visibleShafts, maxLoad;
  final List<double> elevatorPositions;
  final List<double> lowerPositions;  // v2.10.8: Twin Lower
  final List<int> carLoads;
  final List<int> lowerCarLoads;  // v2.10.8: Twin Lower
  final Color color;
  final String controlType;
  final bool isTwin, isDoubleDeck;

  BuildingPainterV2({
    required this.floors, 
    required this.elevatorPositions, 
    required this.lowerPositions,  // v2.10.8
    required this.carLoads,
    required this.lowerCarLoads,  // v2.10.8
    required this.maxLoad,
    required this.color, 
    required this.controlType, 
    required this.visibleShafts,
    this.isTwin = false, 
    this.isDoubleDeck = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final textPainter = TextPainter(textDirection: ui.TextDirection.ltr);
    
    // 배경
    paint.color = Colors.grey[200]!;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(8, 8, size.width - 16, size.height - 16), const Radius.circular(6)), paint);
    
    double floorHeight = (size.height - 36) / floors;
    
    // Zone 분할선
    if (controlType.contains('zone')) { 
      paint.color = Colors.red.withOpacity(0.4); 
      paint.strokeWidth = 2; 
      double midY = size.height - 18 - (floors / 2 * floorHeight); 
      canvas.drawLine(Offset(12, midY), Offset(size.width - 12, midY), paint); 
    }
    
    // 층 그리드
    paint.color = Colors.grey[400]!; 
    paint.strokeWidth = 0.5;
    for (int i = 0; i < floors; i++) {
      double y = size.height - 18 - (i * floorHeight);
      canvas.drawLine(Offset(12, y), Offset(size.width - 12, y), paint);
      int displayFloor = i + 1;
      if (displayFloor % 5 == 0 || displayFloor == 1 || displayFloor == floors) {
        textPainter.text = TextSpan(text: '${displayFloor}F', style: const TextStyle(fontSize: 7, color: Colors.grey));
        textPainter.layout();
        textPainter.paint(canvas, Offset(1, y - 4));
      }
    }
    
    double shaftWidth = (size.width - 40) / max(visibleShafts, 1);
    double carWidth = shaftWidth * 0.6;
    double carHeight = isTwin ? 14 : (isDoubleDeck ? 30 : 20);
    
    for (int i = 0; i < visibleShafts && i < elevatorPositions.length; i++) { 
      double shaftX = 20 + (i * shaftWidth);
      double carX = shaftX + (shaftWidth - carWidth) / 2;
      
      if (isTwin) {
        // ============================================================
        // v2.10.8 FIX: Twin - 독립적 Upper/Lower 위치 사용 + 충돌 방지
        // ============================================================
        double upperPos = elevatorPositions[i];
        double lowerPos = i < lowerPositions.length ? lowerPositions[i] : 0.0;
        
        // 상단 기준 Y 좌표 계산
        double upperY = size.height - 22 - (upperPos * (size.height - 50));
        double lowerY = size.height - 22 - (lowerPos * (size.height - 50));
        
        // v2.10.8: 최소 간격 보장 (충돌 방지 시각화 강화)
        const double minGapPixels = 20.0;
        if (lowerY < upperY + minGapPixels) {
          lowerY = upperY + minGapPixels;
        }
        lowerY = min(lowerY, size.height - 22);
        
        // Upper car (▲)
        int upperLoad = i < carLoads.length ? carLoads[i] : 0;
        _drawElevatorCar(canvas, paint, carX, upperY, carWidth, carHeight, color, upperLoad, true, isUpper: true);
        
        // Lower car (▼) - v2.10.8: 독립적 위치
        int lowerLoad = i < lowerCarLoads.length ? lowerCarLoads[i] : 0;
        _drawElevatorCar(canvas, paint, carX, lowerY, carWidth, carHeight, color.withOpacity(0.75), lowerLoad, false, isUpper: false);
        
      } else if (isDoubleDeck) {
        double y = size.height - 22 - (elevatorPositions[i] * (size.height - 50));
        _drawDoubleDeckCar(canvas, paint, carX, y, carWidth, carHeight, color, i < carLoads.length ? carLoads[i] : 0);
        
      } else {
        double y = size.height - 22 - (elevatorPositions[i] * (size.height - 50));
        _drawElevatorCar(canvas, paint, carX, y, carWidth, carHeight, color, i < carLoads.length ? carLoads[i] : 0, true);
      }
    }
  }
  
  void _drawElevatorCar(Canvas canvas, Paint paint, double x, double y, double width, double height, Color carColor, int load, bool isMain, {bool isUpper = true}) {
    // Car body
    paint.color = carColor;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y - height / 2, width, height), const Radius.circular(3)), paint);
    
    // Window
    paint.color = Colors.white.withOpacity(0.8);
    canvas.drawRect(Rect.fromLTWH(x + 3, y - height / 2 + 3, width - 6, height - 6), paint);
    
    // v2.10.8: 승객 점 표시 (load 기반)
    if (load > 0) {
      int dotsToShow = min(load, 6);
      paint.color = carColor.withOpacity(0.9);
      for (int p = 0; p < dotsToShow; p++) {
        double dotX = x + 5 + (p % 3) * 4;
        double dotY = y - 3 + (p ~/ 3) * 5;
        canvas.drawCircle(Offset(dotX, dotY), 2, paint);
      }
    }
    
    // v2.10.8: Twin 방향 표시 (▲ Upper, ▼ Lower)
    if (isTwin) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: isUpper ? '▲' : '▼', 
          style: TextStyle(fontSize: 6, color: isMain ? Colors.white : Colors.white70)
        ),
        textDirection: ui.TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x + width - 8, y - 4));
    }
  }
  
  void _drawDoubleDeckCar(Canvas canvas, Paint paint, double x, double y, double width, double height, Color carColor, int load) {
    paint.color = carColor;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y - height / 2, width, height), const Radius.circular(3)), paint);
    
    paint.color = Colors.white.withOpacity(0.8);
    canvas.drawRect(Rect.fromLTWH(x + 3, y - height / 2 + 3, width - 6, height / 2 - 5), paint);
    canvas.drawRect(Rect.fromLTWH(x + 3, y + 2, width - 6, height / 2 - 5), paint);
    
    paint.color = carColor;
    paint.strokeWidth = 2;
    canvas.drawLine(Offset(x, y), Offset(x + width, y), paint);
    
    if (load > 0) {
      int dotsToShow = min(load, 4);
      paint.color = carColor.withOpacity(0.9);
      for (int p = 0; p < dotsToShow; p++) {
        double dotX = x + 5 + (p % 2) * 5;
        double dotY = y - height / 4 + (p ~/ 2) * (height / 2);
        canvas.drawCircle(Offset(dotX, dotY), 2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
