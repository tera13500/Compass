// gpt_calculator.dart
// AI-Compass v2.10.8 - Groq API Integration
// ============================================================
// v2.10.8 핵심 변경:
// - Groq API로 전환 (llama-3.3-70b-versatile)
// - OpenAI 호환 포맷 사용
// - 에러 처리 강화 (Local-Mode 자동 전환)
// ============================================================

import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

// ============================================================
// What-If 시나리오 Enum
// ============================================================
enum WhatIfScenario {
  liftOutOfService,
  populationIncrease,
  peakOverload,
  speedReduction,
  capacityReduction,
}

class GPTCalculator {
  // ============================================================
  // Groq API Configuration
  // ============================================================
  static const String _baseUrl = 'https://api.groq.com/openai/v1/chat/completions';
  static const String _model = 'llama-3.3-70b-versatile';
  static const String _apiKey = 'YOUR_GROQ_API_KEY';  // 사용자가 설정
  static const Duration _timeout = Duration(seconds: 30);
  
  // API Key 유효성 확인
  static bool get hasApiKey => _apiKey.isNotEmpty && _apiKey != 'YOUR_GROQ_API_KEY';
  
  // 에러 상태 저장 (UI 표시용)
  static String? lastError;
  
  // ============================================================
  // 주요 건물 분석 API (main.dart 호환)
  // ============================================================
  Future<Map<String, dynamic>> calculateWithAI({
    required String buildingName,
    required String buildingType,
    required int floors,
    required int lifts,
    required int accessibleLifts,
    required int capacity,
    required double ratedSpeed,
    required String currentControl,
    required int peoplePerFloor,
    int? totalPopulation,
    required double peakUsagePercent,
    required int lobbyFloors,
  }) async {
    lastError = null;
    
    // 인구 계산
    int population = totalPopulation ?? ((floors - lobbyFloors) * peoplePerFloor);
    
    try {
      if (hasApiKey) {
        final aiResult = await _callGroqForAnalysis(
          buildingType: buildingType,
          floors: floors,
          lifts: lifts,
          accessibleLifts: accessibleLifts,
          capacity: capacity,
          speed: ratedSpeed,
          population: population,
          peakPercent: peakUsagePercent,
          currentControl: currentControl,
        );
        
        if (aiResult != null) {
          return _buildResultMap(
            floors: floors,
            lifts: lifts,
            accessibleLifts: accessibleLifts,
            capacity: capacity,
            speed: ratedSpeed,
            population: population,
            peakPercent: peakUsagePercent,
            currentControl: currentControl,
            aiData: aiResult,
            source: 'AI-Hybrid',
          );
        }
      }
      
      // API 실패 또는 키 없음 → 로컬 계산
      return _calculateLocalFull(
        floors: floors,
        lifts: lifts,
        accessibleLifts: accessibleLifts,
        capacity: capacity,
        speed: ratedSpeed,
        population: population,
        peakPercent: peakUsagePercent,
        currentControl: currentControl,
      );
      
    } catch (e) {
      lastError = e.toString();
      return _calculateLocalFull(
        floors: floors,
        lifts: lifts,
        accessibleLifts: accessibleLifts,
        capacity: capacity,
        speed: ratedSpeed,
        population: population,
        peakPercent: peakUsagePercent,
        currentControl: currentControl,
      );
    }
  }

  // ============================================================
  // What-If 시나리오 분석
  // ============================================================
  Future<Map<String, dynamic>> analyzeWhatIfScenario({
    required WhatIfScenario scenario,
    required int floors,
    required int lifts,
    required int capacity,
    required double ratedSpeed,
    required int population,
    required double peakUsagePercent,
    required String currentControl,
  }) async {
    lastError = null;
    
    // 시나리오별 파라미터 조정
    int adjLifts = lifts;
    int adjPopulation = population;
    double adjPeak = peakUsagePercent;
    double adjSpeed = ratedSpeed;
    int adjCapacity = capacity;
    
    switch (scenario) {
      case WhatIfScenario.liftOutOfService:
        adjLifts = max(1, lifts - 1);
        break;
      case WhatIfScenario.populationIncrease:
        adjPopulation = (population * 1.2).round();
        break;
      case WhatIfScenario.peakOverload:
        adjPeak = peakUsagePercent * 1.5;
        break;
      case WhatIfScenario.speedReduction:
        adjSpeed = ratedSpeed * 0.7;
        break;
      case WhatIfScenario.capacityReduction:
        adjCapacity = (capacity * 0.8).round();
        break;
    }
    
    try {
      if (hasApiKey) {
        final systemPrompt = '''당신은 엘리베이터 What-If 시나리오 분석 전문가입니다.
시나리오 변경에 따른 영향을 분석하세요.
응답은 JSON 형식으로만 제공하세요.

응답 형식:
{
  "impactLevel": "<high/medium/low>",
  "awtChange": <AWT 변화율 %>,
  "congestionChange": <혼잡도 변화 %>,
  "recommendation": "<100자 이내 대응 전략>",
  "riskLevel": <위험도 1-10>
}''';

        final userPrompt = '''시나리오 분석 요청:
- 시나리오: ${scenario.name}
- 기존 승강기: $lifts대 → 조정: $adjLifts대
- 기존 인구: $population명 → 조정: $adjPopulation명
- 기존 피크: $peakUsagePercent% → 조정: $adjPeak%
- 기존 속도: ${ratedSpeed}m/s → 조정: ${adjSpeed}m/s
- 기존 정원: ${capacity}인 → 조정: ${adjCapacity}인

이 변화가 엘리베이터 서비스에 미치는 영향을 분석하세요.''';

        final response = await _callGroqAPI(systemPrompt, userPrompt);
        if (response != null) {
          final parsed = _parseJsonResponse(response);
          if (parsed != null) {
            return {
              'scenario': scenario.name,
              'impactLevel': parsed['impactLevel'] ?? 'medium',
              'awtChange': _safeDouble(parsed['awtChange']),
              'congestionChange': _safeDouble(parsed['congestionChange']),
              'recommendation': parsed['recommendation'] ?? '',
              'riskLevel': _safeInt(parsed['riskLevel']),
              'adjustedLifts': adjLifts,
              'adjustedPopulation': adjPopulation,
              'adjustedPeak': adjPeak,
              'calculationSource': 'AI-Groq',
            };
          }
        }
      }
      
      // 로컬 폴백
      return _calculateLocalWhatIf(
        scenario: scenario,
        lifts: lifts,
        adjLifts: adjLifts,
        population: population,
        adjPopulation: adjPopulation,
        peakPercent: peakUsagePercent,
        adjPeak: adjPeak,
      );
      
    } catch (e) {
      lastError = e.toString();
      return _calculateLocalWhatIf(
        scenario: scenario,
        lifts: lifts,
        adjLifts: adjLifts,
        population: population,
        adjPopulation: adjPopulation,
        peakPercent: peakUsagePercent,
        adjPeak: adjPeak,
      );
    }
  }

  // ============================================================
  // 멀티피크 시나리오 분석
  // ============================================================
  Future<Map<String, Map<String, dynamic>>> analyzeMultiPeakScenarios({
    required String buildingType,
    required int floors,
    required int lifts,
    required int capacity,
    required double ratedSpeed,
    required int totalPopulation,
    required int lobbyFloors,
  }) async {
    lastError = null;
    
    final scenarios = ['morning_peak', 'lunch_peak', 'evening_peak'];
    final Map<String, Map<String, dynamic>> results = {};
    
    try {
      if (hasApiKey) {
        final systemPrompt = '''당신은 엘리베이터 피크 시간대 분석 전문가입니다.
각 피크 시나리오별 예상 성능을 분석하세요.
응답은 JSON 형식으로만 제공하세요.

응답 형식:
{
  "morning_peak": {"awt": <초>, "congestion": <0-100>, "risk": "<high/medium/low>"},
  "lunch_peak": {"awt": <초>, "congestion": <0-100>, "risk": "<high/medium/low>"},
  "evening_peak": {"awt": <초>, "congestion": <0-100>, "risk": "<high/medium/low>"},
  "recommendation": "<종합 권고사항>"
}''';

        final userPrompt = '''건물 정보:
- 용도: $buildingType
- 층수: $floors층
- 승강기: $lifts대
- 정원: ${capacity}인
- 속도: ${ratedSpeed}m/s
- 총인구: $totalPopulation명

출근/점심/퇴근 피크 시나리오를 분석하세요.''';

        final response = await _callGroqAPI(systemPrompt, userPrompt);
        if (response != null) {
          final parsed = _parseJsonResponse(response);
          if (parsed != null) {
            for (var scenario in scenarios) {
              if (parsed.containsKey(scenario)) {
                final data = parsed[scenario] as Map<String, dynamic>;
                results[scenario] = {
                  'awt': _safeDouble(data['awt']),
                  'congestion': _safeInt(data['congestion']),
                  'risk': data['risk'] ?? 'medium',
                  'calculationSource': 'AI-Groq',
                };
              }
            }
            if (results.isNotEmpty) {
              results['_meta'] = {
                'recommendation': parsed['recommendation'] ?? '',
                'source': 'AI-Groq',
              };
              return results;
            }
          }
        }
      }
      
      // 로컬 폴백
      return _calculateLocalMultiPeak(
        floors: floors,
        lifts: lifts,
        capacity: capacity,
        population: totalPopulation,
      );
      
    } catch (e) {
      lastError = e.toString();
      return _calculateLocalMultiPeak(
        floors: floors,
        lifts: lifts,
        capacity: capacity,
        population: totalPopulation,
      );
    }
  }

  // ============================================================
  // AI 컨설팅 보고서 생성
  // ============================================================
  Future<String> generateAIConsultingReport({
    required Map<String, dynamic> simulationResults,
    required String buildingName,
    required String buildingType,
    required int floors,
    required int lifts,
    required String currentControl,
    required String recommendedControl,
    required double currentAWT,
    required double bestAWT,
    required double annualEnergySaving,
    required double annualCostSaving,
  }) async {
    lastError = null;
    
    try {
      if (hasApiKey) {
        final systemPrompt = '''당신은 엘리베이터 컨설팅 전문가입니다.
건물 분석 결과를 바탕으로 전문 컨설팅 보고서를 작성하세요.
보고서는 한국어로 작성하고, 300-500자 분량으로 작성하세요.
마크다운 형식 없이 일반 텍스트로 작성하세요.''';

        final userPrompt = '''건물 분석 결과:
- 건물명: $buildingName
- 용도: $buildingType
- 층수: $floors층
- 승강기: $lifts대
- 현재 제어방식: $currentControl
- 권장 제어방식: $recommendedControl
- 현재 평균 대기시간: ${currentAWT.toStringAsFixed(1)}초
- 최적화 후 예상 대기시간: ${bestAWT.toStringAsFixed(1)}초
- 연간 에너지 절감: ${annualEnergySaving.toStringAsFixed(0)} kWh
- 연간 비용 절감: ${annualCostSaving.toStringAsFixed(0)}원

위 분석 결과를 바탕으로 전문 컨설팅 보고서를 작성하세요.''';

        final response = await _callGroqAPI(systemPrompt, userPrompt);
        if (response != null && response.isNotEmpty) {
          return response;
        }
      }
      
      // 로컬 폴백
      return _generateLocalReport(
        buildingName: buildingName,
        currentControl: currentControl,
        recommendedControl: recommendedControl,
        currentAWT: currentAWT,
        bestAWT: bestAWT,
        annualEnergySaving: annualEnergySaving,
        annualCostSaving: annualCostSaving,
      );
      
    } catch (e) {
      lastError = e.toString();
      return _generateLocalReport(
        buildingName: buildingName,
        currentControl: currentControl,
        recommendedControl: recommendedControl,
        currentAWT: currentAWT,
        bestAWT: bestAWT,
        annualEnergySaving: annualEnergySaving,
        annualCostSaving: annualCostSaving,
      );
    }
  }

  // ============================================================
  // Groq API 호출
  // ============================================================
  Future<String?> _callGroqAPI(String systemPrompt, String userPrompt) async {
    try {
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': _model,
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': userPrompt},
          ],
          'temperature': 0.3,
          'max_tokens': 2000,
        }),
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices']?[0]?['message']?['content'];
      } else {
        lastError = _getErrorMessage(response.statusCode);
        return null;
      }
    } catch (e) {
      if (e.toString().contains('TimeoutException')) {
        lastError = 'API 요청 시간 초과 (30초)';
      } else {
        lastError = 'API 연결 오류: $e';
      }
      return null;
    }
  }

  // ============================================================
  // Groq 분석 호출 (건물 전체 분석용)
  // ============================================================
  Future<Map<String, dynamic>?> _callGroqForAnalysis({
    required String buildingType,
    required int floors,
    required int lifts,
    required int accessibleLifts,
    required int capacity,
    required double speed,
    required int population,
    required double peakPercent,
    required String currentControl,
  }) async {
    final systemPrompt = '''당신은 엘리베이터 교통 분석 전문가입니다.
ISO 8100-32:2020 및 CIBSE Guide D 표준에 따라 분석합니다.
응답은 JSON 형식으로만 제공하세요.

응답 형식:
{
  "bestControl": "<최적 제어방식>",
  "bestAwt": <최적 AWT 초>,
  "currentAwt": <현재 AWT 초>,
  "congestion": <혼잡도 0-100>,
  "recommendation": "<100자 이내 권고사항>"
}

제어방식: individual, group, zone, oddeven, zone_oddeven, double_deck, dcs, zone_group, group_oddeven, hybrid_dcs, energy_save, twin''';

    final userPrompt = '''건물 분석 요청:
- 용도: $buildingType
- 층수: $floors층
- 승강기: $lifts대 (장애인용 $accessibleLifts대)
- 정원: ${capacity}인
- 속도: ${speed}m/s
- 인구: $population명
- 피크율: $peakPercent%
- 현재 제어: $currentControl

최적 제어방식과 예상 성능을 분석하세요.''';

    final response = await _callGroqAPI(systemPrompt, userPrompt);
    if (response != null) {
      return _parseJsonResponse(response);
    }
    return null;
  }

  // ============================================================
  // HTTP 에러 메시지 (한국어)
  // ============================================================
  static String _getErrorMessage(int statusCode) {
    switch (statusCode) {
      case 400: return '잘못된 요청 형식 (400)';
      case 401: return 'API Key 인증 실패 (401)';
      case 403: return 'API 접근 권한 없음 (403)';
      case 404: return 'API 엔드포인트 없음 (404)';
      case 429: return 'API 호출 한도 초과 (429)';
      case 500: return '서버 내부 오류 (500)';
      case 502: return '게이트웨이 오류 (502)';
      case 503: return '서비스 일시 중단 (503)';
      default: return 'HTTP 오류 ($statusCode)';
    }
  }

  // ============================================================
  // JSON 응답 파싱
  // ============================================================
  Map<String, dynamic>? _parseJsonResponse(String response) {
    try {
      String cleaned = response;
      if (cleaned.contains('```json')) {
        cleaned = cleaned.replaceAll('```json', '').replaceAll('```', '');
      } else if (cleaned.contains('```')) {
        cleaned = cleaned.replaceAll('```', '');
      }
      cleaned = cleaned.trim();
      
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(cleaned);
      if (jsonMatch != null) {
        return jsonDecode(jsonMatch.group(0)!);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // ============================================================
  // 유틸리티 함수
  // ============================================================
  double _safeDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }
  
  int _safeInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  // ============================================================
  // 로컬 전체 계산
  // ============================================================
  Map<String, dynamic> _calculateLocalFull({
    required int floors,
    required int lifts,
    required int accessibleLifts,
    required int capacity,
    required double speed,
    required int population,
    required double peakPercent,
    required String currentControl,
  }) {
    final controlTypes = ['individual', 'group', 'zone', 'oddeven', 'zone_oddeven', 
                          'double_deck', 'dcs', 'zone_group', 'group_oddeven', 
                          'hybrid_dcs', 'energy_save', 'twin'];
    
    final Map<String, dynamic> results = {};
    
    for (var type in controlTypes) {
      final calc = _calculateForControl(
        type: type,
        floors: floors,
        lifts: lifts,
        capacity: capacity,
        speed: speed,
        population: population,
        peakPercent: peakPercent,
      );
      results[type] = calc;
    }
    
    results['_metadata'] = {
      'source': lastError != null ? 'Local-Mode (AI 연결 실패: $lastError)' : 'LOCAL-Calc',
      'timestamp': DateTime.now().toIso8601String(),
    };
    
    return results;
  }

  // ============================================================
  // 제어방식별 계산
  // ============================================================
  Map<String, dynamic> _calculateForControl({
    required String type,
    required int floors,
    required int lifts,
    required int capacity,
    required double speed,
    required int population,
    required double peakPercent,
  }) {
    // 기본 물리 계산
    double interfloorHeight = 3.5;
    double totalHeight = floors * interfloorHeight;
    double travelTime = totalHeight / speed;
    
    // 예상 정지층수
    double expectedStops = floors.toDouble() * (1 - pow((floors - 1) / floors, capacity * 0.8).toDouble());
    expectedStops = expectedStops.clamp(1, floors.toDouble());
    
    // RTT 계산
    double doorTime = 3.0;
    double passengerTime = 1.2;
    double rtt = (2 * travelTime * expectedStops / floors) + 
                 (expectedStops * doorTime) + 
                 (capacity * 0.8 * passengerTime);
    
    // 효율 계수
    double efficiency = _getControlEfficiency(type);
    rtt = rtt / efficiency;
    
    // HC5 계산
    double interval = rtt / lifts;
    double hc5 = (300 / rtt) * capacity * 0.8 * lifts;
    double hc5Percent = (hc5 / population) * 100;
    
    // AWT 계산
    double peakDemand = population * (peakPercent / 100);
    double loadFactor = peakDemand / hc5;
    double awtAvg = interval / 2 * (1 + (loadFactor > 1 ? (loadFactor - 1) : 0));
    awtAvg = awtAvg.clamp(15.0, 180.0);
    double awtPeak = awtAvg * 1.5;
    
    // 혼잡도
    int congestion = (loadFactor * 70).round().clamp(15, 95);
    
    // 포화도
    double saturation = (peakDemand / hc5) * 100;
    
    // 에너지
    double dailyEnergy = lifts * 8 * (1 / efficiency) * 2.5;
    
    return {
      'stops': expectedStops,
      'highestReversal': floors * 0.85,
      'rtt': rtt,
      'interval': interval,
      'hc5': hc5,
      'hc5_percent': hc5Percent,
      'awt_avg': awtAvg,
      'awt_peak': awtPeak,
      'dailyEnergy': dailyEnergy,
      'congestionLevel': congestion,
      'saturation': saturation,
      'regenerationActive': efficiency > 1.2 ? 1.0 : 0.0,
      'meetsSeoulGuideline': awtAvg <= 60 ? 1.0 : 0.0,
    };
  }

  // ============================================================
  // 제어방식별 효율 계수
  // ============================================================
  double _getControlEfficiency(String control) {
    switch (control) {
      case 'individual': return 0.7;
      case 'group': return 1.0;
      case 'zone': return 1.15;
      case 'oddeven': return 1.1;
      case 'zone_oddeven': return 1.2;
      case 'double_deck': return 1.4;
      case 'dcs': return 1.3;
      case 'zone_group': return 1.25;
      case 'group_oddeven': return 1.15;
      case 'hybrid_dcs': return 1.35;
      case 'energy_save': return 0.9;
      case 'twin': return 1.5;
      default: return 1.0;
    }
  }

  // ============================================================
  // 결과 맵 빌드
  // ============================================================
  Map<String, dynamic> _buildResultMap({
    required int floors,
    required int lifts,
    required int accessibleLifts,
    required int capacity,
    required double speed,
    required int population,
    required double peakPercent,
    required String currentControl,
    required Map<String, dynamic> aiData,
    required String source,
  }) {
    final localResults = _calculateLocalFull(
      floors: floors,
      lifts: lifts,
      accessibleLifts: accessibleLifts,
      capacity: capacity,
      speed: speed,
      population: population,
      peakPercent: peakPercent,
      currentControl: currentControl,
    );
    
    // AI 추천 적용
    if (aiData.containsKey('bestControl')) {
      localResults['_aiRecommendation'] = aiData;
    }
    
    localResults['_metadata'] = {
      'source': source,
      'timestamp': DateTime.now().toIso8601String(),
    };
    
    return localResults;
  }

  // ============================================================
  // 로컬 What-If 폴백
  // ============================================================
  Map<String, dynamic> _calculateLocalWhatIf({
    required WhatIfScenario scenario,
    required int lifts,
    required int adjLifts,
    required int population,
    required int adjPopulation,
    required double peakPercent,
    required double adjPeak,
  }) {
    double awtChange = 0;
    int congestionChange = 0;
    String impact = 'medium';
    int riskLevel = 5;
    
    switch (scenario) {
      case WhatIfScenario.liftOutOfService:
        awtChange = ((lifts / adjLifts) - 1) * 100;
        congestionChange = 15;
        impact = 'high';
        riskLevel = 7;
        break;
      case WhatIfScenario.populationIncrease:
        awtChange = ((adjPopulation / population) - 1) * 80;
        congestionChange = 12;
        impact = 'medium';
        riskLevel = 5;
        break;
      case WhatIfScenario.peakOverload:
        awtChange = ((adjPeak / peakPercent) - 1) * 100;
        congestionChange = 20;
        impact = 'high';
        riskLevel = 8;
        break;
      case WhatIfScenario.speedReduction:
        awtChange = 30;
        congestionChange = 10;
        impact = 'medium';
        riskLevel = 4;
        break;
      case WhatIfScenario.capacityReduction:
        awtChange = 25;
        congestionChange = 15;
        impact = 'medium';
        riskLevel = 5;
        break;
    }
    
    return {
      'scenario': scenario.name,
      'impactLevel': impact,
      'awtChange': awtChange.roundToDouble(),
      'congestionChange': congestionChange,
      'recommendation': _getScenarioRecommendation(scenario),
      'riskLevel': riskLevel,
      'adjustedLifts': adjLifts,
      'adjustedPopulation': adjPopulation,
      'adjustedPeak': adjPeak,
      'calculationSource': 'Local-Mode',
    };
  }

  String _getScenarioRecommendation(WhatIfScenario scenario) {
    switch (scenario) {
      case WhatIfScenario.liftOutOfService:
        return '비상 운행 프로토콜 가동 및 신속한 수리 대응 필요';
      case WhatIfScenario.populationIncrease:
        return '피크 시간대 급행 운행 강화 검토 필요';
      case WhatIfScenario.peakOverload:
        return '출퇴근 시간 분산 정책 및 추가 승강기 검토';
      case WhatIfScenario.speedReduction:
        return '정기 점검 일정 확인 및 속도 복구 조치';
      case WhatIfScenario.capacityReduction:
        return '탑승 인원 제한 안내 및 운행 빈도 조정';
    }
  }

  // ============================================================
  // 로컬 멀티피크 폴백
  // ============================================================
  Map<String, Map<String, dynamic>> _calculateLocalMultiPeak({
    required int floors,
    required int lifts,
    required int capacity,
    required int population,
  }) {
    double baseAwt = 45.0;
    
    return {
      'morning_peak': {
        'awt': baseAwt * 1.3,
        'congestion': 75,
        'risk': 'high',
        'calculationSource': 'Local-Mode',
      },
      'lunch_peak': {
        'awt': baseAwt * 1.1,
        'congestion': 55,
        'risk': 'medium',
        'calculationSource': 'Local-Mode',
      },
      'evening_peak': {
        'awt': baseAwt * 1.25,
        'congestion': 70,
        'risk': 'high',
        'calculationSource': 'Local-Mode',
      },
      '_meta': {
        'recommendation': '출퇴근 피크 시간대에 급행 운행 모드 활성화를 권장합니다.',
        'source': 'Local-Mode',
      },
    };
  }

  // ============================================================
  // 로컬 보고서 폴백
  // ============================================================
  String _generateLocalReport({
    required String buildingName,
    required String currentControl,
    required String recommendedControl,
    required double currentAWT,
    required double bestAWT,
    required double annualEnergySaving,
    required double annualCostSaving,
  }) {
    final improvement = ((currentAWT - bestAWT) / currentAWT * 100).toStringAsFixed(1);
    
    return '''[$buildingName 엘리베이터 시스템 컨설팅 보고서]

현재 운영 중인 $currentControl 방식에서 $recommendedControl 방식으로 전환 시 약 $improvement%의 성능 개선이 예상됩니다.

현재 평균 대기시간 ${currentAWT.toStringAsFixed(1)}초에서 ${bestAWT.toStringAsFixed(1)}초로 단축되어 입주자 만족도 향상이 기대됩니다.

연간 ${annualEnergySaving.toStringAsFixed(0)}kWh의 에너지 절감과 ${annualCostSaving.toStringAsFixed(0)}원의 비용 절감 효과가 있습니다.

권장사항: 피크 시간대 운행 패턴 최적화 및 정기적인 성능 모니터링을 통해 지속적인 서비스 품질 관리가 필요합니다.''';
  }
}
