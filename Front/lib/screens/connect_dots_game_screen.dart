
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/magic_ui.dart';

class ConnectDotsGameScreen extends StatefulWidget {
  const ConnectDotsGameScreen({super.key});

  @override
  State<ConnectDotsGameScreen> createState() => _ConnectDotsGameScreenState();
}

class _ConnectDotsGameScreenState extends State<ConnectDotsGameScreen> {
  static const String _assetsPrefix = 'assets/images/games/connect_dots/';
  static const List<String> _preferredImageExtensions = <String>[
    '.webp',
    '.png',
    '.jpg',
    '.jpeg',
  ];

  List<_DotPicture> _pictures = <_DotPicture>[];
  bool _loading = true;
  String? _loadError;
  int _pictureIndex = 0;
  int _connectedCount = 0;
  int? _wrongPoint;
  bool _completed = false;
  int _sessionToken = 0;

  _DotPicture get _picture => _pictures[_pictureIndex];

  @override
  void initState() {
    super.initState();
    _loadPictures();
  }

  Future<void> _loadPictures() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final allAssets = manifest.listAssets();
      final assetByLower = <String, String>{
        for (final asset in allAssets) asset.toLowerCase(): asset,
      };
      final svgAssets = allAssets
          .where((asset) =>
              asset.startsWith(_assetsPrefix) &&
              asset.toLowerCase().endsWith('.svg'))
          .toList()
        ..sort();

      final pictures = <_DotPicture>[];
      for (final svgAsset in svgAssets) {
        final base = svgAsset.substring(0, svgAsset.length - 4);
        String? imageAsset;
        for (final extension in _preferredImageExtensions) {
          final candidate = assetByLower['${base.toLowerCase()}$extension'];
          if (candidate != null) {
            imageAsset = candidate;
            break;
          }
        }
        if (imageAsset == null) continue;

        final svg = await rootBundle.loadString(svgAsset);
        final picture = _parseSvgLevel(
          svgAsset: svgAsset,
          imageAsset: imageAsset,
          svg: svg,
        );
        if (picture != null) pictures.add(picture);
      }

      if (!mounted) return;
      setState(() {
        _pictures = pictures;
        _loading = false;
        _loadError = pictures.isEmpty
            ? 'В папке connect_dots не найдено ни одной пары SVG + WEBP.'
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Не удалось загрузить уровни игры.';
      });
    }
  }

  _DotPicture? _parseSvgLevel({
    required String svgAsset,
    required String imageAsset,
    required String svg,
  }) {
    String? attribute(String name) =>
        RegExp('$name="([^"]+)"').firstMatch(svg)?.group(1);

    List<Offset> raw = <Offset>[];
    List<Offset> preferred = <Offset>[];

    final rawPoints = RegExp(
      r'<polygon\b[^>]*\bpoints="([^"]+)"',
      caseSensitive: false,
    ).firstMatch(svg)?.group(1);

    if (rawPoints != null && rawPoints.trim().isNotEmpty) {
      for (final token in rawPoints.trim().split(RegExp(r'\s+'))) {
        final pair = token.split(',');
        if (pair.length != 2) continue;
        final x = double.tryParse(pair[0]);
        final y = double.tryParse(pair[1]);
        if (x != null && y != null) raw.add(Offset(x, y));
      }
      if (raw.length >= 3 && (raw.first - raw.last).distance > .001) {
        raw.add(raw.first);
      }
    } else {
      final pathMatches = RegExp(
        r'<path\b[^>]*\bd="([^"]+)"',
        caseSensitive: false,
      ).allMatches(svg);

      _SvgPathGeometry? best;
      for (final match in pathMatches) {
        final d = match.group(1);
        if (d == null || d.trim().isEmpty) continue;
        final geometry = _svgPathToGeometry(d);
        if (geometry.raw.length < 4) continue;
        if (best == null || geometry.totalLength > best.totalLength) {
          best = geometry;
        }
      }

      if (best == null) return null;
      raw = best.raw;
      preferred = best.guidePoints;
    }

    if (raw.length < 4) return null;

    // Важно: координаты точек должны жить в той же системе координат,
    // что и PNG. Раньше контур искусственно растягивался до targetSpan=.72
    // относительно собственных min/max. На реальных экранах это приводило
    // к несовпадению SVG-точек с PNG и иногда к визуальному "схлопыванию"
    // точек в центре. Теперь источником истины является viewBox SVG.
    final viewBox = _parseSvgViewBox(svg, raw);
    final sourceWidth = math.max(1.0, viewBox.width);
    final sourceHeight = math.max(1.0, viewBox.height);
    final sourceAspectRatio = sourceWidth / sourceHeight;

    // Для выбора безопасно разнесённых точек используем канонический квадрат
    // с тем же BoxFit.contain, который затем применяется на игровом поле.
    double fitWidth;
    double fitHeight;
    double fitLeft;
    double fitTop;
    if (sourceAspectRatio >= 1) {
      fitWidth = 1;
      fitHeight = 1 / sourceAspectRatio;
      fitLeft = 0;
      fitTop = (1 - fitHeight) / 2;
    } else {
      fitHeight = 1;
      fitWidth = sourceAspectRatio;
      fitLeft = (1 - fitWidth) / 2;
      fitTop = 0;
    }

    Offset toCanonical(Offset p) {
      final u = ((p.dx - viewBox.left) / sourceWidth)
          .clamp(0.0, 1.0)
          .toDouble();
      final v = ((p.dy - viewBox.top) / sourceHeight)
          .clamp(0.0, 1.0)
          .toDouble();
      return Offset(
        fitLeft + u * fitWidth,
        fitTop + v * fitHeight,
      );
    }

    Offset canonicalToUv(Offset p) => Offset(
          ((p.dx - fitLeft) / math.max(.000001, fitWidth))
              .clamp(0.0, 1.0)
              .toDouble(),
          ((p.dy - fitTop) / math.max(.000001, fitHeight))
              .clamp(0.0, 1.0)
              .toDouble(),
        );

    final canonical = raw.map(toCanonical).toList(growable: false);
    final canonicalPreferred =
        preferred.map(toCanonical).toList(growable: false);

    final canonicalPoints = _buildSafeDotPoints(
      canonical,
      preferredPoints: canonicalPreferred,
    );
    if (canonicalPoints.length < 6) return null;

    // В модели храним координаты 0..1 относительно исходного viewBox.
    // Позже они переводятся в фактический Rect PNG на конкретном устройстве.
    final points = canonicalPoints.map(canonicalToUv).toList(growable: false);

    final fallbackName = svgAsset
        .split('/')
        .last
        .replaceAll(RegExp(r'\.svg$', caseSensitive: false), '');
    final name = attribute('data-name') ?? _fallbackDisplayName(fallbackName);
    final color = _parseColor(attribute('data-color')) ??
        _fallbackStrokeColor(fallbackName) ??
        const Color(0xFF4E7DDE);

    return _DotPicture(
      name: name,
      color: color,
      points: points,
      imageAsset: imageAsset,
      sourceAspectRatio: sourceAspectRatio,
    );
  }

  Rect _parseSvgViewBox(String svg, List<Offset> raw) {
    final match = RegExp(
      r'\bviewBox\s*=\s*"([^"]+)"',
      caseSensitive: false,
    ).firstMatch(svg);

    if (match != null) {
      final parts = match
          .group(1)!
          .trim()
          .split(RegExp(r'[\s,]+'))
          .map(double.tryParse)
          .toList(growable: false);
      if (parts.length == 4 && parts.every((value) => value != null)) {
        final left = parts[0]!;
        final top = parts[1]!;
        final width = parts[2]!;
        final height = parts[3]!;
        if (width > 0 && height > 0) {
          return Rect.fromLTWH(left, top, width, height);
        }
      }
    }

    // Fallback для SVG без viewBox: используем фактические границы контура.
    final minX = raw.map((p) => p.dx).reduce(math.min);
    final maxX = raw.map((p) => p.dx).reduce(math.max);
    final minY = raw.map((p) => p.dy).reduce(math.min);
    final maxY = raw.map((p) => p.dy).reduce(math.max);
    return Rect.fromLTWH(
      minX,
      minY,
      math.max(1.0, maxX - minX),
      math.max(1.0, maxY - minY),
    );
  }

  String _fallbackDisplayName(String baseName) {
    switch (baseName.toLowerCase()) {
      case 'apple':
        return 'Яблоко';
      case 'butterfly':
        return 'Бабочка';
      case 'cloud':
        return 'Облачко';
      case 'dragon':
        return 'Дракон';
      case 'fish':
        return 'Рыбка';
      case 'ship':
        return 'Кораблик';
      case 'car':
        return 'Машинка';
      case 'star':
        return 'Звёздочка';
      case 'sun':
        return 'Солнышко';
      case 'tree':
        return 'Ёлочка';
      case 'heart':
        return 'Сердечко';
      case 'house':
        return 'Домик';
      default:
        return baseName;
    }
  }

  Color? _fallbackStrokeColor(String baseName) {
    switch (baseName.toLowerCase()) {
      case 'apple':
        return const Color(0xFFFF5E66);
      case 'butterfly':
        return const Color(0xFF9A69E0);
      case 'cloud':
        return const Color(0xFF74B7EA);
      case 'dragon':
        return const Color(0xFFFF8D42);
      case 'fish':
        return const Color(0xFFFFB246);
      case 'ship':
        return const Color(0xFFB67B3B);
      case 'car':
        return const Color(0xFFFF6A4A);
      default:
        return null;
    }
  }

  _SvgPathGeometry _svgPathToGeometry(String data) {
    final tokenMatches = RegExp(
      r'[A-Za-z]|[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?',
    ).allMatches(data);
    final tokens = tokenMatches.map((m) => m.group(0)!).toList(growable: false);
    if (tokens.isEmpty) return const _SvgPathGeometry.empty();

    final raw = <Offset>[];
    final guidePoints = <Offset>[];
    var totalLength = 0.0;

    int i = 0;
    String command = '';
    Offset current = Offset.zero;
    Offset subpathStart = Offset.zero;
    Offset lastCubicControl = Offset.zero;
    Offset lastQuadraticControl = Offset.zero;
    String previousCommand = '';

    bool isCommand(String value) => RegExp(r'^[A-Za-z]$').hasMatch(value);
    double number() => double.parse(tokens[i++]);
    bool hasNumbers(int count) => i + count <= tokens.length && !isCommand(tokens[i]);

    Offset point(bool relative) {
      final p = Offset(number(), number());
      return relative ? current + p : p;
    }

    void ensureStart() {
      if (raw.isEmpty) raw.add(current);
      if (guidePoints.isEmpty) guidePoints.add(current);
    }

    void addLine(Offset p, {bool addGuide = true}) {
      ensureStart();
      totalLength += (p - current).distance;
      raw.add(p);
      current = p;
      if (addGuide) guidePoints.add(p);
    }

    while (i < tokens.length) {
      if (isCommand(tokens[i])) {
        command = tokens[i++];
      } else if (command.isEmpty) {
        break;
      }

      final relative = command == command.toLowerCase();
      final upper = command.toUpperCase();

      switch (upper) {
        case 'M':
          if (!hasNumbers(2)) break;
          current = point(relative);
          subpathStart = current;
          raw.add(current);
          guidePoints.add(current);
          previousCommand = 'M';
          while (hasNumbers(2)) {
            addLine(point(relative));
          }
          break;
        case 'L':
          while (hasNumbers(2)) {
            addLine(point(relative));
          }
          previousCommand = 'L';
          break;
        case 'H':
          while (hasNumbers(1)) {
            final x = number();
            addLine(Offset(relative ? current.dx + x : x, current.dy));
          }
          previousCommand = 'H';
          break;
        case 'V':
          while (hasNumbers(1)) {
            final y = number();
            addLine(Offset(current.dx, relative ? current.dy + y : y));
          }
          previousCommand = 'V';
          break;
        case 'C':
          while (hasNumbers(6)) {
            final start = current;
            final c1 = point(relative);
            final c2 = point(relative);
            final end = point(relative);
            const steps = 20;
            Offset prev = start;
            for (var step = 1; step <= steps; step++) {
              final t = step / steps;
              final mt = 1 - t;
              final p = start * (mt * mt * mt) +
                  c1 * (3 * mt * mt * t) +
                  c2 * (3 * mt * t * t) +
                  end * (t * t * t);
              totalLength += (p - prev).distance;
              raw.add(p);
              prev = p;
            }
            current = end;
            lastCubicControl = c2;
          }
          previousCommand = 'C';
          break;
        case 'S':
          while (hasNumbers(4)) {
            final start = current;
            final c1 = previousCommand == 'C' || previousCommand == 'S'
                ? current * 2 - lastCubicControl
                : current;
            final c2 = point(relative);
            final end = point(relative);
            const steps = 20;
            Offset prev = start;
            for (var step = 1; step <= steps; step++) {
              final t = step / steps;
              final mt = 1 - t;
              final p = start * (mt * mt * mt) +
                  c1 * (3 * mt * mt * t) +
                  c2 * (3 * mt * t * t) +
                  end * (t * t * t);
              totalLength += (p - prev).distance;
              raw.add(p);
              prev = p;
            }
            current = end;
            lastCubicControl = c2;
          }
          previousCommand = 'S';
          break;
        case 'Q':
          while (hasNumbers(4)) {
            final start = current;
            final c = point(relative);
            final end = point(relative);
            const steps = 16;
            Offset prev = start;
            for (var step = 1; step <= steps; step++) {
              final t = step / steps;
              final mt = 1 - t;
              final p = start * (mt * mt) + c * (2 * mt * t) + end * (t * t);
              totalLength += (p - prev).distance;
              raw.add(p);
              prev = p;
            }
            current = end;
            lastQuadraticControl = c;
          }
          previousCommand = 'Q';
          break;
        case 'T':
          while (hasNumbers(2)) {
            final start = current;
            final c = previousCommand == 'Q' || previousCommand == 'T'
                ? current * 2 - lastQuadraticControl
                : current;
            final end = point(relative);
            const steps = 16;
            Offset prev = start;
            for (var step = 1; step <= steps; step++) {
              final t = step / steps;
              final mt = 1 - t;
              final p = start * (mt * mt) + c * (2 * mt * t) + end * (t * t);
              totalLength += (p - prev).distance;
              raw.add(p);
              prev = p;
            }
            current = end;
            lastQuadraticControl = c;
          }
          previousCommand = 'T';
          break;
        case 'A':
          while (hasNumbers(7)) {
            final start = current;
            final rx = number();
            final ry = number();
            final rotationDeg = number();
            final largeArcFlag = number().round() != 0;
            final sweepFlag = number().round() != 0;
            final end = point(relative);

            final arcGeometry = _arcGeometry(
              start: start,
              end: end,
              rx: rx,
              ry: ry,
              rotationDeg: rotationDeg,
              largeArc: largeArcFlag,
              sweep: sweepFlag,
            );

            if (arcGeometry == null) {
              addLine(end);
            } else {
              ensureStart();
              // Правило для SVG arc (A/a): три опорные точки — начало,
              // вершина/середина дуги и конец.
              if (guidePoints.isEmpty ||
                  (guidePoints.last - start).distance > .001) {
                guidePoints.add(start);
              }
              final mid = _pointOnArc(arcGeometry, .5);
              guidePoints.add(mid);
              guidePoints.add(end);
              final arcPoints = <Offset>[];
              const steps = 18;
              for (var step = 1; step <= steps; step++) {
                arcPoints.add(_pointOnArc(arcGeometry, step / steps));
              }
              Offset prev = start;
              for (final p in arcPoints) {
                totalLength += (p - prev).distance;
                raw.add(p);
                prev = p;
              }
              current = end;
            }
          }
          previousCommand = 'A';
          break;
        case 'Z':
          if ((current - subpathStart).distance > .001) {
            addLine(subpathStart, addGuide: false);
          }
          current = subpathStart;
          previousCommand = 'Z';
          command = '';
          break;
        default:
          return const _SvgPathGeometry.empty();
      }
    }

    return _SvgPathGeometry(raw: raw, guidePoints: guidePoints, totalLength: totalLength);
  }

  _ArcGeometry? _arcGeometry({
    required Offset start,
    required Offset end,
    required double rx,
    required double ry,
    required double rotationDeg,
    required bool largeArc,
    required bool sweep,
  }) {
    rx = rx.abs();
    ry = ry.abs();
    if (rx <= 0 || ry <= 0 || (start - end).distance <= .001) return null;

    final phi = rotationDeg * math.pi / 180.0;
    final cosPhi = math.cos(phi);
    final sinPhi = math.sin(phi);
    final dx2 = (start.dx - end.dx) / 2.0;
    final dy2 = (start.dy - end.dy) / 2.0;
    final x1p = cosPhi * dx2 + sinPhi * dy2;
    final y1p = -sinPhi * dx2 + cosPhi * dy2;

    var rxSq = rx * rx;
    var rySq = ry * ry;
    final x1pSq = x1p * x1p;
    final y1pSq = y1p * y1p;

    final lambda = x1pSq / rxSq + y1pSq / rySq;
    if (lambda > 1) {
      final scale = math.sqrt(lambda);
      rx *= scale;
      ry *= scale;
      rxSq = rx * rx;
      rySq = ry * ry;
    }

    final numerator = rxSq * rySq - rxSq * y1pSq - rySq * x1pSq;
    final denom = rxSq * y1pSq + rySq * x1pSq;
    if (denom == 0) return null;
    final sign = (largeArc == sweep) ? -1.0 : 1.0;
    final coef = sign * math.sqrt(math.max(0.0, numerator / denom));
    final cxp = coef * ((rx * y1p) / ry);
    final cyp = coef * (-(ry * x1p) / rx);

    final cx = cosPhi * cxp - sinPhi * cyp + (start.dx + end.dx) / 2.0;
    final cy = sinPhi * cxp + cosPhi * cyp + (start.dy + end.dy) / 2.0;

    double angleBetween(double ux, double uy, double vx, double vy) {
      final dot = ux * vx + uy * vy;
      final mag = math.sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy));
      if (mag == 0) return 0;
      final signValue = ux * vy - uy * vx < 0 ? -1.0 : 1.0;
      final value = (dot / mag).clamp(-1.0, 1.0);
      return signValue * math.acos(value);
    }

    final theta1 = angleBetween(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry);
    var deltaTheta = angleBetween(
      (x1p - cxp) / rx,
      (y1p - cyp) / ry,
      (-x1p - cxp) / rx,
      (-y1p - cyp) / ry,
    );
    if (!sweep && deltaTheta > 0) deltaTheta -= 2 * math.pi;
    if (sweep && deltaTheta < 0) deltaTheta += 2 * math.pi;

    return _ArcGeometry(
      center: Offset(cx, cy),
      rx: rx,
      ry: ry,
      phi: phi,
      theta1: theta1,
      deltaTheta: deltaTheta,
    );
  }

  Offset _pointOnArc(_ArcGeometry arc, double t) {
    final theta = arc.theta1 + arc.deltaTheta * t;
    final cosPhi = math.cos(arc.phi);
    final sinPhi = math.sin(arc.phi);
    final x = arc.center.dx +
        arc.rx * math.cos(theta) * cosPhi -
        arc.ry * math.sin(theta) * sinPhi;
    final y = arc.center.dy +
        arc.rx * math.cos(theta) * sinPhi +
        arc.ry * math.sin(theta) * cosPhi;
    return Offset(x, y);
  }

  List<Offset> _buildSafeDotPoints(
    List<Offset> contour, {
    List<Offset> preferredPoints = const <Offset>[],
  }) {
    if (contour.length < 4) return contour;

    final closed = List<Offset>.from(contour);
    if ((closed.first - closed.last).distance > .001) {
      closed.add(closed.first);
    }

    List<Offset> reorderFromTop(List<Offset> points) {
      if (points.isEmpty) return points;
      var startIndex = 0;
      for (var index = 1; index < points.length; index++) {
        if (points[index].dy < points[startIndex].dy ||
            (points[index].dy == points[startIndex].dy &&
                points[index].dx < points[startIndex].dx)) {
          startIndex = index;
        }
      }
      if (startIndex == 0) return points;
      return <Offset>[
        ...points.sublist(startIndex),
        ...points.sublist(0, startIndex),
      ];
    }

    List<Offset> filterClosePoints(List<Offset> points, {double minDistance = .085}) {
      final filtered = <Offset>[];
      for (final point in points) {
        if (filtered.isEmpty || (point - filtered.last).distance >= minDistance) {
          filtered.add(point);
        }
      }
      if (filtered.length >= 2 && (filtered.first - filtered.last).distance < minDistance) {
        filtered.removeLast();
      }
      return filtered;
    }

    bool overlaps(List<Offset> points, {double minDistance = .115}) {
      for (var i = 0; i < points.length; i++) {
        for (var j = i + 1; j < points.length; j++) {
          if ((points[i] - points[j]).distance < minDistance) return true;
        }
      }
      return false;
    }

    if (preferredPoints.isNotEmpty) {
      final preferred = reorderFromTop(filterClosePoints(preferredPoints));
      if (preferred.length >= 6 && preferred.length <= 18 && !overlaps(preferred, minDistance: .09)) {
        return preferred;
      }
    }

    final cumulative = <double>[0];
    var totalLength = 0.0;
    for (var i = 1; i < closed.length; i++) {
      totalLength += (closed[i] - closed[i - 1]).distance;
      cumulative.add(totalLength);
    }
    if (totalLength <= 0) return <Offset>[];

    var targetCount = (totalLength / .125).round().clamp(9, 18).toInt();

    List<Offset> sample(int count) {
      final result = <Offset>[];
      for (var n = 0; n < count; n++) {
        final target = totalLength * n / count;
        var segment = 1;
        while (segment < cumulative.length && cumulative[segment] < target) {
          segment++;
        }
        segment = segment.clamp(1, closed.length - 1).toInt();
        final fromLength = cumulative[segment - 1];
        final toLength = cumulative[segment];
        final span = math.max(.000001, toLength - fromLength);
        final t = ((target - fromLength) / span).clamp(0.0, 1.0).toDouble();
        result.add(Offset.lerp(closed[segment - 1], closed[segment], t)!);
      }
      return reorderFromTop(result);
    }

    // Если SVG содержит явные опорные точки сегментов (особенно A/a),
    // не теряем их при последующей равномерной выборке. Для дуги parser
    // добавляет start + midpoint + end. Если этих точек мало для игры,
    // дополняем их обычными точками контура, сохраняя порядок вдоль path.
    if (preferredPoints.length > 1) {
      final preferred = filterClosePoints(preferredPoints, minDistance: .05);

      int nearestContourIndex(Offset point) {
        var bestIndex = 0;
        var bestDistance = double.infinity;
        for (var index = 0; index < closed.length - 1; index++) {
          final distance = (closed[index] - point).distanceSquared;
          if (distance < bestDistance) {
            bestDistance = distance;
            bestIndex = index;
          }
        }
        return bestIndex;
      }

      final target = math.max(8, math.min(18, targetCount));
      final byContourIndex = <int, Offset>{};

      // Сначала обычные точки, затем обязательные guide points поверх них.
      for (final point in sample(target)) {
        byContourIndex.putIfAbsent(nearestContourIndex(point), () => point);
      }
      for (final point in preferred) {
        byContourIndex[nearestContourIndex(point)] = point;
      }

      final orderedEntries = byContourIndex.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      final merged = reorderFromTop(
        orderedEntries.map((entry) => entry.value).toList(growable: false),
      );

      if (merged.length >= 6 && !overlaps(merged, minDistance: .05)) {
        return merged;
      }
    }

    while (targetCount >= 8) {
      final points = sample(targetCount);
      if (!overlaps(points)) return points;
      targetCount--;
    }

    return sample(8);
  }

  Color? _parseColor(String? value) {
    if (value == null) return null;
    final clean = value.replaceFirst('#', '');
    if (clean.length != 6) return null;
    final rgb = int.tryParse(clean, radix: 16);
    if (rgb == null) return null;
    return Color(0xFF000000 | rgb);
  }

  void _restartPicture() {
    setState(() {
      _sessionToken += 1;
      _connectedCount = 0;
      _wrongPoint = null;
      _completed = false;
    });
  }

  Future<void> _onPointTap(int index) async {
    if (_completed) return;

    if (index != _connectedCount) {
      final token = ++_sessionToken;
      setState(() => _wrongPoint = index);
      await Future<void>.delayed(const Duration(milliseconds: 420));
      if (!mounted || token != _sessionToken) return;
      setState(() => _wrongPoint = null);
      return;
    }

    final isLast = index == _picture.points.length - 1;
    if (isLast) {
      await precacheImage(AssetImage(_picture.imageAsset), context);
      if (!mounted) return;
    }

    setState(() {
      _wrongPoint = null;
      _connectedCount += 1;
      if (_connectedCount == _picture.points.length) _completed = true;
    });
  }

  void _nextPicture() {
    if (_pictureIndex == _pictures.length - 1) {
      _showFinishedDialog();
      return;
    }
    setState(() {
      _pictureIndex += 1;
      _connectedCount = 0;
      _wrongPoint = null;
      _completed = false;
      _sessionToken += 1;
    });
  }

  Future<void> _showFinishedDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/ui/celebration.webp', width: 76, height: 76),
            const SizedBox(height: 6),
            const Text(
              'Все картинки готовы!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF124C89),
                fontSize: 23,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ты отлично соединил все точки по порядку.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF5C6F88),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  setState(() {
                    _pictureIndex = 0;
                    _connectedCount = 0;
                    _wrongPoint = null;
                    _completed = false;
                    _sessionToken += 1;
                  });
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4E7DDE),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                child: const Text(
                  'Сыграть ещё',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  Navigator.of(context).pop();
                },
                child: const Text(
                  'В пещеру',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(body: ZenviaLoadingScreen());
    }

    if (_loadError != null || _pictures.isEmpty) {
      return Scaffold(
        body: FantasyBackground(
          light: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _loadError ?? 'Нет уровней.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      setState(() {
                        _loading = true;
                        _loadError = null;
                      });
                      _loadPictures();
                    },
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final nextNumber = math.min(_connectedCount + 1, _picture.points.length);

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Image(
            image: AssetImage('assets/images/adventure_bg.webp'),
            fit: BoxFit.cover,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF163774).withValues(alpha: .35),
                  const Color(0xFF305997).withValues(alpha: .18),
                  const Color(0xFF10294F).withValues(alpha: .40),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      _CircleButton(
                        tooltip: 'Назад',
                        icon: Icons.arrow_back_rounded,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Соедини точки',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            shadows: [
                              Shadow(
                                color: Color(0x8A000000),
                                offset: Offset(0, 2),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      ),
                      _CircleButton(
                        tooltip: 'Начать заново',
                        icon: Icons.refresh_rounded,
                        onPressed: _restartPicture,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _TopStatusCard(
                    title: 'Картинка ${_pictureIndex + 1}/${_pictures.length}',
                    value: _picture.name,
                    progressLabel: 'Найди точку $nextNumber',
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: _DrawingBoard(
                      picture: _picture,
                      connectedCount: _connectedCount,
                      wrongPoint: _wrongPoint,
                      completed: _completed,
                      onPointTap: _onPointTap,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _completed ? _nextPicture : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF5ACB5A),
                        disabledBackgroundColor: Colors.white.withValues(alpha: .35),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22),
                        ),
                      ),
                      child: Text(
                        _pictureIndex == _pictures.length - 1 ? 'Завершить' : 'Дальше',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopStatusCard extends StatelessWidget {
  const _TopStatusCard({
    required this.title,
    required this.value,
    required this.progressLabel,
  });

  final String title;
  final String value;
  final String progressLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 16,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF355686),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Color(0xFFF7B733),
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              progressLabel,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF124C89),
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawingBoard extends StatelessWidget {
  const _DrawingBoard({
    required this.picture,
    required this.connectedCount,
    required this.wrongPoint,
    required this.completed,
    required this.onPointTap,
  });

  final _DotPicture picture;
  final int connectedCount;
  final int? wrongPoint;
  final bool completed;
  final Future<void> Function(int index) onPointTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boardWidth = constraints.maxWidth;
        final boardHeight = constraints.maxHeight;
        final imageRect = _fittedImageRect(
          Size(boardWidth, boardHeight),
          picture.sourceAspectRatio,
        );

        Offset mapPoint(Offset uv) => Offset(
              imageRect.left + uv.dx * imageRect.width,
              imageRect.top + uv.dy * imageRect.height,
            );

        final canvas = Stack(
          fit: StackFit.expand,
          children: [
              if (completed)
                Positioned.fromRect(
                  rect: imageRect,
                  child: Image.asset(
                    picture.imageAsset,
                    fit: BoxFit.contain,
                  ),
                )
              else ...[
                for (var index = 0; index < connectedCount - 1; index++)
                  CustomPaint(
                    painter: _SegmentPainter(
                      from: mapPoint(picture.points[index]),
                      to: mapPoint(picture.points[index + 1]),
                      color: picture.color,
                    ),
                    size: Size(boardWidth, boardHeight),
                  ),
                for (var index = 0; index < picture.points.length; index++)
                  _buildDot(index, imageRect),
              ],
            ],
          );

        return Container(
          width: boardWidth,
          height: boardHeight,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .84),
            borderRadius: BorderRadius.circular(30),
          ),
          clipBehavior: Clip.antiAlias,
          child: canvas,
        );
      },
    );
  }

  Rect _fittedImageRect(Size boardSize, double sourceAspectRatio) {
    const padding = 28.0;
    final availableWidth = math.max(1.0, boardSize.width - padding * 2);
    final availableHeight = math.max(1.0, boardSize.height - padding * 2);
    final availableAspect = availableWidth / availableHeight;

    double width;
    double height;
    if (sourceAspectRatio >= availableAspect) {
      width = availableWidth;
      height = width / math.max(.000001, sourceAspectRatio);
    } else {
      height = availableHeight;
      width = height * sourceAspectRatio;
    }

    return Rect.fromLTWH(
      (boardSize.width - width) / 2,
      (boardSize.height - height) / 2,
      width,
      height,
    );
  }

  Widget _buildDot(int index, Rect imageRect) {
    final point = picture.points[index];
    final left = imageRect.left + point.dx * imageRect.width;
    final top = imageRect.top + point.dy * imageRect.height;
    final solved = index < connectedCount;
    final current = index == connectedCount;
    final wrong = wrongPoint == index;

    return Positioned(
      left: left - 22,
      top: top - 22,
      child: GestureDetector(
        onTap: completed ? null : () => onPointTap(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: solved
                ? picture.color
                : wrong
                    ? const Color(0xFFFF7878)
                    : current
                        ? Colors.white
                        : const Color(0xFFF8FBFF),
            shape: BoxShape.circle,
            border: Border.all(
              color: current
                  ? picture.color
                  : solved
                      ? Colors.white
                      : const Color(0xFF98B2D8),
              width: 3,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            '${index + 1}',
            style: TextStyle(
              color: solved ? Colors.white : const Color(0xFF355686),
              fontSize: index + 1 >= 10 ? 15 : 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _SegmentPainter extends CustomPainter {
  _SegmentPainter({
    required this.from,
    required this.to,
    required this.color,
  });

  final Offset from;
  final Offset to;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7;
    canvas.drawLine(from, to, paint);
  }

  @override
  bool shouldRepaint(covariant _SegmentPainter oldDelegate) =>
      oldDelegate.from != from || oldDelegate.to != to || oldDelegate.color != color;
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: .22),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(icon, color: Colors.white, size: 28),
          ),
        ),
      ),
    );
  }
}

class _DotPicture {
  const _DotPicture({
    required this.name,
    required this.color,
    required this.points,
    required this.imageAsset,
    required this.sourceAspectRatio,
  });

  final String name;
  final Color color;

  /// Координаты точек 0..1 относительно viewBox SVG и парного изображения.
  final List<Offset> points;
  final String imageAsset;
  final double sourceAspectRatio;
}

class _SvgPathGeometry {
  const _SvgPathGeometry({
    required this.raw,
    required this.guidePoints,
    required this.totalLength,
  });

  const _SvgPathGeometry.empty()
      : raw = const <Offset>[],
        guidePoints = const <Offset>[],
        totalLength = 0;

  final List<Offset> raw;
  final List<Offset> guidePoints;
  final double totalLength;
}

class _ArcGeometry {
  const _ArcGeometry({
    required this.center,
    required this.rx,
    required this.ry,
    required this.phi,
    required this.theta1,
    required this.deltaTheta,
  });

  final Offset center;
  final double rx;
  final double ry;
  final double phi;
  final double theta1;
  final double deltaTheta;
}
