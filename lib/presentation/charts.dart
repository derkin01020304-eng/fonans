import 'dart:math';
import 'package:flutter/material.dart';
import '../core/money.dart';
import '../domain/analytics.dart';
import 'widgets.dart';

class ExpenseDonut extends StatefulWidget {
  const ExpenseDonut({
    super.key,
    required this.categories,
    required this.currency,
  });
  final Map<String, int> categories;
  final String currency;
  @override
  State<ExpenseDonut> createState() => _ExpenseDonutState();
}

class _ExpenseDonutState extends State<ExpenseDonut> {
  int? selected;
  @override
  Widget build(BuildContext context) {
    final entries = widget.categories.entries.toList();
    final total = entries.fold<int>(0, (s, e) => s + e.value);
    if (total == 0)
      return const EmptyPanel(
        'Расходов пока нет',
        'Добавьте расход — здесь появится распределение по категориям.',
      );
    final index = selected != null && selected! < entries.length
        ? selected
        : null;
    return Panel(
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: GestureDetector(
              onTapUp: (details) {
                final delta = details.localPosition - const Offset(100, 100);
                var angle = atan2(delta.dy, delta.dx) + pi / 2;
                if (angle < 0) angle += 2 * pi;
                var end = 0.0;
                for (var i = 0; i < entries.length; i++) {
                  end += entries[i].value / total * 2 * pi;
                  if (angle < end) {
                    setState(() => selected = i);
                    break;
                  }
                }
              },
              child: SizedBox(
                width: 200,
                height: 200,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(200, 200),
                      painter: _DonutPainter(
                        entries.map((e) => e.value).toList(),
                        index,
                      ),
                    ),
                    IgnorePointer(
                      child: Padding(
                        padding: const EdgeInsets.all(40),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              index == null ? 'Расходы' : entries[index].key,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 6),
                            FittedBox(
                              child: Text(
                                money(
                                  index == null ? total : entries[index].value,
                                  widget.currency,
                                ),
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < entries.length; i++)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              onTap: () => setState(() => selected = selected == i ? null : i),
              leading: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: chartColors[i % chartColors.length],
                  shape: BoxShape.circle,
                ),
              ),
              title: Text(entries[i].key),
              trailing: Text(
                '${money(entries[i].value, widget.currency)} · ${(entries[i].value / total * 100).toStringAsFixed(0)}%',
              ),
            ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.values, this.selected);
  final List<int> values;
  final int? selected;
  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<int>(0, (s, v) => s + v);
    if (total == 0) return;
    var start = -pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * 2 * pi;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected == i ? 28 : 22
        ..color = chartColors[i % chartColors.length];
      canvas.drawArc(
        Rect.fromCircle(
          center: Offset(size.width / 2, size.height / 2),
          radius: 80,
        ),
        start + .015,
        max(0, sweep - .03),
        false,
        paint,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => true;
}

class FinanceLineChart extends StatefulWidget {
  const FinanceLineChart({
    super.key,
    required this.points,
    required this.metric,
    required this.currency,
  });
  final List<ChartPoint> points;
  final String metric, currency;
  @override
  State<FinanceLineChart> createState() => _FinanceLineChartState();
}

class _FinanceLineChartState extends State<FinanceLineChart> {
  int? selected;
  int value(ChartPoint p) => switch (widget.metric) {
    'income' => p.income,
    'expense' => p.expense,
    'savings' => p.savings,
    'debt' => p.debt,
    _ => p.balance,
  };
  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    if (points.isEmpty)
      return const EmptyPanel('Нет данных', 'Выберите период с операциями.');
    final index = (selected ?? points.length - 1).clamp(0, points.length - 1);
    final values = points.map(value).toList();
    final minV = values.reduce(min), maxV = values.reduce(max);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            money(values[index], widget.currency),
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            dateLabel(points[index].date),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                money(maxV, widget.currency),
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) => Semantics(
              label:
                  'График. Минимум ${money(minV, widget.currency)}, максимум ${money(maxV, widget.currency)}.',
              child: GestureDetector(
                onTapDown: (d) => setState(
                  () => selected =
                      (d.localPosition.dx /
                              constraints.maxWidth *
                              (points.length - 1))
                          .round()
                          .clamp(0, points.length - 1),
                ),
                onHorizontalDragUpdate: (d) => setState(
                  () => selected =
                      (d.localPosition.dx /
                              constraints.maxWidth *
                              (points.length - 1))
                          .round()
                          .clamp(0, points.length - 1),
                ),
                child: CustomPaint(
                  size: Size(constraints.maxWidth, 150),
                  painter: _LinePainter(
                    values,
                    index,
                    widget.metric == 'expense'
                        ? coral
                        : const Color(0xFF319D7F),
                    Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            money(minV, widget.currency),
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                dateLabel(points.first.date),
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const Spacer(),
              Text(
                dateLabel(points.last.date),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Коснитесь графика, чтобы посмотреть значение.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.values, this.selected, this.color, this.grid);
  final List<int> values;
  final int selected;
  final Color color, grid;
  @override
  void paint(Canvas canvas, Size size) {
    final low = values.reduce(min).toDouble(),
        high = values.reduce(max).toDouble();
    final range = max(100.0, high - low);
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = .6;
    for (var i = 0; i < 4; i++) {
      final y = 8 + (size.height - 16) * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    Offset point(int i) => Offset(
      values.length == 1
          ? size.width / 2
          : 4 + (size.width - 8) * i / (values.length - 1),
      size.height - 8 - (values[i] - low) / range * (size.height - 16),
    );
    final path = Path()..moveTo(point(0).dx, point(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(point(i).dx, point(i).dy);
    }
    final fill = Path.from(path)
      ..lineTo(point(values.length - 1).dx, size.height)
      ..lineTo(point(0).dx, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: .22), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2.8
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
    final p = point(selected);
    canvas.drawLine(
      Offset(p.dx, 0),
      Offset(p.dx, size.height),
      Paint()..color = grid,
    );
    canvas.drawCircle(p, 5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => true;
}
