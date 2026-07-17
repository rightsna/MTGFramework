import 'package:flutter/material.dart';

import '../models/dialogue_beat.dart';

/// 샷 상태별 색(칸반). 캔버스 아이콘·인스펙터 칩이 공유.
Color statusColor(BeatStatus s) => switch (s) {
      BeatStatus.ready => const Color(0xFF8A8F98), // 준비 · 회색
      BeatStatus.inProgress => const Color(0xFF4C9AFF), // 진행 · 파랑
      BeatStatus.review => const Color(0xFFE0A94A), // 검토 · 앰버
      BeatStatus.rejected => const Color(0xFFF2555A), // 반려 · 빨강
      BeatStatus.done => const Color(0xFF3FB77E), // 완료 · 초록
    };

/// 샷 상태별 아이콘.
IconData statusIcon(BeatStatus s) => switch (s) {
      BeatStatus.ready => Icons.radio_button_unchecked,
      BeatStatus.inProgress => Icons.timelapse,
      BeatStatus.review => Icons.visibility_outlined,
      BeatStatus.rejected => Icons.replay,
      BeatStatus.done => Icons.check_circle,
    };

/// 화면 전반에서 공유하는 색/레이아웃 상수.
const accent = Color(0xFF8B7BFF);
const accent2 = Color(0xFF5BD1C0);
const previewBg = Color(0xFF10131A);
const panelBg = Color(0xFF161A23);

// 캔버스 카드 레이아웃.
const double cardW = 220;
const double cardH = 268;
const double gap = 64;
const double padX = 48;
const double padY = 40;

// 사이드 패널 폭.
const double inspectorW = 392;
const double playerW = 360;
const double sceneListW = 260;
