import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class ClockFacePainter extends CustomPainter {
  final List<Activity> activities;
  final DateTime currentTime;
  final int? selectedActivityIndex;

  ClockFacePainter({
    required this.activities,
    required this.currentTime,
    this.selectedActivityIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = min(size.width, size.height) / 2;
    final ringWidth = outerRadius * 0.18;
    final innerRadius = outerRadius - ringWidth;
    final activityRadius = innerRadius + ringWidth / 2;

    final backgroundPaint = Paint()
      ..shader = RadialGradient(
        colors: [const Color(0xFF17324D), const Color(0xFF0C1724)],
      ).createShader(Rect.fromCircle(center: center, radius: outerRadius));
    canvas.drawCircle(center, outerRadius, backgroundPaint);

    final framePaint = Paint()
      ..color = Colors.white.withAlpha(28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = outerRadius * 0.035;
    canvas.drawCircle(
      center,
      outerRadius - framePaint.strokeWidth / 2,
      framePaint,
    );

    final activityTrackPaint = Paint()
      ..color = Colors.white.withAlpha(18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth;
    canvas.drawCircle(center, activityRadius, activityTrackPaint);

    // Pierścień segmentów aktywności rozłożonych na pełne 24h.
    for (var i = 0; i < activities.length; i++) {
      final activity = activities[i];
      final isSelected = i == selectedActivityIndex;
      final startAngle =
          -pi / 2 + (activity.startMinutes / Activity.minutesPerDay) * 2 * pi;
      final sweepAngle = (activity.durationHours / 24) * 2 * pi;
      final segmentPaint = Paint()
        ..color = activity.color.withAlpha(
          isSelected ? 255 : (0.95 * 255).round(),
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? ringWidth + 6 : ringWidth;

      if (isSelected) {
        segmentPaint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      }

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: activityRadius),
        startAngle,
        sweepAngle,
        false,
        segmentPaint,
      );
    }

    // Środek tarczy.
    final innerPaint = Paint()
      ..shader = RadialGradient(
        colors: [const Color(0xFF1E425F), const Color(0xFF0C1724)],
      ).createShader(Rect.fromCircle(center: center, radius: innerRadius - 4));

    canvas.drawCircle(center, innerRadius - 4, innerPaint);

    final innerRingPaint = Paint()
      ..color = Colors.white.withAlpha(18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = outerRadius * 0.01;
    canvas.drawCircle(center, innerRadius * 0.77, innerRingPaint);

    // Podziałka 24h.
    final tickPaint = Paint()
      ..color = Colors.white.withAlpha((0.9 * 255).round())
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 24; i++) {
      final angle = (i * 15 - 90) * pi / 180;
      final isMainHour = i.isEven;
      final tickStartRadius = isMainHour ? innerRadius - 18 : innerRadius - 12;
      final tickEndRadius = outerRadius - 12;
      final tickStart = Offset(
        center.dx + tickStartRadius * cos(angle),
        center.dy + tickStartRadius * sin(angle),
      );
      final tickEnd = Offset(
        center.dx + tickEndRadius * cos(angle),
        center.dy + tickEndRadius * sin(angle),
      );
      tickPaint.strokeWidth = isMainHour ? 3 : 1.5;
      canvas.drawLine(tickStart, tickEnd, tickPaint);

      final label = i.toString().padLeft(2, '0');
      final labelPos = Offset(
        center.dx + (outerRadius - 34) * cos(angle),
        center.dy + (outerRadius - 34) * sin(angle),
      );

      final labelPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontSize: i.isEven ? outerRadius * 0.08 : outerRadius * 0.055,
            fontWeight: i.isEven ? FontWeight.w700 : FontWeight.w500,
            color: Colors.white.withAlpha(i.isEven ? 255 : 170),
          ),
        ),
        textDirection: TextDirection.ltr,
      );

      labelPainter.layout();
      labelPainter.paint(
        canvas,
        labelPos - Offset(labelPainter.width / 2, labelPainter.height / 2),
      );
    }

    final centerTextPainter = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: _formatTime(currentTime),
            style: TextStyle(
              fontSize: outerRadius * 0.18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          TextSpan(
            text: '\n24h Clock',
            style: TextStyle(
              fontSize: outerRadius * 0.07,
              fontWeight: FontWeight.w500,
              color: Colors.white.withAlpha(170),
              height: 1.6,
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    centerTextPainter.layout(maxWidth: innerRadius * 1.4);
    centerTextPainter.paint(
      canvas,
      Offset(
        center.dx - centerTextPainter.width / 2,
        center.dy - centerTextPainter.height / 2,
      ),
    );

    final dayProgress =
        (currentTime.hour +
            currentTime.minute / 60 +
            currentTime.second / 3600 +
            currentTime.millisecond / 3600000) /
        24;
    final handAngle = dayProgress * 2 * pi - pi / 2;
    final handTip = Offset(
      center.dx + innerRadius * 0.88 * cos(handAngle),
      center.dy + innerRadius * 0.88 * sin(handAngle),
    );
    final handBase = Offset(
      center.dx - innerRadius * 0.12 * cos(handAngle),
      center.dy - innerRadius * 0.12 * sin(handAngle),
    );

    final handPaint = Paint()
      ..shader = LinearGradient(
        colors: [const Color(0xFFFFD166), const Color(0xFFFF8C42)],
      ).createShader(Rect.fromPoints(handBase, handTip))
      ..strokeWidth = outerRadius * 0.03
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(handBase, handTip, handPaint);

    final glowPaint = Paint()
      ..color = const Color(0xFFFFD166).withAlpha(80)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(handTip, outerRadius * 0.04, glowPaint);

    final handDotPaint = Paint()..color = const Color(0xFFFFD166);
    canvas.drawCircle(handTip, outerRadius * 0.03, handDotPaint);

    final centerDot = Paint()..color = Colors.white;
    canvas.drawCircle(center, outerRadius * 0.035, centerDot);

    final centerDotInner = Paint()..color = const Color(0xFF0C1724);
    canvas.drawCircle(center, outerRadius * 0.018, centerDotInner);
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    final second = time.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  @override
  bool shouldRepaint(covariant ClockFacePainter oldDelegate) {
    return oldDelegate.activities != activities ||
        oldDelegate.currentTime != currentTime ||
        oldDelegate.selectedActivityIndex != selectedActivityIndex;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.initialize();
  runApp(const BrainClockApp());
}

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    tz_data.initializeTimeZones();
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const darwinSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _plugin.initialize(settings);
    await requestPermissions();
  }

  Future<void> requestPermissions() async {
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestExactAlarmsPermission();

    final iosPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    await iosPlugin?.requestPermissions(alert: true, badge: true, sound: true);

    final macOsPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >();
    await macOsPlugin?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<void> showActivityReminder(Activity activity) async {
    const androidDetails = AndroidNotificationDetails(
      'activity_reminders',
      'Activity reminders',
      channelDescription: 'Notifications about activity start times',
      importance: Importance.max,
      priority: Priority.high,
    );
    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
    );

    await _plugin.show(
      activity.hashCode,
      'Time for an activity',
      '${activity.name} • ${activity.timeRangeLabel}',
      notificationDetails,
    );
  }

  Future<void> scheduleActivityReminders(List<Activity> activities) async {
    await _plugin.cancelAll();

    const androidDetails = AndroidNotificationDetails(
      'activity_reminders',
      'Activity reminders',
      channelDescription: 'Notifications about activity start times',
      importance: Importance.max,
      priority: Priority.high,
    );
    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
    );

    final now = DateTime.now();
    const daysAhead = 14;

    for (var dayOffset = 0; dayOffset < daysAhead; dayOffset++) {
      final day = DateTime(
        now.year,
        now.month,
        now.day,
      ).add(Duration(days: dayOffset));

      for (var index = 0; index < activities.length; index++) {
        final activity = activities[index];
        final scheduledLocalTime = day.add(
          Duration(minutes: activity.startMinutes),
        );

        if (!scheduledLocalTime.isAfter(now)) {
          continue;
        }

        final scheduledUtc = tz.TZDateTime.from(
          scheduledLocalTime.toUtc(),
          tz.UTC,
        );

        await _plugin.zonedSchedule(
          10000 + dayOffset * 1000 + index,
          'Time for an activity',
          '${activity.name} • ${activity.timeRangeLabel}',
          scheduledUtc,
          notificationDetails,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    }
  }
}

class BrainClockApp extends StatelessWidget {
  const BrainClockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'BrainClock',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      routerConfig: _router,
    );
  }
}

final GoRouter _router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
    GoRoute(
      path: '/add',
      builder: (context, state) => AddActivityScreen(
        existingActivities:
            (state.extra as List<Activity>?) ?? const <Activity>[],
      ),
    ),
  ],
);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const String _activitiesStorageKey = 'activities';
  static const String _templatesStorageKey = 'day_plan_templates';
  late Timer _clockTimer;
  DateTime _now = DateTime.now();
  int? selectedActivityIndex;
  final Set<String> _confirmedReminderKeys = <String>{};
  bool _isReminderDialogVisible = false;
  bool _activitiesLoaded = false;

  List<Activity> activities = _defaultActivities();
  List<DayPlanTemplate> templates = <DayPlanTemplate>[];

  @override
  void initState() {
    super.initState();
    _loadActivities();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _now = DateTime.now();
      });
      _checkCurrentActivityReminder();
    });
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pageGradient = _backgroundGradientForTime(_now);
    final onSurfaceColor = _foregroundColorForTime(_now);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('BrainClock 24h'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: onSurfaceColor,
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(gradient: pageGradient),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.max,
                children: [
                  Expanded(
                    flex: 7,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final size = Size(
                            constraints.maxWidth,
                            constraints.maxWidth,
                          );
                          return AspectRatio(
                            aspectRatio: 1,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanStart: (details) => _moveSelectedActivity(
                                details.localPosition,
                                size,
                              ),
                              onPanUpdate: (details) => _moveSelectedActivity(
                                details.localPosition,
                                size,
                              ),
                              child: CustomPaint(
                                painter: ClockFacePainter(
                                  activities: activities,
                                  currentTime: _now,
                                  selectedActivityIndex: selectedActivityIndex,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      itemCount: activities.length,
                      itemBuilder: (context, index) {
                        final activity = activities[index];
                        final isSelected = index == selectedActivityIndex;
                        return Card(
                          elevation: 0,
                          color: isSelected
                              ? activity.color.withAlpha(90)
                              : Colors.white.withAlpha(210),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            onTap: () => _toggleActivitySelection(index),
                            leading: CircleAvatar(
                              backgroundColor: activity.color,
                              radius: 10,
                            ),
                            title: Text(activity.name),
                            subtitle: Text(
                              '${activity.timeRangeLabel} • ${activity.durationHours.toStringAsFixed(1)} hours',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isSelected)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 4),
                                    child: Icon(Icons.pan_tool_alt, size: 18),
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () => _editActivity(index),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete),
                                  onPressed: () => _deleteActivity(index),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _showPlanActionsSheet,
                        child: const Text('Add activity'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _deleteAllActivities,
                    borderRadius: BorderRadius.circular(20),
                    child: Ink(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.red.withAlpha(210),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(45),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.delete_sweep_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _editActivity(int index) async {
    final editedActivity = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => EditActivityScreen(activity: activities[index]),
      ),
    );
    if (editedActivity != null) {
      setState(() {
        activities[index] = editedActivity as Activity;
        selectedActivityIndex = index;
      });
      _saveActivities();
    }
  }

  void _deleteActivity(int index) {
    setState(() {
      activities.removeAt(index);
      if (selectedActivityIndex == index) {
        selectedActivityIndex = null;
      } else if (selectedActivityIndex != null &&
          selectedActivityIndex! > index) {
        selectedActivityIndex = selectedActivityIndex! - 1;
      }
    });
    _saveActivities();
  }

  Future<void> _deleteAllActivities() async {
    if (activities.isEmpty) {
      return;
    }

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete all activities?'),
          content: const Text('This will clear the entire current day plan.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete all'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true || !mounted) {
      return;
    }

    setState(() {
      activities.clear();
      selectedActivityIndex = null;
    });
    await _saveActivities();
  }

  void _toggleActivitySelection(int index) {
    setState(() {
      selectedActivityIndex = selectedActivityIndex == index ? null : index;
    });
  }

  void _moveSelectedActivity(Offset localPosition, Size size) {
    final index = selectedActivityIndex;
    if (index == null || !_isOnActivityRing(localPosition, size)) {
      return;
    }

    final activity = activities[index];
    final durationMinutes = activity.durationMinutes;
    final desiredStartMinutes = _minutesFromOffset(localPosition, size);
    final newStartMinutes = _resolveStartWithoutOverlap(
      movingIndex: index,
      desiredStartMinutes: desiredStartMinutes,
      durationMinutes: durationMinutes,
    );
    setState(() {
      activity.startMinutes = newStartMinutes;
      activity.endMinutes =
          (newStartMinutes + durationMinutes) % Activity.minutesPerDay;
    });
    _saveActivities();
  }

  static List<Activity> _defaultActivities() {
    return [
      Activity('Rest', 0, 480, Colors.blue, Category.rest),
      Activity('Mental Work', 480, 960, Colors.green, Category.work),
      Activity('Food', 960, 1080, Colors.orange, Category.meal),
      Activity('Relax', 1080, 1320, Colors.purple, Category.relax),
      Activity('Physical Work', 1320, 0, Colors.green, Category.work),
    ];
  }

  Future<void> _loadActivities() async {
    final preferences = await SharedPreferences.getInstance();
    templates = _loadTemplatesFromPreferences(preferences);
    final jsonString = preferences.getString(_activitiesStorageKey);
    if (jsonString == null) {
      if (!mounted) {
        return;
      }

      setState(() {
        _activitiesLoaded = true;
        templates = _loadTemplatesFromPreferences(preferences);
      });
      await NotificationService.instance.scheduleActivityReminders(activities);
      return;
    }

    try {
      final decoded = jsonDecode(jsonString) as List<dynamic>;
      final loadedActivities = decoded
          .map((item) => Activity.fromJson(item as Map<String, dynamic>))
          .toList();

      if (!mounted) {
        return;
      }

      setState(() {
        activities = loadedActivities;
        _activitiesLoaded = true;
        templates = _loadTemplatesFromPreferences(preferences);
      });
      await NotificationService.instance.scheduleActivityReminders(activities);
      _checkCurrentActivityReminder();
    } catch (_) {
      await preferences.remove(_activitiesStorageKey);
      if (!mounted) {
        return;
      }

      setState(() {
        _activitiesLoaded = true;
        templates = _loadTemplatesFromPreferences(preferences);
      });
      await NotificationService.instance.scheduleActivityReminders(activities);
    }
  }

  Future<void> _saveActivities() async {
    final preferences = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(
      activities.map((activity) => activity.toJson()).toList(),
    );
    await preferences.setString(_activitiesStorageKey, jsonString);
    await NotificationService.instance.scheduleActivityReminders(activities);
  }

  List<DayPlanTemplate> _loadTemplatesFromPreferences(
    SharedPreferences preferences,
  ) {
    final jsonString = preferences.getString(_templatesStorageKey);
    if (jsonString == null) {
      return <DayPlanTemplate>[];
    }

    try {
      final decoded = jsonDecode(jsonString) as List<dynamic>;
      return decoded
          .map((item) => DayPlanTemplate.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return <DayPlanTemplate>[];
    }
  }

  Future<void> _saveTemplates() async {
    final preferences = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(
      templates.map((template) => template.toJson()).toList(),
    );
    await preferences.setString(_templatesStorageKey, jsonString);
  }

  Future<void> _showPlanActionsSheet() async {
    if (!mounted) {
      return;
    }

    final selectedAction = await showModalBottomSheet<_PlanSheetAction>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Day plan',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.add_circle_outline),
                  title: const Text('Add activity'),
                  subtitle: const Text(
                    'Add a new activity to the current plan',
                  ),
                  onTap: () {
                    Navigator.of(
                      sheetContext,
                    ).pop(const _PlanSheetAction.addActivity());
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.bookmark_add_outlined),
                  title: const Text('Save as template'),
                  subtitle: const Text('Keep the current day plan for later'),
                  onTap: () {
                    Navigator.of(
                      sheetContext,
                    ).pop(const _PlanSheetAction.saveTemplate());
                  },
                ),
                const SizedBox(height: 8),
                const Text(
                  'Saved templates',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                if (templates.isEmpty)
                  Text(
                    'You do not have any saved templates yet.',
                    style: TextStyle(color: Colors.grey.shade700),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: templates.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final template = templates[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.calendar_view_day_outlined),
                          title: Text(template.name),
                          subtitle: Text(
                            '${template.activities.length} activities',
                          ),
                          onTap: () {
                            Navigator.of(
                              sheetContext,
                            ).pop(_PlanSheetAction.applyTemplate(template));
                          },
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Delete template',
                            onPressed: () async {
                              final sheetNavigator = Navigator.of(sheetContext);
                              await _deleteTemplate(template);
                              if (mounted) {
                                sheetNavigator.pop();
                                await _showPlanActionsSheet();
                              }
                            },
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || selectedAction == null) {
      return;
    }

    switch (selectedAction.type) {
      case _PlanSheetActionType.addActivity:
        await _openAddActivityFlow();
        break;
      case _PlanSheetActionType.saveTemplate:
        await _saveCurrentPlanAsTemplate();
        break;
      case _PlanSheetActionType.applyTemplate:
        final template = selectedAction.template;
        if (template != null) {
          await _applyTemplate(template);
        }
        break;
    }
  }

  Future<void> _openAddActivityFlow() async {
    final newActivity = await context.push(
      '/add',
      extra: activities.map((activity) => activity.copy()).toList(),
    );
    if (newActivity != null) {
      setState(() {
        if (newActivity is List<Activity>) {
          activities.addAll(newActivity);
        } else {
          activities.add(newActivity as Activity);
        }
      });
      await _saveActivities();
    }
  }

  Future<void> _saveCurrentPlanAsTemplate() async {
    final templateName = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (context) => const SaveTemplateScreen()),
    );

    if (templateName == null || templateName.isEmpty) {
      return;
    }

    final template = DayPlanTemplate(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: templateName,
      activities: activities.map((activity) => activity.copy()).toList(),
    );

    setState(() {
      templates.removeWhere(
        (existing) => existing.name.toLowerCase() == templateName.toLowerCase(),
      );
      templates.insert(0, template);
    });
    await _saveTemplates();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Template "$templateName" saved.')));
  }

  Future<void> _applyTemplate(DayPlanTemplate template) async {
    final shouldApply = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Load template?'),
          content: Text(
            'Template "${template.name}" will replace the current day plan.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Load'),
            ),
          ],
        );
      },
    );

    if (shouldApply != true) {
      return;
    }

    setState(() {
      activities = template.activities
          .map((activity) => activity.copy())
          .toList();
      selectedActivityIndex = null;
    });
    await _saveActivities();
  }

  Future<void> _deleteTemplate(DayPlanTemplate template) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete template?'),
          content: Text('Template "${template.name}" will be deleted.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) {
      return;
    }

    setState(() {
      templates.removeWhere((item) => item.id == template.id);
    });
    await _saveTemplates();
  }

  void _checkCurrentActivityReminder() {
    if (!mounted || !_activitiesLoaded || _isReminderDialogVisible) {
      return;
    }

    final activeActivity = _activityForMoment(_now);
    if (activeActivity == null) {
      return;
    }

    final reminderKey = _reminderKeyForActivity(activeActivity, _now);
    if (_confirmedReminderKeys.contains(reminderKey)) {
      return;
    }

    _showActivityReminder(activeActivity, reminderKey);
  }

  Activity? _activityForMoment(DateTime moment) {
    for (final activity in activities) {
      if (_isActivityActiveAt(activity, moment)) {
        return activity;
      }
    }
    return null;
  }

  bool _isActivityActiveAt(Activity activity, DateTime moment) {
    final occurrenceStart = _occurrenceStartFor(activity, moment);
    final occurrenceEnd = occurrenceStart.add(
      Duration(minutes: activity.durationMinutes),
    );
    return !moment.isBefore(occurrenceStart) && moment.isBefore(occurrenceEnd);
  }

  DateTime _occurrenceStartFor(Activity activity, DateTime moment) {
    final dayStart = DateTime(moment.year, moment.month, moment.day);
    var occurrenceStart = dayStart.add(
      Duration(minutes: activity.startMinutes),
    );

    if (activity.endMinutes <= activity.startMinutes) {
      final currentMinutes = moment.hour * 60 + moment.minute;
      if (currentMinutes < activity.endMinutes) {
        occurrenceStart = occurrenceStart.subtract(const Duration(days: 1));
      }
    }

    return occurrenceStart;
  }

  String _reminderKeyForActivity(Activity activity, DateTime moment) {
    final occurrenceStart = _occurrenceStartFor(activity, moment);
    return '${activity.name}|${activity.startMinutes}|${activity.endMinutes}|${occurrenceStart.toIso8601String()}';
  }

  Future<void> _showActivityReminder(
    Activity activity,
    String reminderKey,
  ) async {
    _isReminderDialogVisible = true;
    await NotificationService.instance.showActivityReminder(activity);
    if (!mounted) {
      _isReminderDialogVisible = false;
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Time for an activity'),
          content: Text(
            '${activity.name}\n${activity.timeRangeLabel}\n\nConfirm that you started or completed this activity.',
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    _confirmedReminderKeys.add(reminderKey);
    _isReminderDialogVisible = false;
  }

  int _resolveStartWithoutOverlap({
    required int movingIndex,
    required int desiredStartMinutes,
    required int durationMinutes,
  }) {
    var candidateStart = desiredStartMinutes;

    for (var i = 0; i < activities.length + 2; i++) {
      final candidateEnd = candidateStart + durationMinutes;
      var latestBlockingEnd = -1;

      for (var otherIndex = 0; otherIndex < activities.length; otherIndex++) {
        if (otherIndex == movingIndex) {
          continue;
        }

        for (final interval in _expandedIntervals(activities[otherIndex])) {
          for (final shiftedInterval in _shiftedIntervals(interval)) {
            if (_rangesOverlap(
              candidateStart,
              candidateEnd,
              shiftedInterval.start,
              shiftedInterval.end,
            )) {
              if (shiftedInterval.end > latestBlockingEnd) {
                latestBlockingEnd = shiftedInterval.end;
              }
            }
          }
        }
      }

      if (latestBlockingEnd == -1) {
        return candidateStart % Activity.minutesPerDay;
      }

      candidateStart = latestBlockingEnd;
    }

    return activities[movingIndex].startMinutes;
  }

  List<_MinuteRange> _expandedIntervals(Activity activity) {
    if (activity.endMinutes > activity.startMinutes) {
      return [_MinuteRange(activity.startMinutes, activity.endMinutes)];
    }

    return [
      _MinuteRange(activity.startMinutes, Activity.minutesPerDay),
      _MinuteRange(0, activity.endMinutes),
    ];
  }

  List<_MinuteRange> _shiftedIntervals(_MinuteRange interval) {
    return List.generate(
      4,
      (index) => _MinuteRange(
        interval.start + (index - 1) * Activity.minutesPerDay,
        interval.end + (index - 1) * Activity.minutesPerDay,
      ),
    );
  }

  bool _rangesOverlap(int startA, int endA, int startB, int endB) {
    return startA < endB && startB < endA;
  }

  bool _isOnActivityRing(Offset localPosition, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final distance = (localPosition - center).distance;
    final outerRadius = min(size.width, size.height) / 2;
    final ringWidth = outerRadius * 0.18;
    final innerRadius = outerRadius - ringWidth;
    return distance >= innerRadius - 24 && distance <= outerRadius + 8;
  }

  int _minutesFromOffset(Offset localPosition, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;
    var angle = atan2(dy, dx) + pi / 2;
    if (angle < 0) {
      angle += 2 * pi;
    }

    final rawMinutes =
        (angle / (2 * pi) * Activity.minutesPerDay).round() %
        Activity.minutesPerDay;
    return ((rawMinutes / 5).round() * 5) % Activity.minutesPerDay;
  }

  LinearGradient _backgroundGradientForTime(DateTime time) {
    final hour = time.hour + time.minute / 60;

    if (hour >= 5 && hour < 10) {
      return const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFE39F), Color(0xFFFFD37B), Color(0xFFFFBD66)],
      );
    }

    if (hour >= 10 && hour < 17) {
      return const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFC5E8FF), Color(0xFF97D3FF), Color(0xFF69BCF2)],
      );
    }

    if (hour >= 17 && hour < 21) {
      return const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFC985), Color(0xFFFFA15E), Color(0xFFE1723F)],
      );
    }

    return const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF233A72), Color(0xFF172955), Color(0xFF0C1736)],
    );
  }

  Color _foregroundColorForTime(DateTime time) {
    final hour = time.hour + time.minute / 60;
    return hour >= 21 || hour < 5 ? Colors.white : const Color(0xFF16324A);
  }
}

enum Category { work, meal, relax, rest, custom }

class Activity {
  String name;
  int startMinutes;
  int endMinutes;
  Color color;
  Category category;

  static const int minutesPerDay = 24 * 60;

  Activity(
    this.name,
    this.startMinutes,
    this.endMinutes,
    this.color,
    this.category,
  );

  Activity copy() {
    return Activity(name, startMinutes, endMinutes, color, category);
  }

  double get durationHours => _durationMinutes / 60;
  int get durationMinutes => _durationMinutes;

  String get timeRangeLabel =>
      '${formatMinutes(startMinutes)} - ${formatMinutes(endMinutes)}';

  int get _durationMinutes {
    final diff = endMinutes - startMinutes;
    return diff > 0 ? diff : diff + minutesPerDay;
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'startMinutes': startMinutes,
      'endMinutes': endMinutes,
      'color': color.toARGB32(),
      'category': category.name,
    };
  }

  factory Activity.fromJson(Map<String, dynamic> json) {
    return Activity(
      _displayNameFromStorage(json['name'] as String),
      json['startMinutes'] as int,
      json['endMinutes'] as int,
      Color(json['color'] as int),
      _categoryFromStorage(json['category'] as String),
    );
  }

  static String _displayNameFromStorage(String value) {
    switch (value) {
      case 'Odpoczynek':
      case 'Rest':
        return 'Rest';
      case 'Praca Umysłowa':
      case 'Mental Work':
        return 'Mental Work';
      case 'Praca Fizyczna':
      case 'Physical Work':
        return 'Physical Work';
      case 'Jedzenie':
      case 'Food':
        return 'Food';
      case 'Picie':
      case 'Drink':
        return 'Drink';
      case 'Suplementy':
      case 'Supplements':
        return 'Supplements';
      case 'Relaks':
      case 'Relax':
        return 'Relax';
      default:
        return value;
    }
  }

  static Category _categoryFromStorage(String value) {
    switch (value) {
      case 'workMental':
      case 'workPhysical':
      case 'work':
        return Category.work;
      case 'meal':
        return Category.meal;
      case 'relax':
        return Category.relax;
      case 'sleep':
      case 'rest':
        return Category.rest;
      case 'custom':
        return Category.custom;
      default:
        return Category.custom;
    }
  }

  static String formatMinutes(int totalMinutes) {
    final normalized = totalMinutes % minutesPerDay;
    final hour = (normalized ~/ 60).toString().padLeft(2, '0');
    final minute = (normalized % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class DayPlanTemplate {
  final String id;
  final String name;
  final List<Activity> activities;

  const DayPlanTemplate({
    required this.id,
    required this.name,
    required this.activities,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'activities': activities.map((activity) => activity.toJson()).toList(),
    };
  }

  factory DayPlanTemplate.fromJson(Map<String, dynamic> json) {
    return DayPlanTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      activities: (json['activities'] as List<dynamic>)
          .map((item) => Activity.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

enum _PlanSheetActionType { addActivity, saveTemplate, applyTemplate }

class _PlanSheetAction {
  final _PlanSheetActionType type;
  final DayPlanTemplate? template;

  const _PlanSheetAction._(this.type, [this.template]);

  const _PlanSheetAction.addActivity()
    : this._(_PlanSheetActionType.addActivity);
  const _PlanSheetAction.saveTemplate()
    : this._(_PlanSheetActionType.saveTemplate);
  const _PlanSheetAction.applyTemplate(DayPlanTemplate template)
    : this._(_PlanSheetActionType.applyTemplate, template);
}

class AddActivityScreen extends StatefulWidget {
  final List<Activity> existingActivities;

  const AddActivityScreen({super.key, required this.existingActivities});

  @override
  State<AddActivityScreen> createState() => _AddActivityScreenState();
}

class SaveTemplateScreen extends StatefulWidget {
  const SaveTemplateScreen({super.key});

  @override
  State<SaveTemplateScreen> createState() => _SaveTemplateScreenState();
}

class _SaveTemplateScreenState extends State<SaveTemplateScreen> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      appBar: AppBar(title: const Text('Save template')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + keyboardInset),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 32,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _controller,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      labelText: 'Template name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _submit, child: const Text('Save')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _submit() {
    final value = _controller.text.trim();
    Navigator.of(context).pop(value);
  }
}

class _AddActivityScreenState extends State<AddActivityScreen> {
  Category? selectedCategory;
  String? subType;
  String customName = '';
  int startMinutes = 8 * 60;
  int durationMinutes = 60;
  String addMode = 'single';

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      appBar: AppBar(title: const Text('Add Activity')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + keyboardInset),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 32,
              ),
              child: Column(
                children: [
                  DropdownButton<Category>(
                    value: selectedCategory,
                    hint: const Text('Select Category'),
                    items: Category.values.map((category) {
                      return DropdownMenuItem(
                        value: category,
                        child: Text(_categoryName(category)),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedCategory = value;
                        subType = null;
                        customName = '';
                        addMode = 'single';
                      });
                    },
                  ),
                  if (selectedCategory == Category.work) ...[
                    const SizedBox(height: 16),
                    DropdownButton<String>(
                      value: subType,
                      hint: const Text('Work Type'),
                      items: ['Mental', 'Physical'].map((type) {
                        return DropdownMenuItem(value: type, child: Text(type));
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          subType = value;
                        });
                      },
                    ),
                  ],
                  if (selectedCategory == Category.meal) ...[
                    const SizedBox(height: 16),
                    DropdownButton<String>(
                      value: subType,
                      hint: const Text('Meal Type'),
                      items: ['Food', 'Drink', 'Supplements'].map((type) {
                        return DropdownMenuItem(value: type, child: Text(type));
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          subType = value;
                        });
                      },
                    ),
                  ],
                  if (selectedCategory == Category.meal &&
                      subType == 'Drink') ...[
                    const SizedBox(height: 16),
                    DropdownButton<String>(
                      value: addMode,
                      items: const [
                        DropdownMenuItem(
                          value: 'single',
                          child: Text('Single'),
                        ),
                        DropdownMenuItem(
                          value: 'drink_auto',
                          child: Text('8 times every 1.5h'),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          addMode = value!;
                        });
                      },
                    ),
                  ],
                  if (selectedCategory == Category.meal &&
                      subType == 'Food') ...[
                    const SizedBox(height: 16),
                    DropdownButton<String>(
                      value: addMode,
                      items: const [
                        DropdownMenuItem(
                          value: 'single',
                          child: Text('Single'),
                        ),
                        DropdownMenuItem(
                          value: 'meal_2',
                          child: Text('2 meals'),
                        ),
                        DropdownMenuItem(
                          value: 'meal_3',
                          child: Text('3 meals'),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          addMode = value!;
                        });
                      },
                    ),
                  ],
                  if (selectedCategory == Category.custom) ...[
                    const SizedBox(height: 16),
                    TextField(
                      onChanged: (value) {
                        setState(() {
                          customName = value;
                        });
                      },
                      decoration: const InputDecoration(
                        labelText: 'New activity name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _TimeRangePicker(
                    startMinutes: startMinutes,
                    durationMinutes: durationMinutes,
                    onPickStart: _pickTime,
                    onDurationChanged: (value) {
                      setState(() {
                        durationMinutes = value;
                      });
                    },
                  ),
                  if (_isAutoScheduleMode) ...[
                    const SizedBox(height: 12),
                    Text(
                      _autoScheduleDescription(),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: () {
                      if (_canSubmit()) {
                        final createdActivities = _buildActivitiesToAdd();
                        Navigator.of(context).pop(
                          createdActivities.length == 1
                              ? createdActivities.first
                              : createdActivities,
                        );
                      }
                    },
                    child: const Text('Add'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _categoryName(Category category) {
    switch (category) {
      case Category.work:
        return 'Work';
      case Category.meal:
        return 'Meal';
      case Category.relax:
        return 'Relax';
      case Category.rest:
        return 'Rest';
      case Category.custom:
        return 'Custom';
    }
  }

  String _activityName(Category category, String? subType, String customName) {
    switch (category) {
      case Category.work:
        return subType == 'Physical' ? 'Physical Work' : 'Mental Work';
      case Category.meal:
        return subType ?? 'Food';
      case Category.relax:
        return 'Relax';
      case Category.rest:
        return 'Rest';
      case Category.custom:
        return customName.trim();
    }
  }

  Color _categoryColor(Category category) {
    switch (category) {
      case Category.work:
        return Colors.green;
      case Category.meal:
        return Colors.orange;
      case Category.relax:
        return Colors.purple;
      case Category.rest:
        return Colors.blue;
      case Category.custom:
        return Colors.teal;
    }
  }

  bool _canSubmit() {
    if (selectedCategory == null ||
        durationMinutes < 1 ||
        durationMinutes > 10 * 60) {
      return false;
    }

    if ((selectedCategory == Category.work ||
            selectedCategory == Category.meal) &&
        subType == null) {
      return false;
    }

    if (selectedCategory == Category.custom && customName.trim().isEmpty) {
      return false;
    }

    return true;
  }

  bool get _isAutoScheduleMode => addMode != 'single';

  String _autoScheduleDescription() {
    switch (addMode) {
      case 'drink_auto':
        return 'Adds 8 Drink entries every 1.5 hours from the selected time and skips occupied slots.';
      case 'meal_2':
        return 'Adds 2 meals every 6 hours from the selected time and skips occupied slots.';
      case 'meal_3':
        return 'Adds 3 meals every 4 hours from the selected time and skips occupied slots.';
      default:
        return '';
    }
  }

  List<Activity> _buildActivitiesToAdd() {
    final endMinutes =
        (startMinutes + durationMinutes) % Activity.minutesPerDay;
    final baseActivity = Activity(
      _activityName(selectedCategory!, subType, customName),
      startMinutes,
      endMinutes,
      _categoryColor(selectedCategory!),
      selectedCategory!,
    );

    if (!_isAutoScheduleMode) {
      return [baseActivity];
    }

    final plannedActivities = <Activity>[];
    final occupiedActivities = [
      ...widget.existingActivities.map((activity) => activity.copy()),
    ];

    final itemCount = addMode == 'drink_auto'
        ? 8
        : addMode == 'meal_2'
        ? 2
        : 3;
    final intervalMinutes = addMode == 'drink_auto'
        ? 90
        : addMode == 'meal_2'
        ? 360
        : 240;

    for (var i = 0; i < itemCount; i++) {
      final preferredStart =
          (startMinutes + i * intervalMinutes) % Activity.minutesPerDay;
      final scheduledStart = _findNextAvailableStart(
        occupiedActivities: occupiedActivities,
        preferredStartMinutes: preferredStart,
        durationMinutes: baseActivity.durationMinutes,
      );

      if (scheduledStart == null) {
        continue;
      }

      final activity = Activity(
        baseActivity.name,
        scheduledStart,
        (scheduledStart + baseActivity.durationMinutes) %
            Activity.minutesPerDay,
        baseActivity.color,
        baseActivity.category,
      );
      plannedActivities.add(activity);
      occupiedActivities.add(activity.copy());
    }

    if (plannedActivities.isEmpty) {
      return [baseActivity];
    }

    return plannedActivities;
  }

  int? _findNextAvailableStart({
    required List<Activity> occupiedActivities,
    required int preferredStartMinutes,
    required int durationMinutes,
  }) {
    final normalizedPreferred = preferredStartMinutes % Activity.minutesPerDay;

    for (var offset = 0; offset < Activity.minutesPerDay; offset += 5) {
      final candidateStart =
          (normalizedPreferred + offset) % Activity.minutesPerDay;
      final candidateEnd =
          (candidateStart + durationMinutes) % Activity.minutesPerDay;

      if (!_hasOverlap(occupiedActivities, candidateStart, candidateEnd)) {
        return candidateStart;
      }
    }

    return null;
  }

  bool _hasOverlap(
    List<Activity> occupiedActivities,
    int startMinutes,
    int endMinutes,
  ) {
    final candidateRanges = _expandedRanges(startMinutes, endMinutes);

    for (final activity in occupiedActivities) {
      final occupiedRanges = _expandedRanges(
        activity.startMinutes,
        activity.endMinutes,
      );

      for (final candidate in candidateRanges) {
        for (final occupied in occupiedRanges) {
          for (final shifted in _shiftRanges(occupied)) {
            if (_rangesOverlap(
              candidate.start,
              candidate.end,
              shifted.start,
              shifted.end,
            )) {
              return true;
            }
          }
        }
      }
    }

    return false;
  }

  List<_MinuteRange> _expandedRanges(int start, int end) {
    if (end > start) {
      return [_MinuteRange(start, end)];
    }

    return [_MinuteRange(start, Activity.minutesPerDay), _MinuteRange(0, end)];
  }

  List<_MinuteRange> _shiftRanges(_MinuteRange range) {
    return List.generate(
      3,
      (index) => _MinuteRange(
        range.start + (index - 1) * Activity.minutesPerDay,
        range.end + (index - 1) * Activity.minutesPerDay,
      ),
    );
  }

  bool _rangesOverlap(int startA, int endA, int startB, int endB) {
    return startA < endB && startB < endA;
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: startMinutes ~/ 60,
        minute: startMinutes % 60,
      ),
    );
    if (picked == null) {
      return;
    }

    setState(() {
      startMinutes = picked.hour * 60 + picked.minute;
    });
  }
}

class EditActivityScreen extends StatefulWidget {
  final Activity activity;

  const EditActivityScreen({super.key, required this.activity});

  @override
  State<EditActivityScreen> createState() => _EditActivityScreenState();
}

class _EditActivityScreenState extends State<EditActivityScreen> {
  late Category selectedCategory;
  String? subType;
  late TextEditingController customNameController;
  late int startMinutes;
  late int durationMinutes;

  @override
  void initState() {
    super.initState();
    selectedCategory = widget.activity.category;
    startMinutes = widget.activity.startMinutes;
    durationMinutes = widget.activity.durationMinutes;
    customNameController = TextEditingController();
    if (selectedCategory == Category.work) {
      subType = widget.activity.name == 'Physical Work' ? 'Physical' : 'Mental';
    } else if (selectedCategory == Category.meal) {
      if (['Food', 'Drink', 'Supplements'].contains(widget.activity.name)) {
        subType = widget.activity.name;
      }
    } else if (selectedCategory == Category.custom) {
      customNameController.text = widget.activity.name;
    }
  }

  @override
  void dispose() {
    customNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Activity')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + keyboardInset),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 32,
              ),
              child: Column(
                children: [
                  DropdownButton<Category>(
                    value: selectedCategory,
                    items: Category.values.map((category) {
                      return DropdownMenuItem(
                        value: category,
                        child: Text(_categoryName(category)),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedCategory = value!;
                        subType = null;
                        if (selectedCategory != Category.custom) {
                          customNameController.clear();
                        }
                      });
                    },
                  ),
                  if (selectedCategory == Category.work) ...[
                    const SizedBox(height: 16),
                    DropdownButton<String>(
                      value: subType,
                      hint: const Text('Work Type'),
                      items: ['Mental', 'Physical'].map((type) {
                        return DropdownMenuItem(value: type, child: Text(type));
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          subType = value;
                        });
                      },
                    ),
                  ],
                  if (selectedCategory == Category.meal) ...[
                    const SizedBox(height: 16),
                    DropdownButton<String>(
                      value: subType,
                      hint: const Text('Meal Type'),
                      items: ['Food', 'Drink', 'Supplements'].map((type) {
                        return DropdownMenuItem(value: type, child: Text(type));
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          subType = value;
                        });
                      },
                    ),
                  ],
                  if (selectedCategory == Category.custom) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: customNameController,
                      decoration: const InputDecoration(
                        labelText: 'New activity name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _TimeRangePicker(
                    startMinutes: startMinutes,
                    durationMinutes: durationMinutes,
                    onPickStart: _pickTime,
                    onDurationChanged: (value) {
                      setState(() {
                        durationMinutes = value;
                      });
                    },
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: () {
                      if (!_canSubmit()) {
                        return;
                      }
                      final endMinutes =
                          (startMinutes + durationMinutes) %
                          Activity.minutesPerDay;
                      final editedActivity = Activity(
                        _activityName(
                          selectedCategory,
                          subType,
                          customNameController.text,
                        ),
                        startMinutes,
                        endMinutes,
                        _categoryColor(selectedCategory),
                        selectedCategory,
                      );
                      Navigator.of(context).pop(editedActivity);
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _categoryName(Category category) {
    switch (category) {
      case Category.work:
        return 'Work';
      case Category.meal:
        return 'Meal';
      case Category.relax:
        return 'Relax';
      case Category.rest:
        return 'Rest';
      case Category.custom:
        return 'Custom';
    }
  }

  String _activityName(Category category, String? subType, String customName) {
    switch (category) {
      case Category.work:
        return subType == 'Physical' ? 'Physical Work' : 'Mental Work';
      case Category.meal:
        return subType ?? 'Food';
      case Category.relax:
        return 'Relax';
      case Category.rest:
        return 'Rest';
      case Category.custom:
        return customName.trim();
    }
  }

  Color _categoryColor(Category category) {
    switch (category) {
      case Category.work:
        return Colors.green;
      case Category.meal:
        return Colors.orange;
      case Category.relax:
        return Colors.purple;
      case Category.rest:
        return Colors.blue;
      case Category.custom:
        return Colors.teal;
    }
  }

  bool _canSubmit() {
    if (durationMinutes < 1 || durationMinutes > 10 * 60) {
      return false;
    }

    if ((selectedCategory == Category.work ||
            selectedCategory == Category.meal) &&
        subType == null) {
      return false;
    }

    if (selectedCategory == Category.custom &&
        customNameController.text.trim().isEmpty) {
      return false;
    }

    return true;
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: startMinutes ~/ 60,
        minute: startMinutes % 60,
      ),
    );
    if (picked == null) {
      return;
    }

    setState(() {
      startMinutes = picked.hour * 60 + picked.minute;
    });
  }
}

class _TimeRangePicker extends StatefulWidget {
  final int startMinutes;
  final int durationMinutes;
  final VoidCallback onPickStart;
  final ValueChanged<int> onDurationChanged;

  const _TimeRangePicker({
    required this.startMinutes,
    required this.durationMinutes,
    required this.onPickStart,
    required this.onDurationChanged,
  });

  @override
  State<_TimeRangePicker> createState() => _TimeRangePickerState();
}

class _TimeRangePickerState extends State<_TimeRangePicker> {
  late FixedExtentScrollController _hoursController;
  late FixedExtentScrollController _minutesController;

  @override
  void initState() {
    super.initState();
    _hoursController = FixedExtentScrollController(
      initialItem: widget.durationMinutes ~/ 60,
    );
    _minutesController = FixedExtentScrollController(
      initialItem: widget.durationMinutes % 60,
    );
  }

  @override
  void didUpdateWidget(covariant _TimeRangePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.durationMinutes != widget.durationMinutes) {
      final hours = widget.durationMinutes ~/ 60;
      final minutes = widget.durationMinutes % 60;
      if (_hoursController.selectedItem != hours) {
        _hoursController.jumpToItem(hours);
      }
      if (_minutesController.selectedItem != minutes) {
        _minutesController.jumpToItem(minutes);
      }
    }
  }

  @override
  void dispose() {
    _hoursController.dispose();
    _minutesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final endMinutes =
        (widget.startMinutes + widget.durationMinutes) % Activity.minutesPerDay;
    final durationHours = widget.durationMinutes / 60;
    final selectedHours = widget.durationMinutes ~/ 60;
    final selectedMinutes = widget.durationMinutes % 60;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Time Range', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 160,
              child: OutlinedButton(
                onPressed: widget.onPickStart,
                child: Text(
                  'From: ${Activity.formatMinutes(widget.startMinutes)}',
                ),
              ),
            ),
            SizedBox(
              width: 160,
              child: OutlinedButton(
                onPressed: null,
                child: Text('To: ${Activity.formatMinutes(endMinutes)}'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Duration: ${_formatDuration(widget.durationMinutes)} (${durationHours.toStringAsFixed(1)} hours)',
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(120),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildWheel(
                  controller: _hoursController,
                  itemCount: 11,
                  selectedItem: selectedHours,
                  labelBuilder: (index) => index == 1 ? '1 hr' : '$index hrs',
                  onSelectedItemChanged: (hours) {
                    _updateDuration(hours, selectedMinutes);
                  },
                ),
              ),
              Expanded(
                child: _buildWheel(
                  controller: _minutesController,
                  itemCount: 60,
                  selectedItem: selectedMinutes,
                  labelBuilder: (index) => index.toString().padLeft(2, '0'),
                  onSelectedItemChanged: (minutes) {
                    _updateDuration(selectedHours, minutes);
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWheel({
    required FixedExtentScrollController controller,
    required int itemCount,
    required int selectedItem,
    required String Function(int index) labelBuilder,
    required ValueChanged<int> onSelectedItemChanged,
  }) {
    return SizedBox(
      height: 160,
      child: CupertinoPicker(
        scrollController: controller,
        itemExtent: 36,
        magnification: 1.05,
        useMagnifier: true,
        squeeze: 1.1,
        selectionOverlay: CupertinoPickerDefaultSelectionOverlay(
          background: Colors.blue.withAlpha(20),
        ),
        onSelectedItemChanged: onSelectedItemChanged,
        children: List.generate(
          itemCount,
          (index) => Center(
            child: Text(
              labelBuilder(index),
              style: TextStyle(
                fontWeight: index == selectedItem
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _updateDuration(int hours, int minutes) {
    var nextHours = hours;
    var nextMinutes = minutes;

    if (nextHours == 0 && nextMinutes == 0) {
      nextMinutes = 1;
      _minutesController.jumpToItem(nextMinutes);
    }

    if (nextHours == 10 && nextMinutes > 0) {
      nextMinutes = 0;
      _minutesController.jumpToItem(nextMinutes);
    }

    final nextDuration = nextHours * 60 + nextMinutes;
    widget.onDurationChanged(nextDuration.clamp(1, 600));
  }

  String _formatDuration(int totalMinutes) {
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;

    if (hours == 0) {
      return '$minutes min';
    }

    if (minutes == 0) {
      return hours == 1 ? '1 hr' : '$hours hrs';
    }

    final hourLabel = hours == 1 ? '1 hr' : '$hours hrs';
    return '$hourLabel $minutes min';
  }
}

class _MinuteRange {
  final int start;
  final int end;

  const _MinuteRange(this.start, this.end);
}
