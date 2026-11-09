import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

const Color purple = Color(0xFFB56CFF);
const Color lightPurple = Color(0xFF2B2038);
const Color palePurple = Color(0xFFF0E6FF);
final ValueNotifier<bool> darkModeNotifier = ValueNotifier<bool>(true);

const int dailyGoal = 10000;
const List<int> milestones = [2500, 5000, 7500, 10000];

String dateKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

final FlutterLocalNotificationsPlugin localNotifications =
    FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(StepTaskHandler());
}

class StepTaskHandler extends TaskHandler {
  StreamSubscription<StepCount>? subscription;

  int todaySteps = 0;
  int? lastRaw;
  String currentDate = '';

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    currentDate = dateKey(DateTime.now());

    final savedDate =
        await FlutterForegroundTask.getData(key: 'step_date') as String?;

    todaySteps =
        await FlutterForegroundTask.getData(key: 'today_steps') as int? ?? 0;

    lastRaw = await FlutterForegroundTask.getData(key: 'last_raw') as int?;

    if (savedDate != currentDate) {
      todaySteps = 0;
      lastRaw = null;
      await FlutterForegroundTask.saveData(
        key: 'step_date',
        value: currentDate,
      );
      await FlutterForegroundTask.saveData(key: 'today_steps', value: 0);
    }

    await localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );

    subscription = Pedometer.stepCountStream.listen(
      (event) async {
        final raw = event.steps;
        final today = dateKey(DateTime.now());

        if (today != currentDate) {
          currentDate = today;
          todaySteps = 0;
          lastRaw = raw;
        } else if (lastRaw == null) {
          lastRaw = raw;
        } else if (raw >= lastRaw!) {
          todaySteps += raw - lastRaw!;
          lastRaw = raw;
        } else {
          // Sensor counter restarted after a device reboot.
          lastRaw = raw;
        }

        await FlutterForegroundTask.saveData(
          key: 'step_date',
          value: currentDate,
        );
        await FlutterForegroundTask.saveData(
          key: 'today_steps',
          value: todaySteps,
        );
        await FlutterForegroundTask.saveData(key: 'last_raw', value: lastRaw!);
        await FlutterForegroundTask.saveData(
          key: 'history_$currentDate',
          value: todaySteps,
        );

        final prefs = await SharedPreferences.getInstance();
        final showStepCount = prefs.getBool('background_notifications') ?? true;
        FlutterForegroundTask.updateService(
          notificationTitle: 'Step Tracker',
          notificationText: showStepCount
              ? '$todaySteps steps completed today'
              : 'Background step tracking is active',
        );

        for (final milestone in milestones) {
          if (todaySteps >= milestone) {
            final key = 'alert_${currentDate}_$milestone';
            final alreadySent =
                await FlutterForegroundTask.getData(key: key) as bool? ?? false;

            final prefs = await SharedPreferences.getInstance();
            final milestoneEnabled = prefs.getBool('milestone_notifications') ?? true;
            if (!alreadySent && milestoneEnabled) {
              await localNotifications.show(
                milestone,
                'Step Tracker',
                'You have reached $milestone steps today. Keep it up!',
                const NotificationDetails(
                  android: AndroidNotificationDetails(
                    'step_channel',
                    'Step Tracker Notifications',
                    channelDescription: 'Daily step milestone alerts',
                    importance: Importance.high,
                    priority: Priority.high,
                  ),
                ),
              );

              await FlutterForegroundTask.saveData(key: key, value: true);
            }
          }
        }

        FlutterForegroundTask.sendDataToMain({
          'steps': todaySteps,
          'date': currentDate,
        });
      },
      onError: (error) {
        FlutterForegroundTask.sendDataToMain({'error': error.toString()});
      },
    );
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await subscription?.cancel();
    subscription = null;
  }
}

Future<void> initializeForegroundService() async {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'step_tracking',
      channelName: 'Step Tracking',
      channelDescription: 'Background step tracking is active',
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(5000),
      autoRunOnBoot: false,
      allowWakeLock: true,
    ),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterForegroundTask.initCommunicationPort();
  await initializeForegroundService();

  runApp(const StepTrackerApp());
}

class StepTrackerApp extends StatelessWidget {
  const StepTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: darkModeNotifier,
      builder: (context, isDark, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Step Tracker',
        themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          colorScheme: ColorScheme.fromSeed(seedColor: purple, brightness: Brightness.light),
          scaffoldBackgroundColor: const Color(0xFFF7F5FA),
          appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF6F35A5), foregroundColor: Colors.white),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: const ColorScheme.dark(primary: Color(0xFFB86CFF), secondary: Color(0xFFD6B5FF), surface: Color(0xFF21182B), onSurface: Colors.white, onSurfaceVariant: Color(0xFFD0C6D8)),
          scaffoldBackgroundColor: Colors.black,
          appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF24172F), foregroundColor: Colors.white),
          navigationBarTheme: const NavigationBarThemeData(backgroundColor: Color(0xFF17121D), indicatorColor: Color(0xFF49305F)),
        ),
        home: const MainScreen(),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int selectedTab = 0;
  int steps = 0;
  int goal = dailyGoal;
  bool tracking = false;
  String profileName = '';
  String profileAge = '';
  String profileHeight = '';
  String profileWeight = '';
  String profileGender = 'Prefer not to say';
  String? profileImagePath;
  double strideLength = 0.70;
  bool milestoneNotifications = true;
  bool backgroundNotifications = true;
  final ImagePicker imagePicker = ImagePicker();

  final List<int> weeklySteps = List.filled(7, 0);

  @override
  void initState() {
    super.initState();
    FlutterForegroundTask.addTaskDataCallback(onTaskData);
    loadSavedData();
    checkService();
  }

  Future<void> loadSavedData() async {
    final saved =
        await FlutterForegroundTask.getData(key: 'today_steps') as int?;
    final savedGoal =
        await FlutterForegroundTask.getData(key: 'daily_goal') as int?;

    final prefs = await SharedPreferences.getInstance();
    profileName = prefs.getString('profile_name') ?? '';
    profileAge = prefs.getString('profile_age') ?? '';
    profileHeight = prefs.getString('profile_height') ?? '';
    profileWeight = prefs.getString('profile_weight') ?? '';
    profileGender = prefs.getString('profile_gender') ?? 'Prefer not to say';
    profileImagePath = prefs.getString('profile_image');
    strideLength = prefs.getDouble('stride_length') ?? 0.70;
    milestoneNotifications = prefs.getBool('milestone_notifications') ?? true;
    backgroundNotifications = prefs.getBool('background_notifications') ?? true;
    darkModeNotifier.value = prefs.getBool('dark_mode') ?? true;

    final now = DateTime.now();

    for (int i = 0; i < 7; i++) {
      final date = DateTime(now.year, now.month, now.day - (6 - i));
      final value = await FlutterForegroundTask.getData(
        key: 'history_${dateKey(date)}',
      );

      weeklySteps[i] = value as int? ?? 0;
    }

    if (!mounted) return;

    setState(() {
      steps = saved ?? 0;
      goal = savedGoal ?? dailyGoal;
    });
  }

  void onTaskData(Object data) {
    if (!mounted) return;

    if (data is Map && data['steps'] is int) {
      setState(() {
        steps = data['steps'] as int;
      });
      loadWeeklyData();
    }
  }

  Future<void> loadWeeklyData() async {
    final now = DateTime.now();
    for (int i = 0; i < 7; i++) {
      final date = DateTime(now.year, now.month, now.day - (6 - i));
      final value = await FlutterForegroundTask.getData(
        key: 'history_${dateKey(date)}',
      );
      weeklySteps[i] = value as int? ?? 0;
    }
    if (mounted) setState(() {});
  }

  Future<void> checkService() async {
    final running = await FlutterForegroundTask.isRunningService;
    if (mounted) setState(() => tracking = running);
  }

  Future<void> startTracking() async {
    final activity = await Permission.activityRecognition.request();

    if (!activity.isGranted) {
      showMessage('Please allow Physical Activity permission.');
      return;
    }

    final notification =
        await FlutterForegroundTask.checkNotificationPermission();

    if (notification != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.restartService();
    } else {
      await FlutterForegroundTask.startService(
        serviceId: 256,
        notificationTitle: 'Step Tracker',
        notificationText: 'Background step tracking is active',
        callback: startCallback,
      );
    }

    await checkService();
  }

  Future<void> stopTracking() async {
    await FlutterForegroundTask.stopService();
    await checkService();
  }

  void showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> changeGoal() async {
    final controller = TextEditingController(text: goal.toString());

    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Daily Step Goal'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Enter your step goal'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context, int.tryParse(controller.text));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result > 0) {
      await FlutterForegroundTask.saveData(key: 'daily_goal', value: result);
      if (mounted) setState(() => goal = result);
    }
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(onTaskData);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [dashboard(), statistics(), history(), profile()];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: purple,
        foregroundColor: Colors.white,
        title: const Text(
          'Step Tracker',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: tracking ? stopTracking : startTracking,
            icon: Icon(tracking ? Icons.pause_circle : Icons.play_circle),
            tooltip: tracking ? 'Stop tracking' : 'Start tracking',
          ),
        ],
      ),
      body: pages[selectedTab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedTab,
        onDestinationSelected: (index) => setState(() => selectedTab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Stats'),
          NavigationDestination(icon: Icon(Icons.history), label: 'History'),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget dashboard() {
    final progress = (steps / goal).clamp(0.0, 1.0);
    final distance = steps * strideLength / 1000;
    final calories = steps * 0.04;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Today’s Activity',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            children: [
              SizedBox(
                height: 210,
                width: 210,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 15,
                        backgroundColor: palePurple,
                        valueColor: const AlwaysStoppedAnimation(purple),
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.directions_walk,
                          color: purple,
                          size: 38,
                        ),
                        Text(
                          '$steps',
                          style: const TextStyle(
                            fontSize: 56,
                            fontWeight: FontWeight.bold,
                            color: purple,
                          ),
                        ),
                        const Text('Steps'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '${(progress * 100).toStringAsFixed(1)}% of your daily goal',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text('Daily goal: $goal steps'),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: metricCard(
                Icons.route,
                'Distance',
                '${distance.toStringAsFixed(2)} km',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: metricCard(
                Icons.local_fire_department,
                'Calories',
                '${calories.toStringAsFixed(0)} kcal',
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: palePurple,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Icon(
                tracking ? Icons.check_circle : Icons.info_outline,
                color: purple,
                size: 30,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  tracking
                      ? 'Background tracking is active.'
                      : 'Start tracking to count steps in the background.',
                  style: const TextStyle(color: Colors.black, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        ElevatedButton.icon(
          onPressed: tracking ? stopTracking : startTracking,
          icon: Icon(tracking ? Icons.stop : Icons.play_arrow),
          label: Text(tracking ? 'Stop Tracking' : 'Start Tracking'),
          style: ElevatedButton.styleFrom(
            backgroundColor: purple,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.all(16),
          ),
        ),
      ],
    );
  }

  Widget metricCard(IconData icon, String title, String value) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: purple, size: 30),
          const SizedBox(height: 12),
          Text(title, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ],
      ),
    );
  }

  Widget statistics() {
    final maxSteps = weeklySteps.fold<int>(
      goal > 0 ? goal : 1,
      (previous, value) => value > previous ? value : previous,
    );

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Weekly Statistics',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 25),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              const Text('Steps in the last 7 days'),
              const SizedBox(height: 25),
              SizedBox(
                height: 190,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(7, (index) {
                    final value = weeklySteps[index];
                    final height = value / maxSteps * 140;
                    final date = DateTime.now().subtract(
                      Duration(days: 6 - index),
                    );

                    return Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            value > 0 ? '$value' : '0',
                            style: const TextStyle(fontSize: 10),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            height: height.clamp(4.0, 140.0),
                            width: 18,
                            decoration: BoxDecoration(
                              color: purple,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            ['M', 'T', 'W', 'T', 'F', 'S', 'S'][date.weekday -
                                1],
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        metricCard(Icons.directions_walk, 'Today', '$steps steps'),
      ],
    );
  }

  Widget history() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Activity History',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 18),
        ...List.generate(7, (index) {
          final date = DateTime.now().subtract(Duration(days: 6 - index));
          final value = weeklySteps[index];

          return Card(
            color: Theme.of(context).colorScheme.surface,
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: palePurple,
                child: Icon(Icons.directions_walk, color: purple),
              ),
              title: Text(dateKey(date)),
              subtitle: Text('$value steps'),
              trailing: Icon(
                value >= goal ? Icons.emoji_events : Icons.chevron_right,
                color: purple,
              ),
            ),
          );
        }),
      ],
    );
  }

  Future<void> pickProfilePhoto() async {
    final file = await imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 900);
    if (file == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_image', file.path);
    if (mounted) setState(() => profileImagePath = file.path);
  }

  Future<void> editProfile() async {
    final name = TextEditingController(text: profileName);
    final age = TextEditingController(text: profileAge);
    final height = TextEditingController(text: profileHeight);
    final weight = TextEditingController(text: profileWeight);
    String gender = profileGender;
    final saved = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Edit Profile'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
          TextField(controller: age, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Age')),
          TextField(controller: height, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Height (cm)')),
          TextField(controller: weight, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Weight (kg)')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(initialValue: gender, decoration: const InputDecoration(labelText: 'Gender'), items: const [
            DropdownMenuItem(value: 'Female', child: Text('Female')),
            DropdownMenuItem(value: 'Male', child: Text('Male')),
            DropdownMenuItem(value: 'Non-binary', child: Text('Non-binary')),
            DropdownMenuItem(value: 'Prefer not to say', child: Text('Prefer not to say')),
          ], onChanged: (value) { if (value != null) setDialogState(() => gender = value); }),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save'))],
      ),
    ));
    if (saved == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profile_name', name.text.trim());
      await prefs.setString('profile_age', age.text.trim());
      await prefs.setString('profile_height', height.text.trim());
      await prefs.setString('profile_weight', weight.text.trim());
      await prefs.setString('profile_gender', gender);
      if (!mounted) return;
      setState(() { profileName = name.text.trim(); profileAge = age.text.trim(); profileHeight = height.text.trim(); profileWeight = weight.text.trim(); profileGender = gender; });
    }
    name.dispose(); age.dispose(); height.dispose(); weight.dispose();
  }

  Future<void> editStride() async {
    final controller = TextEditingController(text: strideLength.toStringAsFixed(2));
    final value = await showDialog<double>(context: context, builder: (context) => AlertDialog(
      title: const Text('Stride Length'),
      content: TextField(controller: controller, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Stride length in metres', hintText: 'Example: 0.70')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, double.tryParse(controller.text)), child: const Text('Save'))],
    ));
    if (value != null && value > 0 && value < 2) {
      final prefs = await SharedPreferences.getInstance(); await prefs.setDouble('stride_length', value);
      if (mounted) setState(() => strideLength = value);
    }
    controller.dispose();
  }

  Future<void> togglePreference(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance(); await prefs.setBool(key, value);
    if (!mounted) return;
    setState(() { if (key == 'milestone_notifications') milestoneNotifications = value; if (key == 'background_notifications') backgroundNotifications = value; });
  }

  Future<void> logout() async {
    final confirm = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Log out?'), content: const Text('This app has no account sign-in yet. Logging out will clear locally saved profile details and photo, but keep step history.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear profile'))],
    ));
    if (confirm != true) return;
    final prefs = await SharedPreferences.getInstance();
    for (final key in ['profile_name','profile_age','profile_height','profile_weight','profile_gender','profile_image']) { await prefs.remove(key); }
    if (!mounted) return;
    setState(() { profileName=''; profileAge=''; profileHeight=''; profileWeight=''; profileGender='Prefer not to say'; profileImagePath=null; });
  }

  Widget profile() {
    final hasPhoto = profileImagePath != null && File(profileImagePath!).existsSync();
    final isDark = darkModeNotifier.value;
    return ListView(padding: const EdgeInsets.all(20), children: [
      Center(child: Column(children: [
        GestureDetector(onTap: pickProfilePhoto, child: CircleAvatar(radius:  50, backgroundColor: const Color(0xFF49305F), backgroundImage: hasPhoto ? FileImage(File(profileImagePath!)) : null, child: hasPhoto ? null : const Icon(Icons.person, color: Colors.white, size: 54))),
        const SizedBox(height: 10), Text(profileName.isEmpty ? 'My Profile' : profileName, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
        TextButton.icon(onPressed: pickProfilePhoto, icon: const Icon(Icons.photo_camera), label: const Text('Change profile photo')),
      ])),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: editProfile, icon: const Icon(Icons.edit), label: const Text('Edit Profile')),
      const SizedBox(height: 12),
      Card(child: Column(children: [
        ListTile(leading: const Icon(Icons.badge_outlined), title: const Text('Personal details'), subtitle: Text('Age: ${profileAge.isEmpty ? 'Not set' : profileAge}  •  Height: ${profileHeight.isEmpty ? 'Not set' : '$profileHeight cm'}  •  Weight: ${profileWeight.isEmpty ? 'Not set' : '$profileWeight kg'}\nGender: $profileGender')),
        const Divider(height: 1),
        ListTile(leading: const Icon(Icons.flag), title: const Text('Daily step goal'), subtitle: Text('$goal steps'), trailing: const Icon(Icons.edit), onTap: changeGoal),
        const Divider(height: 1),
        ListTile(leading: const Icon(Icons.straighten), title: const Text('Stride length'), subtitle: Text('${strideLength.toStringAsFixed(2)} metres'), trailing: const Icon(Icons.edit), onTap: editStride),
      ])),
      const SizedBox(height: 12),
      Text('Settings', style: Theme.of(context).textTheme.titleLarge),
      Card(child: SwitchListTile(secondary: const Icon(Icons.dark_mode), title: const Text('Dark mode'), value: isDark, onChanged: (value) async { final prefs = await SharedPreferences.getInstance(); await prefs.setBool('dark_mode', value); darkModeNotifier.value = value; setState(() {}); })),
      const Card(child: ListTile(leading: Icon(Icons.notifications_active), title: Text('Background tracking notification'), subtitle: Text('Android requires a persistent notification while the foreground step-tracking service is running.'))),
      Card(child: SwitchListTile(secondary: const Icon(Icons.emoji_events), title: const Text('Milestone notifications'), subtitle: const Text('Alerts at 2,500, 5,000, 7,500 and 10,000 steps'), value: milestoneNotifications, onChanged: (value) => togglePreference('milestone_notifications', value))),
      const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: logout, icon: const Icon(Icons.logout), label: const Text('Logout / Clear Profile')),
      const SizedBox(height: 12),
      Text('Distance is estimated from your stride length. Calorie values are approximate.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}
